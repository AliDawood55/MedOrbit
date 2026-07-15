const axios = require('axios');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';
const AI_SERVICE_TIMEOUT_MS = parseInt(process.env.AI_SERVICE_TIMEOUT_MS) || 60000;

class AIClientService {

    async sendMessage(payload) {
        try {

            let body = {};

            if (typeof payload === 'string') {
                body = { message: payload };
            } else {
                body = payload || {};
            }

            if (!body.message || typeof body.message !== 'string') {
                body.message = 'hello';
            }

            const response = await axios.post(
                `${AI_SERVICE_URL}/chat`,
                body,
                { timeout: AI_SERVICE_TIMEOUT_MS }
            );

            const data = response.data;

            return {
                reply: data.reply || 'No reply generated',
                intent: data.intent || 'unknown',
                confidence: data.confidence || 0,
                entities: data.entities || {}
            };

        } catch (error) {

            const status = error.response?.status;
            const msg = error.response?.data?.detail || error.message;

            if (status === 404) {
                console.error('[AI] Service not reachable at', AI_SERVICE_URL);
            } else if (status === 422) {
                console.error('[AI] Validation error:', msg);
            } else if (error.code === 'ECONNABORTED') {
                console.error('[AI] Request timed out after', AI_SERVICE_TIMEOUT_MS, 'ms');
            } else {
                console.error('[AI] Error:', msg);
            }

            // Never crash — return safe fallback
            return {
                reply: 'Service temporarily unavailable. Please try again.',
                intent: 'error',
                confidence: 0,
                entities: {}
            };
        }
    }
}

module.exports = new AIClientService();