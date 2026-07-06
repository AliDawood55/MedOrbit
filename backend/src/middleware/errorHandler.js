const { error } = require('../utils/response');

const errorHandler = (err, req, res, next) => {
  console.error('Error:', err);

  // JWT errors
  if (err.name === 'JsonWebTokenError') {
    return error(res, 'Invalid token', 401, 'UNAUTHORIZED');
  }
  if (err.name === 'TokenExpiredError') {
    return error(res, 'Token expired', 401, 'TOKEN_EXPIRED');
  }

  // PostgreSQL errors
  if (err.code === '23505') {
    return error(res, 'Duplicate entry', 409, 'DUPLICATE_ENTRY');
  }
  if (err.code === '23503') {
    return error(res, 'Foreign key violation', 400, 'INVALID_REFERENCE');
  }
  if (err.code === '22P02') {
    return error(res, 'Invalid data format', 400, 'INVALID_FORMAT');
  }

  // Default
  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal server error';
  
  return error(res, message, statusCode, err.code || 'INTERNAL_ERROR');
};

// 404 handler
const notFound = (req, res) => {
  return error(res, `Route ${req.originalUrl} not found`, 404, 'NOT_FOUND');
};

module.exports = { errorHandler, notFound };