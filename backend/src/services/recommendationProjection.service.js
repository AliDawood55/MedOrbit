const db = require('../config/database');
const { validateEnvelope } = require('../events/eventEnvelope');
const {
    ALLOWED_SIGNALS,
    isAllowedSignal,
    validateSafeSourceEvent,
    boundedContribution,
    clampProfileScore,
} = require('./recommendationPolicy.service');

const CONSUMER_NAME = 'recommendation-profile-v1';
function permanentInputError(message) { const error=new Error(message);error.permanent=true;return error; }

const maxDate = (left, right) => !left || new Date(right) > new Date(left) ? right : left;
const profileKey = (type, key) => `${type}:${String(key).trim().toLowerCase()}`;

async function loadEventDimensions(client, events) {
    const postIds = [...new Set(events.filter((event) => event.entity_type === 'doctor_post').map((event) => event.entity_id))];
    const doctorIds = [...new Set(events.filter((event) => event.entity_type === 'doctor').map((event) => event.entity_id))];
    const specialtyIds = [...new Set(events.filter((event) => event.entity_type === 'specialty').map((event) => event.entity_id))];
    const posts = postIds.length ? (await client.query(
        `SELECT p.id,lower(trim(p.category)) category,d.specialty_id
         FROM medorbit.doctor_posts p JOIN medorbit.doctors d ON d.id=p.doctor_id
         WHERE p.id=ANY($1::uuid[])`, [postIds]
    )).rows : [];
    const doctors = doctorIds.length ? (await client.query(
        `SELECT id,specialty_id FROM medorbit.doctors WHERE id=ANY($1::uuid[])`, [doctorIds]
    )).rows : [];
    const specialties = specialtyIds.length ? (await client.query(
        `SELECT id FROM medorbit.specialties WHERE id=ANY($1::uuid[])`, [specialtyIds]
    )).rows : [];
    return {
        posts: new Map(posts.map((row) => [row.id, row])),
        doctors: new Map(doctors.map((row) => [row.id, row])),
        specialties: new Set(specialties.map((row) => row.id)),
    };
}

function dimensionsForEvent(event, dimensions) {
    if (event.entity_type === 'doctor_post') {
        const post = dimensions.posts.get(event.entity_id);
        if (!post) return [];
        return [
            ...(post.category ? [{ type: 'post_category', key: post.category }] : []),
            ...(post.specialty_id ? [{ type: 'specialty', key: post.specialty_id }] : []),
        ];
    }
    if (event.entity_type === 'doctor') {
        const doctor = dimensions.doctors.get(event.entity_id);
        return doctor?.specialty_id ? [{ type: 'specialty', key: doctor.specialty_id }] : [];
    }
    if (event.entity_type === 'specialty' && dimensions.specialties.has(event.entity_id)) {
        return [{ type: 'specialty', key: event.entity_id }];
    }
    return [];
}

async function calculateUserProfiles(client, userId) {
    const events = (await client.query(
        `SELECT id,user_id,event_type,entity_type,entity_id,metadata,occurred_at
         FROM medorbit.user_events
         WHERE user_id=$1 AND event_type=ANY($2::varchar[])
         ORDER BY occurred_at,id`, [userId, Object.keys(ALLOWED_SIGNALS)]
    )).rows;
    const safeEvents = [];
    for (const event of events) {
        const result = validateSafeSourceEvent(event);
        if (result.accepted) safeEvents.push(event);
    }
    const dimensions = await loadEventDimensions(client, safeEvents);
    const groups = new Map();
    for (const event of safeEvents) {
        const eventDimensions = dimensionsForEvent(event, dimensions);
        if (!eventDimensions.length) continue;
        const key = `${event.event_type}:${event.entity_id}`;
        const group = groups.get(key) || { eventType: event.event_type, count: 0, lastInteractionAt: null, dimensions: eventDimensions };
        group.count += 1;
        group.lastInteractionAt = maxDate(group.lastInteractionAt, event.occurred_at);
        groups.set(key, group);
    }
    const profiles = new Map();
    for (const group of groups.values()) {
        const policy = ALLOWED_SIGNALS[group.eventType];
        const contribution = boundedContribution(policy.weight, group.count, policy.repeatCap);
        for (const dimension of group.dimensions) {
            const key = profileKey(dimension.type, dimension.key);
            const profile = profiles.get(key) || {
                userId, interestType: dimension.type, interestKey: String(dimension.key).trim().toLowerCase(),
                score: 0, interactionCount: 0, lastInteractionAt: null,
            };
            profile.score += contribution;
            profile.interactionCount += Math.min(group.count, policy.repeatCap);
            profile.lastInteractionAt = maxDate(profile.lastInteractionAt, group.lastInteractionAt);
            profiles.set(key, profile);
        }
    }
    return [...profiles.values()].map((profile) => ({ ...profile, score: clampProfileScore(profile.score) }))
        .filter((profile) => profile.score > 0);
}

