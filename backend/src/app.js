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
const aiRoutes = require('./routes/ai.routes');
const billingRoutes = require('./routes/billing.routes');
const virtualDoctorRoutes = require('./routes/virtual-doctor.routes');
const adminInvitationRoutes = require('./routes/admin-invitation.routes');
const { applicationRoutes, adminDoctorApplicationRoutes } = require('./routes/doctor-application.routes');
const careRelationshipRoutes = require('./routes/care-relationship.routes');
const { feedRoutes, socialDoctorRoutes, adminSocialRoutes } = require('./routes/social.routes');
const messageRoutes = require('./routes/message.routes');
const { contactRoutes, adminContactRoutes } = require('./routes/contact.routes');
const eventHealthRoutes = require('./routes/event-health.routes');
const { createGeneralApiLimiter, createAiFeatureLimiter } = require('./middleware/rateLimit');
const { policy: billingPolicy } = require('./config/billing');


const app = express();

// Staging is behind exactly one Caddy reverse-proxy hop. This restores the
// real visitor IP for login and anonymous rate limits without trusting
// attacker-controlled X-Forwarded-* headers in direct local development.
const trustProxy = String(process.env.TRUST_PROXY || '').trim().toLowerCase();
if (trustProxy === '1' || trustProxy === 'true') {
  app.set('trust proxy', 1);
}

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
  res.setHeader('Permissions-Policy', 'geolocation=(self), microphone=(self), camera=(), fullscreen=(self), payment=()');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  next();
});

// CORS: configured origins plus same-machine/LAN frontend origins.
app.use(cors(createCorsOptions()));

// General reads retain a bounded limiter without making local signed-in users
// consume one shared IP bucket.
app.use('/api', createGeneralApiLimiter());

// Infrastructure fair-use limiter for the chatbot.
//
// Distinct from the free-message quota, which EntitlementService enforces per
// account per 24 hours. This one protects the AI workers from a burst and
// applies to Pro subscribers too: "unlimited" describes the product quota, not
// permission to saturate the service.
//
// Keyed per authenticated user rather than per IP so that a clinic or campus
// behind one address does not share a single bucket. The limit comes from the
// central billing policy so it is configurable rather than hardcoded here.
const chatLimiter = createAiFeatureLimiter({
  max: billingPolicy.fairUse.chatbotMessagesPerMinute,
  message: 'Too many chat messages. Please slow down.',
});

// Body parser — must be before routes
app.use(express.json({
  limit: '1mb',
  // Webhook signatures are computed over the exact bytes a provider sent.
  // Re-serializing the parsed object would change key order and whitespace and
  // break verification, so the original buffer is kept for that one route.
  verify: (req, _res, buf) => { req.rawBody = buf; },
}));
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
app.use('/api/doctor-applications', applicationRoutes);

// Persisted AI operations cross this authenticated identity boundary.
app.use('/api/ai', aiRoutes);
app.use('/api/billing', billingRoutes);
// Virtual Doctor now enters through the authenticated backend rather than the
// browser calling the AI service directly.
app.use('/api/virtual-doctor', virtualDoctorRoutes);

// Chatbot routes (with stricter rate limit)
app.use('/api/chat', chatLimiter, chatbotRoutes);

// Clinic routes (public read)

app.use('/api/clinics', clinicRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin/notifications/templates', notificationTemplateRoutes);
app.use('/api/specialties', specialtyRoutes);
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
app.use('/api/doctors', socialDoctorRoutes);
app.use('/api/feed', feedRoutes);
app.use('/api/recommendations', require('./routes/recommendation.routes'));

// Conversation routes (protected)
app.use('/api/conversations', conversationRoutes);
// Human patient-doctor messaging remains isolated from AI chatbot conversations.
app.use('/api/messages', messageRoutes);
app.use('/api/contact', contactRoutes);
app.use('/api/health/events', eventHealthRoutes);

app.use("/api/admin", adminRoutes);
app.use('/api/admin/invitations', adminInvitationRoutes);
app.use('/api/admin/doctor-applications', adminDoctorApplicationRoutes);
app.use('/api/admin/care-relationships', careRelationshipRoutes);
app.use('/api/admin/social', adminSocialRoutes);
app.use('/api/admin/contact-messages', adminContactRoutes);
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
