const ALLOWED_SIGNALS = Object.freeze({
    post_view: { weight: 1, entityType: 'doctor_post', repeatCap: 3 },
    post_like: { weight: 3, entityType: 'doctor_post', repeatCap: 5 },
    post_unlike: { weight: -3, entityType: 'doctor_post', repeatCap: 5 },
    post_comment: { weight: 4, entityType: 'doctor_post', repeatCap: 5 },
    doctor_profile_view: { weight: 2, entityType: 'doctor', repeatCap: 5 },
    doctor_follow: { weight: 6, entityType: 'doctor', repeatCap: 5 },
    doctor_unfollow: { weight: -6, entityType: 'doctor', repeatCap: 5 },
    search_specialty: { weight: 2, entityType: 'specialty', repeatCap: 5 },
});

const EVENT_METADATA_KEYS = Object.freeze({
    post_view: [], post_like: [], post_unlike: [],
    post_comment: ['comment_id'],
    doctor_profile_view: [], doctor_follow: [], doctor_unfollow: [],
    search_specialty: ['specialty_id'],
});

const FORBIDDEN_INPUT = /(diagnosis|symptom|prescription|medical[_-]?record|clinical[_-]?note|message[_-]?body|chat|conversation[_-]?text|sdp|ice|candidate|audio|video|password|token|secret|credential|email|google)/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isAllowedSignal(eventType) { return Object.hasOwn(ALLOWED_SIGNALS, eventType); }

function validateSafeSourceEvent(event) {
    const policy = ALLOWED_SIGNALS[event?.event_type];
    if (!policy) return { accepted: false, reason: 'UNSUPPORTED_EVENT' };
    if (!UUID.test(String(event.user_id || ''))) throw new Error('Recommendation event requires a valid user id');
    if (event.entity_type !== policy.entityType) throw new Error('Recommendation event entity type mismatch');
    if (!UUID.test(String(event.entity_id || ''))) throw new Error('Recommendation event requires a valid entity id');
    const metadata = event.metadata || {};
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) throw new Error('Recommendation metadata must be an object');
    const allowedKeys = new Set(EVENT_METADATA_KEYS[event.event_type]);
    for (const [key, value] of Object.entries(metadata)) {
        if (FORBIDDEN_INPUT.test(key)) throw new Error(`Forbidden recommendation field: ${key}`);
        if (!allowedKeys.has(key)) throw new Error(`Unsupported recommendation field: ${key}`);
        if (!['string', 'number', 'boolean'].includes(typeof value)) throw new Error(`Invalid recommendation field: ${key}`);
    }
    if (event.event_type === 'search_specialty') {
        const specialtyId = metadata.specialty_id || event.entity_id;
        if (!UUID.test(String(specialtyId || ''))) throw new Error('Normalized specialty id is required');
    }
    return { accepted: true, policy };
}

function decayMultiplier(lastInteractionAt, asOf = new Date()) {
    const ageDays = Math.max(0, (new Date(asOf).getTime() - new Date(lastInteractionAt).getTime()) / 86400000);
    if (ageDays <= 7) return 1;
    if (ageDays <= 30) return 0.7;
    if (ageDays <= 90) return 0.4;
    return 0.2;
}

function boundedContribution(weight, count, repeatCap) {
    return Number(weight) * Math.min(Math.max(Number(count) || 0, 0), repeatCap);
}

function clampProfileScore(score) { return Math.min(100, Math.max(0, Number(score) || 0)); }

module.exports = {
    ALLOWED_SIGNALS,
    EVENT_METADATA_KEYS,
    FORBIDDEN_INPUT,
    isAllowedSignal,
    validateSafeSourceEvent,
    decayMultiplier,
    boundedContribution,
    clampProfileScore,
};
