const db = require('../config/database');

/**
 * Chatbot Repository
 * All SQL queries related to chatbot conversations, messages, and context.
 */
class ChatbotRepository {

    // ==================== CONVERSATIONS ====================

    async createConversation(sessionId, userId = null) {
        const result = await db.query(
            `INSERT INTO medorbit.chatbot_conversations (session_id, user_id)
             VALUES ($1, $2)
             RETURNING id, session_id, user_id, started_at`,
            [sessionId, userId]
        );
        return result.rows[0];
    }

    async findConversationById(id) {
        const result = await db.query(
            `SELECT * FROM medorbit.chatbot_conversations WHERE id = $1`,
            [id]
        );
        return result.rows[0] || null;
    }

    async findBySessionId(sessionId) {
        const result = await db.query(
            `SELECT * FROM medorbit.chatbot_conversations WHERE session_id = $1`,
            [sessionId]
        );
        return result.rows[0] || null;
    }

    async updateLastMessageAt(conversationId) {
        await db.query(
            `UPDATE medorbit.chatbot_conversations 
             SET last_message_at = CURRENT_TIMESTAMP 
             WHERE id = $1`,
            [conversationId]
        );
    }

    async endConversation(conversationId) {
        await db.query(
            `UPDATE medorbit.chatbot_conversations 
             SET is_active = false, ended_at = CURRENT_TIMESTAMP 
             WHERE id = $1`,
            [conversationId]
        );
    }

    // ==================== MESSAGES ====================

    async saveMessage({ conversationId, messageText, messageType, intent, confidence, metadata }) {
        const result = await db.query(
            `INSERT INTO medorbit.chatbot_messages
             (conversation_id, message_text, message_type, intent, confidence_score, metadata)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, created_at`,
            [conversationId, messageText, messageType, intent, confidence || 0,
             metadata ? JSON.stringify(metadata) : null]
        );
        return result.rows[0];
    }

    async saveUserMessage(conversationId, messageText) {
        return this.saveMessage({
            conversationId,
            messageText,
            messageType: 'user',
            intent: null,
            confidence: null,
            metadata: null
        });
    }

    async saveBotMessage({ conversationId, messageText, intent, confidence, metadata }) {
        return this.saveMessage({
            conversationId,
            messageText,
            messageType: 'bot',
            intent,
            confidence,
            metadata
        });
    }

    async findMessagesByConversationId(conversationId, { limit = 50, offset = 0 } = {}) {
        const result = await db.query(
            `SELECT id, message_text, message_type, intent, confidence_score, metadata, created_at
             FROM medorbit.chatbot_messages
             WHERE conversation_id = $1
             ORDER BY created_at ASC
             LIMIT $2 OFFSET $3`,
            [conversationId, limit, offset]
        );
        return result.rows;
    }

    async findLastBotMessageWithPlaces(conversationId) {
        const result = await db.query(
            `SELECT metadata
             FROM medorbit.chatbot_messages
             WHERE conversation_id = $1
               AND message_type = 'bot'
               AND metadata::text LIKE '%"places"%'
               AND metadata::text NOT LIKE '%"places":[]'
             ORDER BY created_at DESC
             LIMIT 1`,
            [conversationId]
        );
        return result.rows[0] || null;
    }

    async countMessagesByConversationId(conversationId) {
        const result = await db.query(
            `SELECT COUNT(*) FROM medorbit.chatbot_messages WHERE conversation_id = $1`,
            [conversationId]
        );
        return parseInt(result.rows[0].count);
    }

    // ==================== CONTEXT ====================

    async findContextByConversationId(conversationId) {
        const result = await db.query(
            `SELECT last_intent, current_topic, entities_json
             FROM medorbit.chatbot_context
             WHERE conversation_id = $1`,
            [conversationId]
        );
        return result.rows[0] || null;
    }

    async upsertContext({ conversationId, lastIntent, currentTopic, entities }) {
        const existing = await this.findContextByConversationId(conversationId);
        const existingEntities = existing?.entities_json || {};
        const merged = { ...existingEntities, ...entities };

        await db.query(
            `INSERT INTO medorbit.chatbot_context
             (conversation_id, last_intent, current_topic, entities_json)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (conversation_id)
             DO UPDATE SET
                 last_intent = EXCLUDED.last_intent,
                 current_topic = EXCLUDED.current_topic,
                 entities_json = EXCLUDED.entities_json,
                 updated_at = CURRENT_TIMESTAMP`,
            [conversationId, lastIntent, currentTopic, JSON.stringify(merged)]
        );
    }

    // ==================== TRANSACTION SUPPORT ====================

    async getClient() {
        return db.getClient();
    }

    async saveMessageWithClient(client, { conversationId, messageText, messageType, intent, confidence, metadata }) {
        const result = await client.query(
            `INSERT INTO medorbit.chatbot_messages
             (conversation_id, message_text, message_type, intent, confidence_score, metadata)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, created_at`,
            [conversationId, messageText, messageType, intent, confidence || 0,
             metadata ? JSON.stringify(metadata) : null]
        );
        return result.rows[0];
    }

    async upsertContextWithClient(client, { conversationId, lastIntent, currentTopic, entities }) {
        const result = await client.query(
            `SELECT entities_json FROM medorbit.chatbot_context WHERE conversation_id = $1`,
            [conversationId]
        );
        const existing = result.rows[0]?.entities_json || {};
        const merged = { ...existing, ...entities };

        await client.query(
            `INSERT INTO medorbit.chatbot_context
             (conversation_id, last_intent, current_topic, entities_json)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (conversation_id)
             DO UPDATE SET
                 last_intent = EXCLUDED.last_intent,
                 current_topic = EXCLUDED.current_topic,
                 entities_json = EXCLUDED.entities_json,
                 updated_at = CURRENT_TIMESTAMP`,
            [conversationId, lastIntent, currentTopic, JSON.stringify(merged)]
        );
    }
}

module.exports = new ChatbotRepository();