async function rebuildUserInterest(client, userId) {
    const profiles = await calculateUserProfiles(client, userId);
    await client.query('DELETE FROM medorbit.user_interest_profiles WHERE user_id=$1', [userId]);
    for (const profile of profiles) {
        await client.query(
            `INSERT INTO medorbit.user_interest_profiles
               (user_id,interest_type,interest_key,score,interaction_count,last_interaction_at)
             VALUES($1,$2,$3,$4,$5,$6)`,
            [profile.userId, profile.interestType, profile.interestKey, profile.score, profile.interactionCount, profile.lastInteractionAt]
        );
    }
    return profiles;
}

function validateProjectionEnvelope(envelope) {
    try { validateEnvelope(envelope); } catch(error) { throw permanentInputError(error.message); }
    if (envelope.eventType !== 'user.interaction.recorded') return { accepted: false, reason: 'UNSUPPORTED_EVENT' };
    const payload = envelope.payload;
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw permanentInputError('Recommendation envelope payload is invalid');
    const keys = Object.keys(payload).sort();
    if (keys.join(',') !== 'eventType,userEventId,userId') throw permanentInputError('Recommendation envelope payload is not allowlisted');
    if (!/^[0-9a-f-]{36}$/i.test(payload.userEventId) || !/^[0-9a-f-]{36}$/i.test(payload.userId)) throw permanentInputError('Recommendation envelope identifiers are invalid');
    if (!isAllowedSignal(payload.eventType)) throw permanentInputError('Recommendation source event is not allowlisted');
    return { accepted: true };
}

async function processRecommendationEnvelope(envelope, pool = db.pool) {
    const envelopeResult = validateProjectionEnvelope(envelope);
    if (!envelopeResult.accepted) return { processed: false, ignored: true };
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const marker = await client.query(
            `INSERT INTO medorbit.processed_events(consumer_name,event_id,event_type,event_version)
             VALUES($1,$2,$3,$4) ON CONFLICT(consumer_name,event_id) DO NOTHING RETURNING event_id`,
            [CONSUMER_NAME, envelope.eventId, envelope.eventType, envelope.eventVersion]
        );
        if (!marker.rows[0]) { await client.query('COMMIT'); return { processed: false, duplicate: true }; }
        const source = (await client.query(
            `SELECT id,user_id,event_type,entity_type,entity_id,metadata,occurred_at
             FROM medorbit.user_events WHERE id=$1 AND user_id=$2 FOR SHARE`,
            [envelope.payload.userEventId, envelope.payload.userId]
        )).rows[0];
        if (!source) throw permanentInputError('Recommendation source event not found');
        let sourceResult;
        try { sourceResult=validateSafeSourceEvent(source); } catch(error) { throw permanentInputError(error.message); }
        if (!sourceResult.accepted || source.event_type !== envelope.payload.eventType) throw permanentInputError('Recommendation source event mismatch');
        const profiles = await rebuildUserInterest(client, source.user_id);
        await client.query('COMMIT');
        return { processed: true, profileCount: profiles.length, occurredAt: source.occurred_at };
    } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
    } finally { client.release(); }
}

async function rebuildAllInterests(client) {
    const eventCounts = (await client.query(
        `SELECT event_type,count(*)::int count FROM medorbit.user_events GROUP BY event_type ORDER BY event_type`
    )).rows;
    const users = (await client.query(
        `SELECT DISTINCT user_id FROM medorbit.user_events
         WHERE user_id IS NOT NULL AND event_type=ANY($1::varchar[]) ORDER BY user_id`,
        [Object.keys(ALLOWED_SIGNALS)]
    )).rows;
    await client.query('DELETE FROM medorbit.user_interest_profiles');
    let profileRows = 0;
    for (const row of users) profileRows += (await rebuildUserInterest(client, row.user_id)).length;
    return {
        eligibleEvents: eventCounts.filter((row) => isAllowedSignal(row.event_type)).reduce((sum, row) => sum + row.count, 0),
        usersWithAllowedEvents: users.length,
        profileRows,
        ignoredEventTypes: eventCounts.filter((row) => !isAllowedSignal(row.event_type)).map((row) => ({ eventType: row.event_type, count: row.count })),
    };
}

module.exports = {
    CONSUMER_NAME,
    calculateUserProfiles,
    rebuildUserInterest,
    rebuildAllInterests,
    processRecommendationEnvelope,
    validateProjectionEnvelope,
};
