const db=require('../config/database');
const {ALLOWED_SIGNALS}=require('./recommendationPolicy.service');

const ALLOWED_EVENT_TYPES=Object.freeze(Object.keys(ALLOWED_SIGNALS));
const ML_READINESS_POLICY=Object.freeze({
 level1:Object.freeze({behavioralUsers:20,eligibleEvents:200,eligiblePosts:30,representedSpecialties:3,historyDays:7}),
 level2:Object.freeze({usersWith10Events:50,eligibleEvents:2000,eligiblePosts:100,representedSpecialties:5,historyDays:30,maxEventTypePercentage:80}),
});

const number=(value)=>Number(value)||0;
const round=(value)=>Math.round((Number(value)||0)*100)/100;

function failedLevel1(metrics){const t=ML_READINESS_POLICY.level1,failed=[];
 if(metrics.behavioralUsers<t.behavioralUsers)failed.push('BEHAVIORAL_USERS_LT_20');
 if(metrics.eligibleEvents<t.eligibleEvents)failed.push('ELIGIBLE_EVENTS_LT_200');
 if(metrics.eligiblePosts<t.eligiblePosts)failed.push('ELIGIBLE_POSTS_LT_30');
 if(metrics.representedSpecialties<t.representedSpecialties)failed.push('REPRESENTED_SPECIALTIES_LT_3');
 if(metrics.historyDays<t.historyDays)failed.push('HISTORY_DAYS_LT_7');
 return failed;}
function failedLevel2(metrics,maxEventTypePercentage){const t=ML_READINESS_POLICY.level2,failed=[];
 if(metrics.usersWith10Events<t.usersWith10Events)failed.push('USERS_WITH_10_EVENTS_LT_50');
 if(metrics.eligibleEvents<t.eligibleEvents)failed.push('ELIGIBLE_EVENTS_LT_2000');
 if(metrics.eligiblePosts<t.eligiblePosts)failed.push('ELIGIBLE_POSTS_LT_100');
 if(metrics.representedSpecialties<t.representedSpecialties)failed.push('REPRESENTED_SPECIALTIES_LT_5');
 if(metrics.historyDays<t.historyDays)failed.push('HISTORY_DAYS_LT_30');
 if(maxEventTypePercentage>t.maxEventTypePercentage)failed.push('EVENT_TYPE_CONCENTRATION_GT_80_PERCENT');
 return failed;}

function evaluateReadiness(metrics,eventDistribution={}){
 const maxEventTypePercentage=Math.max(0,...Object.values(eventDistribution).map(number));
 const level2Failures=failedLevel2(metrics,maxEventTypePercentage);
 if(!level2Failures.length)return{level:'S9_PILOT_READY',s9PilotReady:true,failedGates:[],maxEventTypePercentage};
 const level1Failures=failedLevel1(metrics);
 if(!level1Failures.length)return{level:'EXPERIMENTAL_DATA',s9PilotReady:false,failedGates:level2Failures,maxEventTypePercentage};
 return{level:'INSUFFICIENT',s9PilotReady:false,failedGates:level1Failures,maxEventTypePercentage};
}

