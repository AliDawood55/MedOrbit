const chatbotService = require('../services/chatbot/chatbot.service');

exports.sendMessage = async (req, res) => {
    try {

        const { message, conversationId, latitude, longitude } = req.body;
        
        // Support authenticated users (userId from JWT)
        const userId = req.user?.sub || null;

        if (!message) {
            return res.status(400).json({
                success: false,
                error: { message: 'Message is required' }
            });
        }

        const result = await chatbotService.processMessage({
            message,
            conversationId,
            userId,
            latitude,
            longitude
        });

        res.json({
            success: true,
            data: result
        });

    } catch (error) {

        console.error("🔥 CONTROLLER ERROR:", error);

        res.status(500).json({
            success: false,
            error: {
                message: "Internal server error"
            }
        });
    }
};
