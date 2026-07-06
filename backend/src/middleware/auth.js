const jwt = require('jsonwebtoken');
const { error } = require('../utils/response');

// Verify JWT token
const authenticate = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return error(res, 'Access token required', 401, 'UNAUTHORIZED');
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    req.user = decoded;
    next();
  } catch (err) {
    next(err);
  }
};

// Role-based access control
const authorize = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return error(res, 'Authentication required', 401, 'UNAUTHORIZED');
    }

    if (!roles.includes(req.user.role)) {
      return error(res, 'Insufficient permissions', 403, 'FORBIDDEN');
    }

    next();
  };
};

module.exports = { authenticate, authorize };