async function collectMlReadiness(pool=db.pool){const client=await pool.connect();try{
 await client.query('BEGIN TRANSACTION READ ONLY');
 const identity=(await client.query(`SELECT current_database() database,system_identifier::text system_identifier FROM pg_control_system()`)).rows[0];
 const base=(await client.query(`SELECT
  (SELECT count(*)::int FROM medorbit.users) users,
  (SELECT count(*)::int FROM medorbit.doctors d JOIN medorbit.users u ON u.id=d.user_id WHERE d.approval_status='approved' AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL) approved_doctors,
  (SELECT count(*)::int FROM medorbit.doctor_posts p JOIN medorbit.doctors d ON d.id=p.doctor_id JOIN medorbit.users u ON u.id=d.user_id WHERE p.status='published' AND p.moderation_status='approved' AND p.deleted_at IS NULL AND d.approval_status='approved' AND u.role='doctor' AND u.is_active=true AND u.deleted_at IS NULL) eligible_posts`)).rows[0];
 const events=(await client.query(`WITH eligible AS (
    SELECT user_id,event_type,occurred_at FROM medorbit.user_events WHERE event_type=ANY($1::varchar[])
  ), per_user AS (SELECT user_id,count(*) event_count FROM eligible WHERE user_id IS NOT NULL GROUP BY user_id)
  SELECT (SELECT count(*)::int FROM eligible) eligible_events,
    (SELECT count(*)::int FROM per_user) behavioral_users,
    (SELECT count(*)::int FROM per_user WHERE event_count>=5) users_with_5_events,
    (SELECT count(*)::int FROM per_user WHERE event_count>=10) users_with_10_events,
    (SELECT min(occurred_at) FROM eligible) oldest_event_at,
    (SELECT max(occurred_at) FROM eligible) newest_event_at`,[ALLOWED_EVENT_TYPES])).rows[0];
 const distributionRows=(await client.query(`SELECT event_type,count(*)::int count FROM medorbit.user_events WHERE event_type=ANY($1::varchar[]) GROUP BY event_type ORDER BY event_type`,[ALLOWED_EVENT_TYPES])).rows;
 const profile=(await client.query(`SELECT count(*)::int profile_rows,count(DISTINCT user_id)::int profile_users,
    count(DISTINCT interest_key) FILTER(WHERE interest_type='specialty' AND score>0)::int represented_specialties
    FROM medorbit.user_interest_profiles`)).rows[0];
 await client.query('COMMIT');
 const eligibleEvents=number(events.eligible_events),behavioralUsers=number(events.behavioral_users),users=number(base.users);
 const oldest=events.oldest_event_at?new Date(events.oldest_event_at):null,newest=events.newest_event_at?new Date(events.newest_event_at):null;
 const historyDays=oldest&&newest?Math.max(0,Math.floor((newest-oldest)/86400000)):0;
 const eventCounts=Object.fromEntries(ALLOWED_EVENT_TYPES.map(type=>[type,0]));for(const row of distributionRows)eventCounts[row.event_type]=number(row.count);
 const eventDistribution=Object.fromEntries(ALLOWED_EVENT_TYPES.map(type=>[type,eligibleEvents?round(eventCounts[type]*100/eligibleEvents):0]));
 const metrics={users,approvedDoctors:number(base.approved_doctors),eligiblePosts:number(base.eligible_posts),eligibleEvents,
  behavioralUsers,usersWith5Events:number(events.users_with_5_events),usersWith10Events:number(events.users_with_10_events),
  averageEventsPerBehavioralUser:behavioralUsers?round(eligibleEvents/behavioralUsers):0,
  profileRows:number(profile.profile_rows),profileUsers:number(profile.profile_users),representedSpecialties:number(profile.represented_specialties),
  oldestEligibleEventAt:oldest?oldest.toISOString():null,newestEligibleEventAt:newest?newest.toISOString():null,historyDays,
  coldUserPercentage:users?round((users-behavioralUsers)*100/users):0,
  behavioralCoveragePercentage:users?round(behavioralUsers*100/users):0,
  profileCoveragePercentage:users?round(number(profile.profile_users)*100/users):0,
  eligibleEventsPerPost:number(base.eligible_posts)?round(eligibleEvents/number(base.eligible_posts)):0};
 const readiness=evaluateReadiness(metrics,eventDistribution);
 return{database:identity.database,systemIdentifier:identity.system_identifier,generatedAt:new Date().toISOString(),level:readiness.level,s9PilotReady:readiness.s9PilotReady,
  metrics,eventCounts,eventDistribution,failedGates:readiness.failedGates};
 }catch(error){await client.query('ROLLBACK').catch(()=>{});throw error;}finally{client.release();}}

module.exports={ALLOWED_EVENT_TYPES,ML_READINESS_POLICY,evaluateReadiness,collectMlReadiness};
