// .env is loaded by src/config/env.js (called from server.js)
// Do NOT call dotenv.config() here — it would override the root path.

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
const env = require('./config/env');
const { createCorsOptions } = require('./config/cors');
const notificationRoutes = require('./routes/notification.routes');
const notificationTemplateRoutes = require('./routes/notification-template.routes');
const appointmentRoutes = require("./routes/appointment.routes");
const medicalRecordRoutes = require("./routes/medicalRecord.routes");
const specialtyRoutes = require('./routes/specialty.routes');
const prescriptionRoutes = require("./routes/prescription.routes");
const reviewRoutes = require('./routes/review.routes');
const reportRoutes = require('./routes/report.routes');
const adminRoutes = require("./routes/admin.routes");
const systemSettingsRoutes = require('./routes/system-settings.routes');
const auditLogRoutes = require('./routes/audit-log.routes');


const app = express();

// =============================
// SECURITY MIDDLEWARE
// =============================

// Helmet — sets security headers
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginResourcePolicy: { policy: 'cross-origin' },
  hsts: false
}));

app.use((req, res, next) => {
  res.setHeader('Content-Security-Policy', "default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'self'");
  res.setHeader('Permissions-Policy', 'geolocation=(self), microphone=(self), camera=(self), fullscreen=(self), payment=()');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  next();
});

// CORS: configured origins plus same-machine/LAN frontend origins.
app.use(cors(createCorsOptions()));

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

// Stricter rate limit for login endpoint (per-IP, prevents brute force)
// NOTE: applied at the route level inside auth.routes.js, not here — kept
// as-is from the pre-merge file rather than removed during conflict
// resolution.
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,                   // 10 attempts per IP per 15 min
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many login attempts. Please try again later.' }
  }
});

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

// Body parser — must be before routes
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

app.use(
  "/uploads",
  express.static("uploads")
);

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
app.use("/api/appointments", appointmentRoutes);
app.use("/api/medical-records", medicalRecordRoutes);
app.use("/api/prescriptions", prescriptionRoutes);
app.use("/api/patients", require("./routes/patient.routes"));
app.use("/api/feedback", require("./routes/feedback.routes"));
app.use('/api', reviewRoutes);
app.use('/api', reportRoutes);
// User routes (protected)
app.use('/api/users', userRoutes);

// Doctor routes (public read, protected write)
app.use('/api/doctors', doctorRoutes);

// Clinic routes (public read, protected write)
app.use('/api/clinics', clinicRoutes);

// Specialties (public read)
app.use('/api/specialties', specialtyRoutes);

// Appointments
app.use('/api/appointments', appointmentRoutes);

// Notifications
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin/notifications/templates', notificationTemplateRoutes);

// Chatbot routes (with stricter rate limit)
app.use('/api/chat', chatLimiter, chatbotRoutes);

// Conversation routes (protected)
app.use('/api/conversations', conversationRoutes);

app.use("/api/admin", adminRoutes);
app.use('/api/admin/system-settings', systemSettingsRoutes);
app.use('/api/admin/audit-logs', auditLogRoutes);

// Public client config — values the frontend needs but that shouldn't be
// duplicated into a static frontend file (single source of truth is .env).
// googleClientId is a public OAuth client identifier, not a secret.
app.get('/api/config', (req, res) => {
  res.json({
    success: true,
    data: {
      googleClientId: env.google.clientId || null
    }
  });
});

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



if (process.env.NODE_ENV !== "test") {

  setInterval(

    processEmails,

    10000

  );

}

module.exports = app;
