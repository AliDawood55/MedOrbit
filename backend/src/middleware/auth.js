const jwt = require("jsonwebtoken");
const { error } = require("../utils/response");

/**
 * Verify JWT token
 */
const authenticate = (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;

        if (!authHeader || !authHeader.startsWith("Bearer ")) {
            return error(res, "Access token required", 401, "UNAUTHORIZED");
        }

        const token = authHeader.split(" ")[1];
        const decoded = jwt.verify(token, process.env.JWT_SECRET);

        req.user = decoded;
        next();

    } catch (err) {
        return error(res, "Invalid access token", 401, "UNAUTHORIZED");
    }
};

/**
 * Role authorization middleware
 * Usage: authorize("doctor") or authorize("admin", "doctor")
 */
const authorize = (...roles) => {
    return (req, res, next) => {
        if (!req.user) {
            return error(res, "Authentication required", 401, "UNAUTHORIZED");
        }

        if (!roles.includes(req.user.role)) {
            return error(res, "You do not have permission", 403, "FORBIDDEN");
        }

        next();
    };
};

/**
 * Optional JWT verification — populates req.user if a valid Bearer token
 * is present, but never rejects the request. For endpoints that must work
 * for both anonymous and logged-in callers (e.g. POST /chat/message),
 * where a missing/invalid token should just mean "anonymous", not a 401.
 */
const authenticateOptional = (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;

        if (authHeader && authHeader.startsWith("Bearer ")) {
            const token = authHeader.split(" ")[1];
            const decoded = jwt.verify(token, process.env.JWT_SECRET);
            req.user = decoded;
        }

        next();

    } catch (err) {
        // Invalid/expired token — proceed as anonymous rather than rejecting.
        next();
    }
};

module.exports = { authenticate, authorize, authenticateOptional };