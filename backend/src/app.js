const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { errorHandler, notFound } = require('./middleware/errorHandler');

// Import routes
const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/user.routes');;
const doctorRoutes = require('./routes/doctor.routes');
const clinicRoutes = require('./routes/clinic.routes');
const notificationRoutes = require('./routes/notification.routes');
const notificationTemplateRoutes = require('./routes/notification-template.routes');


const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: { success: false, error: { code: 'RATE_LIMIT', message: 'Too many requests' } }
});
app.use('/api/', limiter);

// Stricter rate limit for auth
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { success: false, error: { code: 'RATE_LIMIT', message: 'Too many auth attempts' } }
});
app.use('/api/auth/', authLimiter);

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Health check
app.get('/health', (req, res) => {
  res.json({ success: true, message: 'MedOrbit API is running', timestamp: new Date().toISOString() });
});

app.use(
  "/uploads",
  express.static("uploads")
);

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/doctors', doctorRoutes);
app.use('/api/clinics', clinicRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin/notifications/templates', notificationTemplateRoutes);
app.use('/api/specialties', require('./routes/specialty.routes'));

// 404 handler
app.use(notFound);

// Error handler
app.use(errorHandler);

const {
  processEmails
} = require("./workers/email.worker");



setInterval(

  processEmails,

  60000

);

module.exports = app;