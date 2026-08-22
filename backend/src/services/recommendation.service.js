const crypto = require('crypto');
const db = require('../config/database');
const env = require('../config/env');
const { decayMultiplier } = require('./recommendationPolicy.service');

const FEED_POLICY = Object.freeze({
    followBoost: 6,
    viewedPenalty: 2,
    affinityScale: 0.25,
    affinityCap: 8,
    engagementCap: 3,
    maxConsecutiveDoctor: 2,
});

function postRecencyScore(publishedAt, asOf) {
    const days = Math.max(0, (new Date(asOf) - new Date(publishedAt)) / 86400000);
    if (days <= 1) return 10;
    if (days <= 7) return 8;
    if (days <= 30) return 5;
    if (days <= 90) return 2;
    return 0.5;
}

function affinityComponent(profile, asOf, cap = FEED_POLICY.affinityCap) {
    if (!profile) return 0;
    return Math.min(cap, Number(profile.score) * decayMultiplier(profile.last_interaction_at, asOf) * FEED_POLICY.affinityScale);
}

function boundedEngagement(likes, comments) {
    return Math.min(FEED_POLICY.engagementCap, Math.log1p(Number(likes) || 0) + 1.25 * Math.log1p(Number(comments) || 0));
}

function scorePost(row, profiles, asOf) {
    const category = profiles.get(`post_category:${String(row.category).trim().toLowerCase()}`);
    const specialty = row.specialty_id ? profiles.get(`specialty:${row.specialty_id}`) : null;
    const components = {
        recency: postRecencyScore(row.published_at, asOf),
        category: affinityComponent(category, asOf),
        specialty: affinityComponent(specialty, asOf),
        follow: row.following_doctor ? FEED_POLICY.followBoost : 0,
        engagement: boundedEngagement(row.like_count, row.comment_count),
        fatigue: row.viewed_by_me ? -FEED_POLICY.viewedPenalty : 0,
    };
    const personalized = [
        ['FOLLOWED_DOCTOR', components.follow],
        ['INTEREST_SPECIALTY', components.specialty],
        ['INTEREST_CATEGORY', components.category],
    ].sort((a,b) => b[1]-a[1])[0];
    const reasonCode = personalized[1] > 0 ? personalized[0] : components.engagement >= 1 ? 'TRENDING' : 'RECENT';
    return { score: Object.values(components).reduce((sum, value) => sum + value, 0), components, reasonCode };
}

function deterministicSort(left, right) {
    if (right._rank.score !== left._rank.score) return right._rank.score - left._rank.score;
    const time = new Date(right.published_at) - new Date(left.published_at);
    return time || String(right.id).localeCompare(String(left.id));
}

function diversifyPosts(sorted, maxConsecutive = FEED_POLICY.maxConsecutiveDoctor) {
    const remaining = [...sorted], output = [];
    while (remaining.length) {
        let index = 0;
        if (output.length >= maxConsecutive && output.slice(-maxConsecutive).every((item) => item.doctor_id === output.at(-1).doctor_id)) {
            const alternative = remaining.findIndex((item) => item.doctor_id !== output.at(-1).doctor_id);
            if (alternative >= 0) index = alternative;
        }
        output.push(remaining.splice(index,1)[0]);
    }
    return output;
}

function cursorSignature(payload) {
    if (!env.jwt.secret) throw new Error('JWT secret is required for recommendation cursors');
    return crypto.createHmac('sha256', env.jwt.secret).update(payload).digest('base64url');
}

function encodeCursor(value) {
    const payload = Buffer.from(JSON.stringify(value)).toString('base64url');
    return `${payload}.${cursorSignature(payload)}`;
}

function decodeCursor(value, subject) {
    if (!value) return null;
    try {
        const [payload, signature, extra] = String(value).split('.');
        if (!payload || !signature || extra) return null;
        const expected = cursorSignature(payload);
        if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature),Buffer.from(expected))) return null;
        const parsed = JSON.parse(Buffer.from(payload,'base64url').toString('utf8'));
        if (parsed.v !== 1 || parsed.subject !== subject || !Number.isInteger(parsed.offset) || parsed.offset < 0 || Number.isNaN(Date.parse(parsed.asOf))) return null;
        return parsed;
    } catch { return null; }
}

async function loadProfiles(userId, queryable = db) {
    if (!userId) return new Map();
    const rows = (await queryable.query(
        `SELECT interest_type,interest_key,score,last_interaction_at
         FROM medorbit.user_interest_profiles WHERE user_id=$1`, [userId]
    )).rows;
    return new Map(rows.map((row) => [`${row.interest_type}:${row.interest_key}`, row]));
}

