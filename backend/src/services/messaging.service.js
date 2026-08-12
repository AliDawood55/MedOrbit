const db = require('../config/database');
const { createAudit } = require('./audit.service');
const { recordUserEvent } = require('./userEvent.service');
const { enqueueOutboxEvent } = require('./outbox.service');
const { emitMessageCreated, emitToConversation } = require('./realtime.service');
const {
    MessagingPolicyError,
    resolveMessagingActor,
    resolveCounterpart,
    findActiveRelationship,
    getConversationAccess,
} = require('./messagingPolicy.service');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUEST_COOLDOWN_DAYS = 30;
const MAX_NEW_PATIENT_REQUESTS_PER_DAY = 20;

function encodeCursor(row) {
    return Buffer.from(JSON.stringify([row.created_at, row.id])).toString('base64url');
}

function decodeCursor(value) {
    try {
        const [createdAt, id] = JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
        if (!createdAt || !UUID.test(id) || Number.isNaN(Date.parse(createdAt))) throw new Error();
        return [createdAt, id];
    } catch {
        throw new MessagingPolicyError('Invalid message cursor', 400, 'VALIDATION_ERROR');
    }
}

function pairKey(firstUserId, secondUserId) {
    return [String(firstUserId), String(secondUserId)].sort().join(':');
}

function messageDto(row) {
    return {
        id: row.id,
        conversation_id: row.conversation_id,
        sender_user_id: row.sender_user_id,
        client_message_id: row.client_message_id,
        body: row.body,
        message_type: row.message_type,
        created_at: row.created_at,
    };
}

async function getConversationDto(conversationId, userId, queryable = db) {
    const result = await queryable.query(
        `SELECT c.id,c.status,c.conversation_type,c.request_status,
                c.initiated_by_user_id,c.request_updated_at,c.created_at,c.last_message_at,
                om.member_role AS other_role,op.profile_image_url AS other_avatar_url,
                COALESCE(NULLIF(trim(concat_ws(' ',op.first_name_en,op.last_name_en)),''),
                         NULLIF(trim(concat_ws(' ',op.first_name_ar,op.last_name_ar)),''),
                         'MedOrbit user') AS other_display_name,
                lm.id AS last_message_id,left(lm.body,120) AS last_message_preview,
                lm.sender_user_id AS last_sender_user_id,lm.created_at AS last_message_created_at,
                (c.request_status='pending' AND me.member_role='patient'
                 AND c.initiated_by_user_id<>$2) AS can_respond_to_request,
                (SELECT count(*)::int
                 FROM medorbit.direct_messages um
                 LEFT JOIN medorbit.direct_messages rm ON rm.id=me.last_read_message_id
                 WHERE um.conversation_id=c.id AND um.deleted_at IS NULL
                   AND um.sender_user_id<>$2
                   AND (me.last_read_message_id IS NULL
                        OR (um.created_at,um.id)>(rm.created_at,rm.id))) AS unread_count
         FROM medorbit.direct_conversations c
         JOIN medorbit.conversation_members me
           ON me.conversation_id=c.id AND me.user_id=$2 AND me.left_at IS NULL
         JOIN medorbit.conversation_members om
           ON om.conversation_id=c.id AND om.user_id<>$2 AND om.left_at IS NULL
         LEFT JOIN medorbit.user_profiles op ON op.user_id=om.user_id
         LEFT JOIN LATERAL (
           SELECT id,body,sender_user_id,created_at
           FROM medorbit.direct_messages
           WHERE conversation_id=c.id AND deleted_at IS NULL
           ORDER BY created_at DESC,id DESC LIMIT 1
         ) lm ON true
         WHERE c.id=$1`,
        [conversationId, userId]
    );
    if (!result.rows[0]) throw new MessagingPolicyError('Conversation not found', 404, 'NOT_FOUND');
    return result.rows[0];
}

