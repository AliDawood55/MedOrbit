const DEFAULT_FRONTEND_PORT = '8080';

function normalizeOriginList(corsOrigin) {
    return String(corsOrigin || '')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean);
}

function isPrivateNetworkHost(hostname) {
    const host = String(hostname || '').replace(/^\[|\]$/g, '').toLowerCase();
    if (host === 'localhost' || host === '::1') return true;
    if (/^127(?:\.\d{1,3}){3}$/.test(host)) return true;
    if (/^10(?:\.\d{1,3}){3}$/.test(host)) return true;
    if (/^192\.168(?:\.\d{1,3}){2}$/.test(host)) return true;

    const match = host.match(/^172\.(\d{1,3})(?:\.\d{1,3}){2}$/);
    return !!match && Number(match[1]) >= 16 && Number(match[1]) <= 31;
}

function isAllowedCorsOrigin(origin, options = {}) {
    const corsOrigin = options.corsOrigin || process.env.CORS_ORIGIN || '*';
    if (!origin || corsOrigin === '*') return true;

    if (normalizeOriginList(corsOrigin).includes(origin)) return true;

    try {
        const url = new URL(origin);
        const frontendPort = String(options.frontendPort || process.env.FRONTEND_PORT || DEFAULT_FRONTEND_PORT);
        return (url.protocol === 'http:' || url.protocol === 'https:')
            && url.port === frontendPort
            && isPrivateNetworkHost(url.hostname);
    } catch {
        return false;
    }
}

function createCorsOptions() {
    const corsOrigin = process.env.CORS_ORIGIN || '*';

    return {
        origin(origin, callback) {
            callback(null, isAllowedCorsOrigin(origin, { corsOrigin }));
        },
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization'],
        credentials: corsOrigin !== '*'
    };
}

module.exports = {
    createCorsOptions,
    isAllowedCorsOrigin,
    isPrivateNetworkHost
};
