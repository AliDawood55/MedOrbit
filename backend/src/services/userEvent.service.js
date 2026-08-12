const db = require('../config/database');
const { enqueueOutboxEvent } = require('./outbox.service');
const { isAllowedSignal, validateSafeSourceEvent } = require('./recommendationPolicy.service');

const FORBIDDEN_KEYS = /patient|appointment|diagnosis|clinical|medical_record|token|password|email|google/i;

function sanitizeMetadata(metadata = {}) {
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return {};
    const safe = Object.fromEntries(Object.entries(metadata)
        .filter(([key,value]) => !FORBIDDEN_KEYS.test(key) && ['string','number','boolean'].includes(typeof value))
        .slice(0, 12));
    return JSON.stringify(safe).length <= 2048 ? safe : {};
}

async function recordUserEvent({ userId=null,eventType,entityType,entityId=null,metadata={},dedupeKey=null }, queryable=db) {
    if (isAllowedSignal(eventType)) {
        if (typeof queryable.release !== 'function') throw new Error('Recommendation user events require an existing transaction');
        validateSafeSourceEvent({ user_id:userId,event_type:eventType,entity_type:entityType,entity_id:entityId,metadata });
    }
    const sanitizedMetadata = sanitizeMetadata(metadata);
    const result = await queryable.query(
        `INSERT INTO medorbit.user_events
           (user_id,event_type,entity_type,entity_id,metadata,dedupe_key)
         VALUES($1,$2,$3,$4,$5,$6)
         ON CONFLICT(dedupe_key) DO NOTHING RETURNING id`,
        [userId,eventType,entityType,entityId,sanitizedMetadata,dedupeKey]
    );
    const recorded = result.rows[0] || null;
    if (recorded && isAllowedSignal(eventType)) {
        await enqueueOutboxEvent(queryable,{
            aggregateType:'user_event',aggregateId:recorded.id,eventType:'user.interaction.recorded',eventVersion:1,
            partitionKey:String(userId),payload:{userEventId:recorded.id,userId,eventType},
        });
    }
    return recorded;
}

module.exports = { recordUserEvent, sanitizeMetadata };