async function getRankedFeed({ userId = null, limit = 10, cursor = null, queryable = db, now = new Date() }) {
    const subject = userId || 'anonymous';
    const decoded = decodeCursor(cursor,subject);
    if (cursor && !decoded) { const error = new Error('Invalid cursor'); error.code='INVALID_CURSOR'; throw error; }
    const asOf = decoded?.asOf || new Date(now).toISOString(), offset = decoded?.offset || 0;
    const profiles = await loadProfiles(userId,queryable);
    const rows = (await queryable.query(
        `SELECT p.id,p.doctor_id,p.title_ar,p.title_en,p.body,p.category,p.published_at,p.created_at,p.updated_at,
                d.id doctor_public_id,d.specialty_id,pr.first_name_ar,pr.last_name_ar,pr.first_name_en,pr.last_name_en,
                pr.profile_image_url,s.name_ar specialty_ar,s.name_en specialty_en,
                (SELECT count(*)::int FROM medorbit.post_likes l WHERE l.post_id=p.id) like_count,
                (SELECT count(*)::int FROM medorbit.post_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_status='approved') comment_count,
                CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS(SELECT 1 FROM medorbit.post_likes l WHERE l.post_id=p.id AND l.user_id=$1) END liked_by_me,
                CASE WHEN $1::uuid IS NULL THEN false WHEN d.user_id=$1 THEN false ELSE EXISTS(SELECT 1 FROM medorbit.user_follows f WHERE f.doctor_id=d.id AND f.user_id=$1) END following_doctor,
                CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS(SELECT 1 FROM medorbit.user_events e WHERE e.user_id=$1 AND e.entity_id=p.id AND e.event_type='post_view') END viewed_by_me,
                CASE WHEN $1::uuid IS NULL THEN false ELSE d.user_id=$1 END is_own_doctor
         FROM medorbit.doctor_posts p
         JOIN medorbit.doctors d ON d.id=p.doctor_id JOIN medorbit.users u ON u.id=d.user_id
         LEFT JOIN medorbit.user_profiles pr ON pr.user_id=u.id LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id
         WHERE p.status='published' AND p.moderation_status='approved' AND p.deleted_at IS NULL AND p.published_at<=$2
           AND d.approval_status='approved' AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL`,
        [userId,asOf]
    )).rows;
    const ranked = diversifyPosts(rows.map((row) => ({...row,_rank:scorePost(row,profiles,asOf)})).sort(deterministicSort));
    const slice = ranked.slice(offset,offset+limit), hasMore = offset+limit < ranked.length;
    return {
        items: slice.map((row) => ({
            id:row.id,title:row.title_ar||row.title_en||null,title_ar:row.title_ar,title_en:row.title_en,body:row.body,category:row.category,
            published_at:row.published_at,created_at:row.created_at,updated_at:row.updated_at,
            like_count:row.like_count,comment_count:row.comment_count,reason_code:row._rank.reasonCode,
            ...(userId ? {liked_by_me:row.liked_by_me,following_doctor:row.following_doctor,is_own_doctor:row.is_own_doctor} : {}),
            doctor:{id:row.doctor_public_id,first_name_ar:row.first_name_ar,last_name_ar:row.last_name_ar,
                first_name_en:row.first_name_en,last_name_en:row.last_name_en,profile_image_url:row.profile_image_url,
                specialty_ar:row.specialty_ar,specialty_en:row.specialty_en},
        })),
        next_cursor:hasMore?encodeCursor({v:1,subject,asOf,offset:offset+limit}):null,has_more:hasMore,
    };
}

async function getRankedDoctors({ userId = null, limit = 10, queryable = db, now = new Date() }) {
    const profiles = await loadProfiles(userId,queryable), asOf = new Date(now).toISOString();
    const rows = (await queryable.query(
        `SELECT d.id,d.years_of_experience,d.consultation_fee,d.average_rating,d.total_ratings,d.is_accepting_patients,d.specialty_id,
                p.first_name_ar,p.last_name_ar,p.first_name_en,p.last_name_en,p.profile_image_url,
                s.name_ar specialty_ar,s.name_en specialty_en,s.icon specialty_icon,
                CASE WHEN $1::uuid IS NULL THEN false ELSE EXISTS(SELECT 1 FROM medorbit.user_follows f WHERE f.user_id=$1 AND f.doctor_id=d.id) END following_doctor
         FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id
         LEFT JOIN medorbit.user_profiles p ON p.user_id=d.user_id LEFT JOIN medorbit.specialties s ON s.id=d.specialty_id
         WHERE u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL AND d.approval_status='approved'`, [userId]
    )).rows;
    return rows.map((row) => {
        const affinity=affinityComponent(row.specialty_id?profiles.get(`specialty:${row.specialty_id}`):null,asOf,10);
        const follow=row.following_doctor?6:0,quality=Math.min(5,Number(row.average_rating)||0)+Math.min(2,Math.log1p(Number(row.total_ratings)||0));
        return {...row,_score:affinity+follow+quality,reason_code:follow?'FOLLOWED_DOCTOR':affinity>0?'INTEREST_SPECIALTY':quality>=2?'TRENDING':'RECENT'};
    }).sort((a,b)=>b._score-a._score||String(a.id).localeCompare(String(b.id))).slice(0,limit)
      .map(({_score,...row})=>row);
}

module.exports = {
    FEED_POLICY, postRecencyScore, affinityComponent, boundedEngagement, scorePost, diversifyPosts,
    encodeCursor, decodeCursor, getRankedFeed, getRankedDoctors,
};
