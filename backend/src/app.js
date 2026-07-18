require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const chatbotRoutes = require('./routes/chatbot.routes');
const clinicRoutes = require('./routes/clinic.routes');
const doctorRoutes = require('./routes/doctor.routes');

const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/user.routes');
const conversationRoutes = require('./routes/conversation.routes');
const { errorHandler, notFound } = require('./middleware/errorHandler');
const notificationRoutes = require('./routes/notification.routes');
const notificationTemplateRoutes = require('./routes/notification-template.routes');


const app = express();

// =============================
// SECURITY MIDDLEWARE
// =============================

// Helmet — sets security headers
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginResourcePolicy: { policy: 'cross-origin' }
}));

// CORS — restrict to configured origin in production
const corsOrigin = process.env.CORS_ORIGIN || '*';
app.use(cors({
  origin: corsOrigin === '*' ? true : corsOrigin.split(',').map(s => s.trim()),
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: corsOrigin !== '*'
}));

// Rate limiting — global
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many requests. Please try again later.' }
  }
});
app.use('/api/', globalLimiter);

// Stricter rate limit for AI chatbot endpoint
const chatLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'CHAT_RATE_LIMITED', message: 'Too many chat messages. Please slow down.' }
  }
});

app.use(
  "/uploads",
  express.static("uploads")
);

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/doctors', doctorRoutes);

// Body parser
app.use(express.json({ limit: '1mb' }));

// Request logging (dev)
if (process.env.NODE_ENV === 'development') {
  app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      const duration = Date.now() - start;
      if (duration > 2000) {
        console.log(`⏱ ${req.method} ${req.originalUrl} — ${duration}ms [${res.statusCode}]`);
      }
    });
    next();
  });
}

// =============================
// API ROUTES
// =============================

// Auth routes (public)
app.use('/api/auth', authRoutes);

// Chatbot routes (with stricter rate limit)
app.use('/api/chat', chatLimiter, chatbotRoutes);

// Clinic routes (public read)

app.use('/api/clinics', clinicRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin/notifications/templates', notificationTemplateRoutes);
app.use('/api/specialties', require('./routes/specialty.routes'));

// Doctor routes (public read, protected write)
app.use('/api/doctors', doctorRoutes);

// User routes (protected)
app.use('/api/users', userRoutes);

// Conversation routes (protected)
app.use('/api/conversations', conversationRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({
    success: true,
    data: {
      status: 'healthy',
      version: '2.0.0',
      timestamp: new Date().toISOString()
    }
  });
});

// =============================
// ERROR HANDLING
// =============================

// 404 for unmatched API routes
app.use('/api', notFound);

// Global error handler (must be last)
app.use(errorHandler);

const {
  processEmails
} = require("./workers/email.worker");



setInterval(

  processEmails,

  60000

);

module.exports = app;