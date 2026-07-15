const express = require('express');
const router = express.Router();

const conversationRepository = require('../repositories/conversation.repository');
const chatbotRepository = require('../repositories/chatbot.repository');
const { authenticate } = require('../middleware/auth');
const { success, error } = require('../utils/response');

// =====================================================
// Conversation Routes
// All routes require authentication
// =====================================================

// GET /api/conversations — List user conversations
router.get('/', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { page = 1, limit = 50, search } = req.query;

        const result = await conversationRepository.findByUserId(userId, {
            page: parseInt(page),
            limit: Math.min(parseInt(limit), 100),
            search
        });

        return success(res, result, 'Conversations retrieved');
    } catch (err) {
        next(err);
    }
});

// POST /api/conversations — Create new conversation
router.post('/', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { language = 'ar' } = req.body;
        const sessionId = Date.now().toString() + '-' + userId.slice(0, 8);

        const conversation = await conversationRepository.create({
            sessionId,
            userId,
            language
        });

        // Auto-generate title placeholder (will be updated after first message)
        await conversationRepository.upsertTitle(
            conversation.id,
            language === 'ar' ? 'محادثة جديدة' : 'New conversation',
            true
        );

        return success(res, {
            ...conversation,
            title: language === 'ar' ? 'محادثة جديدة' : 'New conversation',
            is_auto_generated: true,
            message_count: 0
        }, 'Conversation created', 201);
    } catch (err) {
        next(err);
    }
});

// GET /api/conversations/search — Search conversations
router.get('/search', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { q } = req.query;

        if (!q || q.trim().length < 2) {
            return error(res, 'Search query must be at least 2 characters', 400, 'VALIDATION_ERROR');
        }

        const results = await conversationRepository.searchByUserId(userId, q.trim());
        return success(res, { conversations: results }, 'Search results');
    } catch (err) {
        next(err);
    }
});

// GET /api/conversations/:id — Get conversation with messages
router.get('/:id', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;
        const { limit = 50, offset = 0 } = req.query;

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        // Check ownership
        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        // Get messages
        const messages = await chatbotRepository.findMessagesByConversationId(id, {
            limit: parseInt(limit),
            offset: parseInt(offset)
        });

        // Get saved places
        const places = await conversationRepository.findPlacesByConversationId(id);

        return success(res, {
            conversation,
            messages,
            places,
            messageCount: messages.length
        }, 'Conversation retrieved');
    } catch (err) {
        next(err);
    }
});

// PUT /api/conversations/:id — Rename conversation
router.put('/:id', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;
        const { title } = req.body;

        if (!title || title.trim().length === 0) {
            return error(res, 'Title is required', 400, 'VALIDATION_ERROR');
        }

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        await conversationRepository.updateTitle(id, title.trim());

        return success(res, { id, title: title.trim() }, 'Conversation renamed');
    } catch (err) {
        next(err);
    }
});

// DELETE /api/conversations/:id — Delete conversation
router.delete('/:id', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        await conversationRepository.delete(id);

        return success(res, null, 'Conversation deleted');
    } catch (err) {
        next(err);
    }
});

// POST /api/conversations/:id/title — Auto-generate title
router.post('/:id/title', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        // Get first user message to generate title from
        const messages = await chatbotRepository.findMessagesByConversationId(id, { limit: 1, offset: 0 });
        const firstMessage = messages.find(m => m.message_type === 'user');

        let title;
        if (firstMessage) {
            // Extract first meaningful words for title
            const text = firstMessage.message_text;
            title = text.length > 60 ? text.substring(0, 60).trim() + '...' : text;
        } else {
            title = conversation.language === 'ar' ? 'محادثة جديدة' : 'New conversation';
        }

        await conversationRepository.upsertTitle(id, title, true);

        return success(res, { id, title }, 'Title generated');
    } catch (err) {
        next(err);
    }
});

// =====================================================
// Saved Places within a Conversation
// =====================================================

// GET /api/conversations/:id/places — Get saved places
router.get('/:id/places', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        const places = await conversationRepository.findPlacesByConversationId(id);
        return success(res, { places }, 'Places retrieved');
    } catch (err) {
        next(err);
    }
});

// POST /api/conversations/:id/places — Save a place
router.post('/:id/places', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.sub;
        const { id } = req.params;
        const { placeName, placeType, latitude, longitude, address, phone, distanceKm, rating } = req.body;

        if (!placeName || !placeType || latitude == null || longitude == null) {
            return error(res, 'Place name, type, latitude, and longitude are required', 400, 'VALIDATION_ERROR');
        }

        const conversation = await conversationRepository.findById(id);
        if (!conversation) {
            return error(res, 'Conversation not found', 404, 'NOT_FOUND');
        }

        if (conversation.user_id !== userId) {
            return error(res, 'Unauthorized', 403, 'FORBIDDEN');
        }

        const place = await conversationRepository.savePlace({
            conversationId: id,
            userId,
            placeName,
            placeType,
            latitude,
            longitude,
            address,
            phone,
            distanceKm,
            rating
        });

        return success(res, place, 'Place saved', 201);
    } catch (err) {
        next(err);
    }
});

module.exports = router;