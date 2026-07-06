/**
 * Standard API Response Format
 * Success: { success: true, data: {}, message: '' }
 * Error: { success: false, error: { code, message, details } }
 */

const success = (res, data = null, message = 'Success', statusCode = 200) => {
  return res.status(statusCode).json({
    success: true,
    data,
    message,
    timestamp: new Date().toISOString()
  });
};

const error = (res, message = 'Error', statusCode = 500, code = 'INTERNAL_ERROR', details = null) => {
  return res.status(statusCode).json({
    success: false,
    error: {
      code,
      message,
      details,
      timestamp: new Date().toISOString()
    }
  });
};

module.exports = { success, error };