async function assertRequestAllowed(actor, counterpart, key, queryable) {
    if (counterpart.allow_doctor_messages !== true) {
        throw new MessagingPolicyError('Patient is not accepting doctor message requests', 404, 'NOT_FOUND');
    }

    const declined = await queryable.query(
        `SELECT declined_at
         FROM medorbit.direct_conversations
         WHERE participant_pair_key=$1 AND request_status='declined'
         ORDER BY declined_at DESC NULLS LAST,id DESC LIMIT 1`,
        [key]
    );
    if (declined.rows[0]?.declined_at
        && Date.now() - new Date(declined.rows[0].declined_at).getTime()
            < REQUEST_COOLDOWN_DAYS * 24 * 60 * 60 * 1000) {
        throw new MessagingPolicyError(
            'A declined request cannot be recreated yet',
            429,
            'MESSAGE_REQUEST_COOLDOWN'
        );
    }

    const recent = await queryable.query(
        `SELECT count(*)::int AS count
         FROM medorbit.direct_conversations
         WHERE initiated_by_user_id=$1 AND conversation_type='patient_doctor'
           AND created_at>=NOW()-INTERVAL '24 hours'`,
        [actor.user_id]
    );
    if (recent.rows[0].count >= MAX_NEW_PATIENT_REQUESTS_PER_DAY) {
        throw new MessagingPolicyError(
            'Daily patient message request limit reached',
            429,
            'MESSAGE_REQUEST_RATE_LIMITED'
        );
    }
}

