class MemoryService {

    async updateContext(client, conversationId, intent, entities) {

        const res = await client.query(
            `SELECT entities_json FROM chatbot_context
             WHERE conversation_id = $1`,
            [conversationId]
        );

        const existing = res.rows[0]?.entities_json || {};

        const merged = {
            ...existing,
            ...entities
        };

        await client.query(`
            INSERT INTO chatbot_context
            (conversation_id, last_intent, current_topic, entities_json)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (conversation_id)
            DO UPDATE SET
                last_intent = EXCLUDED.last_intent,
                current_topic = EXCLUDED.current_topic,
                entities_json = $4
        `, [
            conversationId,
            intent,
            intent,
            JSON.stringify(merged)
        ]);
    }

    async getLastPlacesFromMessages(client, conversationId) {
        // Retrieve last places from the most recent bot message
        // that had places stored in its metadata JSON
        const res = await client.query(
            `SELECT metadata
             FROM chatbot_messages
             WHERE conversation_id = $1
               AND message_type = 'bot'
               AND metadata::text LIKE '%"places"%'
               AND metadata::text NOT LIKE '%"places":[]'
             ORDER BY created_at DESC
             LIMIT 1`,
            [conversationId]
        );

        if (!res.rows[0]) return null;

        try {
            const metadata = res.rows[0].metadata;
            const parsed = typeof metadata === 'string' ? JSON.parse(metadata) : metadata;
            const places = parsed?.places;
            return (Array.isArray(places) && places.length > 0) ? places : null;
        } catch {
            return null;
        }
    }

    async getContext(client, conversationId) {
        const res = await client.query(
            `SELECT last_intent, current_topic, entities_json
             FROM chatbot_context
             WHERE conversation_id = $1`,
            [conversationId]
        );

        if (!res.rows[0]) return null;

        const row = res.rows[0];

        return {
            lastIntent: row.last_intent,
            topic: row.current_topic,
            entities: row.entities_json || {}
        };
    }
}

module.exports = new MemoryService();