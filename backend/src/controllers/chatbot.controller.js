const chatbotService = require('../services/chatbot/chatbot.service');
const chatbotRepository = require('../repositories/chatbot.repository');
const entitlementService = require('../services/entitlement.service');
const { ERROR_CODES } = require('../config/billing');
const { error } = require('../utils/response');

/**
 * Reply to a replayed request from what was already produced.
 *
 * A client that retries after a network timeout must not trigger a second AI
 * call or a second charge, so the original conversation's latest assistant
 * message is returned instead. This is best-effort: if the conversation cannot
 * be resolved the caller still gets a non-error response rather than an
 * accidental duplicate.
 */
async function replayResponse(ledger) {
    if (!ledger?.reference_id) return null;
    const messages = await chatbotRepository.findMessagesByConversationId(ledger.reference_id, { limit: 50 });
    const lastBot = [...messages].reverse().find((m) => m.message_type === 'bot');
    if (!lastBot) return null;

    return {
        conversationId: ledger.reference_id,
        reply: lastBot.message_text,
        intent: lastBot.intent || null,
        confidence: lastBot.confidence_score || 0,
        places: lastBot.metadata?.places || [],
        clinics: [],
        doctors: [],
        route: null,
        suggestions: [],
        duplicate: true,
    };
}

exports.sendMessage = async (req, res) => {
    let reservation = null;

    try {
        const { message, conversationId, latitude, longitude } = req.body;

        // Optional client-supplied idempotency key. Bounded in length because
        // it reaches a VARCHAR(64) unique index; an oversized value is dropped
        // rather than rejected, so an older client keeps working.
        const rawRequestId = req.body.client_message_id || req.body.request_id;
        const clientRequestId = typeof rawRequestId === 'string' && rawRequestId.length <= 64 && rawRequestId.length > 0
            ? rawRequestId
            : null;

        // Global auth gate: this route is already behind authenticate, so a
        // user is always present. Entitlement is keyed on that id and never on
        // anything the client sends.
        const userId = req.user?.sub || null;

        if (!message) {
            return res.status(400).json({
                success: false,
                error: { message: 'Message is required' },
            });
        }

        // Quota is reserved BEFORE the AI is called. Doing it afterwards would
        // let concurrent requests all pass the check and overspend the limit.
        reservation = await entitlementService.reserveChatbotMessage({
            userId,
            clientRequestId,
            conversationId: conversationId || null,
        });

        if (!reservation.allowed) {
            if (reservation.code === ERROR_CODES.DUPLICATE_IN_FLIGHT) {
                return error(
                    res,
                    'This message is already being processed.',
                    409,
                    ERROR_CODES.DUPLICATE_IN_FLIGHT,
                    reservation.meta
                );
            }
            return error(
                res,
                'Your free messages are used for this period.',
                429,
                ERROR_CODES.FREE_QUOTA_EXHAUSTED,
                reservation.meta
            );
        }

        // A replay of a request that already completed: answer from what was
        // produced the first time. No second AI call, no second quota unit.
        if (reservation.replay) {
            const settled = await entitlementService.findSettledRequest(userId, clientRequestId);
            const replayed = await replayResponse(settled);
            if (replayed) {
                return res.json({ success: true, data: replayed });
            }

            // The original answer can no longer be reconstructed (the
            // conversation was deleted, say). Re-running the AI is acceptable,
            // but it is new work and must be paid for — the settled row cannot
            // be charged twice, so a fresh unit is taken instead. Without this
            // the fall-through would be an unmetered AI call.
            reservation = await entitlementService.reserveChatbotMessage({
                userId,
                clientRequestId: null,
                conversationId: conversationId || null,
            });
            if (!reservation.allowed) {
                return error(
                    res,
                    'Your free messages are used for this period.',
                    429,
                    ERROR_CODES.FREE_QUOTA_EXHAUSTED,
                    reservation.meta
                );
            }
        }

        const result = await chatbotService.processMessage({
            message,
            conversationId,
            userId,
            latitude,
            longitude,
        });

        // chatbot.service catches its own failures and returns a fallback reply
        // rather than throwing, so the sentinel intent is what distinguishes a
        // real answer from a failed one. Releasing on failure is what stops a
        // broken AI call from permanently costing the user a message.
        const failed = result.intent === 'error';
        await entitlementService.settleChatbotMessage(
            reservation.ledgerId,
            failed ? 'released' : 'consumed',
            failed ? null : result.conversationId
        );

        // Quota state as it stood when this message was accepted. A released
        // (failed) message did not spend anything, so its reservation is added
        // back to what the client is told remains.
        const quota = reservation.meta
            ? {
                used: failed ? Math.max(reservation.meta.used - 1, 0) : reservation.meta.used,
                limit: reservation.meta.limit,
                remaining: reservation.meta.remaining === null
                    ? null
                    : reservation.meta.remaining + (failed ? 1 : 0),
                resets_at: reservation.meta.resets_at,
                unlimited: reservation.meta.limit === null,
            }
            : null;

        reservation = null;

        return res.json({
            success: true,
            data: { ...result, quota },
        });
    } catch (err) {
        // Any unexpected failure hands the reservation back before surfacing.
        if (reservation?.ledgerId) {
            await entitlementService.settleChatbotMessage(reservation.ledgerId, 'released').catch(() => {});
        }

        console.error('CONTROLLER ERROR:', err);

        return res.status(500).json({
            success: false,
            error: {
                message: 'Internal server error',
            },
        });
    }
};