async function createConversation({ userId, role, counterpartId }) {
    if (!UUID.test(String(counterpartId || ''))) {
        throw new MessagingPolicyError('Valid counterpartId is required', 400, 'VALIDATION_ERROR');
    }

    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const actor = await resolveMessagingActor(userId, role, client);
        const counterpart = await resolveCounterpart(actor, counterpartId, client);
        const key = pairKey(actor.user_id, counterpart.user_id);

        const existing = await client.query(
            `SELECT id FROM medorbit.direct_conversations
             WHERE participant_pair_key=$1 AND status='active'
               AND request_status IN ('pending','accepted')
             FOR UPDATE`,
            [key]
        );
        if (existing.rows[0]) {
            const conversation = await getConversationDto(existing.rows[0].id, userId, client);
            await client.query('COMMIT');
            return { conversation, created: false };
        }

        const relationship = await findActiveRelationship(actor, counterpart, client);
        const conversationType = actor.kind === 'doctor' && counterpart.kind === 'doctor'
            ? 'doctor_doctor'
            : 'patient_doctor';
        let requestStatus = 'accepted';
        if (actor.kind === 'doctor' && counterpart.kind === 'patient' && !relationship) {
            await assertRequestAllowed(actor, counterpart, key, client);
            requestStatus = 'pending';
        }

        const inserted = await client.query(
            `INSERT INTO medorbit.direct_conversations
               (relationship_id,participant_pair_key,conversation_type,
                initiated_by_user_id,request_status)
             VALUES($1,$2,$3,$4,$5)
             ON CONFLICT(participant_pair_key)
               WHERE status='active' AND request_status IN ('pending','accepted')
             DO NOTHING RETURNING id`,
            [relationship?.id || null, key, conversationType, actor.user_id, requestStatus]
        );
        let conversationId = inserted.rows[0]?.id;
        const created = Boolean(conversationId);
        if (!conversationId) {
            const raced = await client.query(
                `SELECT id FROM medorbit.direct_conversations
                 WHERE participant_pair_key=$1 AND status='active'
                   AND request_status IN ('pending','accepted')`,
                [key]
            );
            conversationId = raced.rows[0]?.id;
        }
        if (!conversationId) throw new Error('Unable to create conversation');

        if (created) {
            await client.query(
                `INSERT INTO medorbit.conversation_members
                   (conversation_id,user_id,member_role)
                 VALUES($1,$2,$3),($1,$4,$5)`,
                [conversationId, actor.user_id, actor.kind, counterpart.user_id, counterpart.kind]
            );
            await createAudit({
                user_id: userId,
                user_role: role,
                action: requestStatus === 'pending'
                    ? 'MESSAGE_REQUEST_CREATED'
                    : 'DIRECT_CONVERSATION_CREATED',
                entity_type: 'DIRECT_CONVERSATION',
                entity_id: conversationId,
                new_values: {
                    conversation_type: conversationType,
                    request_status: requestStatus,
                    relationship_id: relationship?.id || null,
                },
            }, client);
            await recordUserEvent({
                userId,
                eventType: 'direct_conversation_started',
                entityType: 'direct_conversation',
                entityId: conversationId,
                dedupeKey: `direct-conversation:${conversationId}`,
            }, client);

            if (requestStatus === 'pending') {
                await client.query(
                    `INSERT INTO medorbit.notifications
                       (user_id,title_ar,title_en,message_ar,message_en,
                        notification_type,reference_id,reference_type,channel)
                     VALUES($1,'طلب مراسلة جديد','New message request',
                            'أرسل طبيب معتمد طلب مراسلة جديداً.',
                            'An approved doctor sent you a message request.',
                            'NEW_MESSAGE_REQUEST',$2,'DIRECT_CONVERSATION','in_app')`,
                    [counterpart.user_id, conversationId]
                );
            }
        }

        const conversation = await getConversationDto(conversationId, userId, client);
        await client.query('COMMIT');
        return { conversation, created };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function listConversations(userId, { limit = 30, offset = 0 } = {}) {
    const safeLimit = Math.min(Math.max(Number(limit) || 30, 1), 50);
    const safeOffset = Math.max(Number(offset) || 0, 0);
    const result = await db.query(
        `SELECT c.id
         FROM medorbit.direct_conversations c
         JOIN medorbit.conversation_members m ON m.conversation_id=c.id
         WHERE m.user_id=$1 AND m.left_at IS NULL AND c.status='active'
           AND c.request_status IN ('pending','accepted')
         ORDER BY c.last_message_at DESC NULLS LAST,c.created_at DESC,c.id DESC
         LIMIT $2 OFFSET $3`,
        [userId, safeLimit, safeOffset]
    );
    const items = [];
    for (const row of result.rows) items.push(await getConversationDto(row.id, userId));
    return { items, limit: safeLimit, offset: safeOffset };
}

async function listMessages(conversationId, userId, { limit = 50, cursor = null, after = null } = {}) {
    await getConversationAccess(conversationId, userId);
    const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
    const params = [conversationId, safeLimit + 1];
    let boundary = '';
    let order = 'DESC';
    if (after) {
        const [at, id] = decodeCursor(after);
        params.push(at, id);
        boundary = ' AND (created_at,id)>($3::timestamptz,$4::uuid)';
        order = 'ASC';
    } else if (cursor) {
        const [at, id] = decodeCursor(cursor);
        params.push(at, id);
        boundary = ' AND (created_at,id)<($3::timestamptz,$4::uuid)';
    }
    const result = await db.query(
        `SELECT id,conversation_id,sender_user_id,client_message_id,body,message_type,created_at
         FROM medorbit.direct_messages
         WHERE conversation_id=$1 AND deleted_at IS NULL${boundary}
         ORDER BY created_at ${order},id ${order} LIMIT $2`,
        params
    );
    const hasMore = result.rows.length > safeLimit;
    let rows = result.rows.slice(0, safeLimit);
    if (order === 'DESC') rows = rows.reverse();
    return {
        items: rows.map(messageDto),
        next_cursor: hasMore && rows.length ? encodeCursor(rows[0]) : null,
        latest_cursor: rows.length ? encodeCursor(rows[rows.length - 1]) : null,
    };
}

async function sendMessage({ conversationId, userId, body, clientMessageId }) {
    const text = typeof body === 'string' ? body.trim() : '';
    if (!text || text.length > 4000) {
        throw new MessagingPolicyError('Message body must contain 1 to 4000 characters', 400, 'VALIDATION_ERROR');
    }
    if (!UUID.test(String(clientMessageId || ''))) {
        throw new MessagingPolicyError('Valid client_message_id is required', 400, 'VALIDATION_ERROR');
    }

    const client = await db.getClient();
    let message;
    let created = false;
    try {
        await client.query('BEGIN');
        await getConversationAccess(conversationId, userId, { requireActiveEligibility: true }, client);
        const inserted = await client.query(
            `INSERT INTO medorbit.direct_messages
               (conversation_id,sender_user_id,client_message_id,body)
             VALUES($1,$2,$3,$4)
             ON CONFLICT(conversation_id,sender_user_id,client_message_id)
             DO NOTHING RETURNING *`,
            [conversationId, userId, clientMessageId, text]
        );
        message = inserted.rows[0];
        created = Boolean(message);
        if (!message) {
            const existing = await client.query(
                `SELECT * FROM medorbit.direct_messages
                 WHERE conversation_id=$1 AND sender_user_id=$2 AND client_message_id=$3`,
                [conversationId, userId, clientMessageId]
            );
            message = existing.rows[0];
        } else {
            await client.query(
                `UPDATE medorbit.direct_conversations
                 SET last_message_at=$2,updated_at=NOW() WHERE id=$1`,
                [conversationId, message.created_at]
            );
            const recipient = await client.query(
                `SELECT m.user_id,
                        COALESCE(NULLIF(trim(concat_ws(' ',p.first_name_en,p.last_name_en)),''),
                                 NULLIF(trim(concat_ws(' ',p.first_name_ar,p.last_name_ar)),''),
                                 'MedOrbit user') AS sender_name
                 FROM medorbit.conversation_members m
                 LEFT JOIN medorbit.user_profiles p ON p.user_id=$2
                 WHERE m.conversation_id=$1 AND m.user_id<>$2 AND m.left_at IS NULL`,
                [conversationId, userId]
            );
            if (recipient.rows[0]) {
                const safeName = recipient.rows[0].sender_name;
                await client.query(
                    `INSERT INTO medorbit.notifications
                       (user_id,title_ar,title_en,message_ar,message_en,
                        notification_type,reference_id,reference_type,channel)
                     VALUES($1,'رسالة جديدة','New message',$2,$3,
                            'NEW_DIRECT_MESSAGE',$4,'DIRECT_CONVERSATION','in_app')`,
                    [
                        recipient.rows[0].user_id,
                        `رسالة جديدة من ${safeName}`,
                        `New message from ${safeName}`,
                        conversationId,
                    ]
                );
            }
            await recordUserEvent({
                userId,
                eventType: 'direct_message_sent',
                entityType: 'direct_message',
                entityId: message.id,
                metadata: { conversation_id: conversationId, body_length: text.length },
                dedupeKey: `direct-message:${message.id}`,
            }, client);
            await enqueueOutboxEvent(client, {
                aggregateType: 'direct_message',
                aggregateId: message.id,
                eventType: 'direct.message.sent',
                payload: {
                    messageId: message.id,
                    conversationId,
                    senderUserId: userId,
                    recipientUserId: recipient.rows[0]?.user_id || null,
                },
            });
        }
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }

    const dto = messageDto(message);
    if (created) emitMessageCreated(dto);
    return { message: dto, created };
}

async function respondToRequest(conversationId, userId, decision) {
    if (!['accepted', 'declined'].includes(decision)) {
        throw new MessagingPolicyError('Invalid request decision', 400, 'VALIDATION_ERROR');
    }
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const access = await getConversationAccess(conversationId, userId, {}, client);
        if (access.member_role !== 'patient' || access.initiated_by_user_id === userId) {
            throw new MessagingPolicyError('Only the recipient patient can respond to this request');
        }
        if (access.request_status !== 'pending' || access.status !== 'active') {
            throw new MessagingPolicyError('Message request is no longer pending', 409, 'REQUEST_NOT_PENDING');
        }

        const result = await client.query(
            `UPDATE medorbit.direct_conversations
             SET request_status=$1::varchar,
                 status=CASE WHEN $1::varchar='declined' THEN 'closed' ELSE status END,
                 declined_at=CASE WHEN $1::varchar='declined' THEN NOW() ELSE NULL END,
                 request_updated_at=NOW(),updated_at=NOW()
             WHERE id=$2 AND request_status='pending' AND status='active'
             RETURNING id,initiated_by_user_id`,
            [decision, conversationId]
        );
        if (!result.rows[0]) {
            throw new MessagingPolicyError('Message request is no longer pending', 409, 'REQUEST_NOT_PENDING');
        }

        await createAudit({
            user_id: userId,
            user_role: 'patient',
            action: decision === 'accepted' ? 'MESSAGE_REQUEST_ACCEPTED' : 'MESSAGE_REQUEST_DECLINED',
            entity_type: 'DIRECT_CONVERSATION',
            entity_id: conversationId,
            new_values: { request_status: decision },
        }, client);
        await client.query(
            `INSERT INTO medorbit.notifications
               (user_id,title_ar,title_en,message_ar,message_en,
                notification_type,reference_id,reference_type,channel)
             VALUES($1,$2,$3,$4,$5,$6,$7,'DIRECT_CONVERSATION','in_app')`,
            [
                result.rows[0].initiated_by_user_id,
                decision === 'accepted' ? 'تم قبول طلب المراسلة' : 'تم رفض طلب المراسلة',
                decision === 'accepted' ? 'Message request accepted' : 'Message request declined',
                decision === 'accepted'
                    ? 'يمكنك الآن بدء المحادثة النصية.'
                    : 'رفض المريض طلب المراسلة.',
                decision === 'accepted'
                    ? 'You can now start the text conversation.'
                    : 'The patient declined the message request.',
                decision === 'accepted' ? 'MESSAGE_REQUEST_ACCEPTED' : 'MESSAGE_REQUEST_DECLINED',
                conversationId,
            ]
        );
        const dto = decision === 'accepted'
            ? await getConversationDto(conversationId, userId, client)
            : { id: conversationId, status: 'closed', request_status: 'declined' };
        await client.query('COMMIT');
        return dto;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function markRead(conversationId, userId, messageId = null) {
    await getConversationAccess(conversationId, userId);
    const target = await db.query(
        messageId
            ? `SELECT id FROM medorbit.direct_messages
               WHERE id=$1 AND conversation_id=$2 AND deleted_at IS NULL`
            : `SELECT id FROM medorbit.direct_messages
               WHERE conversation_id=$1 AND deleted_at IS NULL
               ORDER BY created_at DESC,id DESC LIMIT 1`,
        messageId ? [messageId, conversationId] : [conversationId]
    );
    if (messageId && !target.rows[0]) {
        throw new MessagingPolicyError('Message not found', 404, 'NOT_FOUND');
    }
    if (!target.rows[0]) {
        return { conversation_id: conversationId, last_read_message_id: null, last_read_at: null };
    }
    const result = await db.query(
        `UPDATE medorbit.conversation_members
         SET last_read_message_id=$3,last_read_at=NOW()
         WHERE conversation_id=$1 AND user_id=$2 AND (
           last_read_message_id IS NULL OR
           (SELECT (created_at,id) FROM medorbit.direct_messages WHERE id=last_read_message_id)
           <=(SELECT (created_at,id) FROM medorbit.direct_messages WHERE id=$3)
         )
         RETURNING conversation_id,last_read_message_id,last_read_at`,
        [conversationId, userId, target.rows[0].id]
    );
    const dto = result.rows[0] || {
        conversation_id: conversationId,
        last_read_message_id: target.rows[0].id,
    };
    emitToConversation(conversationId, 'conversation.read', { ...dto, user_id: userId });
    return dto;
}

module.exports = {
    REQUEST_COOLDOWN_DAYS,
    MAX_NEW_PATIENT_REQUESTS_PER_DAY,
    createConversation,
    listConversations,
    listMessages,
    sendMessage,
    respondToRequest,
    markRead,
    getConversationDto,
    encodeCursor,
    decodeCursor,
    messageDto,
    pairKey,
};
