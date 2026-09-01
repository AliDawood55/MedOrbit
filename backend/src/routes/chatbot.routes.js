const express = require('express');
const router = express.Router();

const chatbotController = require('../controllers/chatbot.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.post('/message', authenticate, authorize('patient', 'doctor'), chatbotController.sendMessage);

module.exports = router;
