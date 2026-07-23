const express = require('express');
const router = express.Router();

const chatbotController = require('../controllers/chatbot.controller');
const { authenticateOptional } = require('../middleware/auth');

// POST /api/chat/message — works for anonymous and logged-in callers;
// authenticateOptional attaches req.user when a valid token is present
// (without it, chat.service.js always created anonymous conversations).
router.post('/message', authenticateOptional, chatbotController.sendMessage);

module.exports = router;