const express = require('express');
const router = express.Router();

const chatbotController = require('../controllers/chatbot.controller');
const { authenticateOptional } = require('../middleware/auth');

router.post('/message', authenticateOptional, chatbotController.sendMessage);

module.exports = router;