const crypto=require('crypto');
const fs=require('fs');
const {Pool}=require('pg');
const {apiBase,poolConfig}=require('./helpers/test-environment');
const {generateAccessToken}=require('../src/utils/jwt');
const {collectMlReadiness,evaluateReadiness,ML_READINESS_POLICY}=require('../src/services/mlReadiness.service');

const pool=new Pool(poolConfig),run=String(Date.now()).slice(-8),users=[],doctors=[],posts=[],specialties=[];
let passed=0,failed=0;
function check(name,condition,detail=''){if(condition){passed++;console.log(`  ✓ ${name}`);}else{failed++;console.error(`  ✗ ${name}${detail?` — ${detail}`:''}`);}}
async function createUser(key,role){const id=crypto.randomUUID();users.push(id);await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version) VALUES($1,$2,'s85-test',$3,true,true,1)`,[id,`s85_${run}_${key}@medorbit.test`,role]);return{id,role};}
async function createDoctor(key,specialtyId,status='approved'){const user=await createUser(key,'doctor'),id=crypto.randomUUID();doctors.push(id);await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,specialty_id,approval_status,approved_at) VALUES($1,$2,$3,$4,$5,NOW())`,[id,user.id,`S85-${run}-${key}`,specialtyId,status]);return{...user,doctorId:id};}
async function createPost(doctorId,status='published',moderation='approved'){const id=crypto.randomUUID();posts.push(id);await pool.query(`INSERT INTO medorbit.doctor_posts(id,doctor_id,title_en,body,category,is_published,status,moderation_status,published_at) VALUES($1,$2,'S8.5','aggregate-only','health_tip',$3='published',$3,$4,NOW())`,[id,doctorId,status,moderation]);return id;}
async function request(path,token){const response=await fetch(`${apiBase}${path}`,{headers:token?{Authorization:`Bearer ${token}`}:{}});let body=null;try{body=await response.json();}catch{}return{status:response.status,body};}
async function cleanup(){
 await pool.query('DELETE FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctor_posts WHERE id=ANY($1::uuid[])',[posts]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctors WHERE id=ANY($1::uuid[])',[doctors]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.specialties WHERE id=ANY($1::uuid[])',[specialties]).catch(()=>{});
}
function metrics(overrides={}){return{behavioralUsers:20,eligibleEvents:200,eligiblePosts:30,representedSpecialties:3,historyDays:7,usersWith10Events:0,...overrides};}

(async()=>{console.log('\nS8.5 ML data readiness tests\n');try{
 check('test isolation fails closed outside Docker test target',process.env.NODE_ENV==='test'&&process.env.MEDORBIT_TEST_ISOLATION==='docker'&&poolConfig.host==='postgres'&&poolConfig.database.endsWith('_test'));
 const empty=await collectMlReadiness(pool);check('empty recommendation history is insufficient',empty.level==='INSUFFICIENT'&&!empty.s9PilotReady&&empty.metrics.eligibleEvents===0);
 const specialty=crypto.randomUUID();specialties.push(specialty);await pool.query(`INSERT INTO medorbit.specialties(id,name_ar,name_en,is_active) VALUES($1,'جاهزية','S8.5 readiness',true)`,[specialty]);
 const patient=await createUser('patient','patient'),admin=await createUser('admin','admin');
 const approved=await createDoctor('approved',specialty),suspended=await createDoctor('suspended',specialty,'suspended');
 const eligiblePost=await createPost(approved.doctorId),draftPost=await createPost(approved.doctorId,'draft','approved'),hiddenPost=await createPost(approved.doctorId,'published','hidden'),suspendedPost=await createPost(suspended.doctorId);
 await pool.query(`INSERT INTO medorbit.user_events(user_id,event_type,entity_type,entity_id) VALUES($1,'direct_message_sent','direct_message',$2)`,[patient.id,crypto.randomUUID()]);
 const excluded=await collectMlReadiness(pool);check('excluded event types never count',excluded.metrics.eligibleEvents===0&&excluded.eventCounts.post_view===0);
 await pool.query(`INSERT INTO medorbit.user_events(user_id,event_type,entity_type,entity_id,occurred_at) VALUES($1,'post_view','doctor_post',$2,NOW()-interval '8 days')`,[patient.id,eligiblePost]);
 await pool.query(`INSERT INTO medorbit.user_interest_profiles(user_id,interest_type,interest_key,score,interaction_count,last_interaction_at) VALUES($1,'specialty',$2,1,1,NOW())`,[patient.id,specialty]);
 const report=await collectMlReadiness(pool);
 check('only approved active doctors count',report.metrics.approvedDoctors===1);
 check('only published approved eligible posts count',report.metrics.eligiblePosts===1&&posts.length===4);
 check('allowlisted event aggregates are counted',report.metrics.eligibleEvents===1&&report.eventCounts.post_view===1&&report.metrics.behavioralUsers===1);
 check('profile and represented-specialty aggregates count safely',report.metrics.profileRows===1&&report.metrics.profileUsers===1&&report.metrics.representedSpecialties===1);
 const level1=evaluateReadiness(metrics(),{post_view:100});check('exact Level 1 thresholds pass',level1.level==='EXPERIMENTAL_DATA'&&!level1.s9PilotReady);
 const below=evaluateReadiness(metrics({eligibleEvents:199}),{post_view:100});check('one below Level 1 threshold fails',below.level==='INSUFFICIENT');
 const level2Metrics=metrics({behavioralUsers:50,usersWith10Events:50,eligibleEvents:2000,eligiblePosts:100,representedSpecialties:5,historyDays:30});
 const level2=evaluateReadiness(level2Metrics,{post_view:80,post_like:20});check('exact Level 2 thresholds and 80 percent concentration pass',level2.level==='S9_PILOT_READY'&&level2.s9PilotReady);
 const concentrated=evaluateReadiness(level2Metrics,{post_view:80.01,post_like:19.99});check('event concentration above 80 percent blocks Level 2',concentrated.level==='EXPERIMENTAL_DATA'&&!concentrated.s9PilotReady&&concentrated.failedGates.includes('EVENT_TYPE_CONCENTRATION_GT_80_PERCENT'));
 check('threshold policy is centralized and exact',ML_READINESS_POLICY.level1.eligibleEvents===200&&ML_READINESS_POLICY.level2.eligibleEvents===2000&&ML_READINESS_POLICY.level2.maxEventTypePercentage===80);
 const serialized=JSON.stringify(report);check('aggregate response contains no user identifiers or metadata',!serialized.includes(patient.id)&&!serialized.includes('@medorbit.test')&&!serialized.includes('metadata'));
 const source=fs.readFileSync(require.resolve('../src/services/mlReadiness.service'),'utf8');
 check('service never queries clinical message chatbot or video tables',!/medical_records|prescriptions|appointments|doctor_patient_relationships|direct_messages|chatbot_|video_consultations/i.test(source));
 check('service SQL is read-only',source.includes('BEGIN TRANSACTION READ ONLY')&&!/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|ALTER|DROP)\b/i.test(source));
 check('unauthenticated admin readiness endpoint is denied',(await request('/admin/ml-readiness')).status===401);
 check('patient cannot access admin readiness endpoint',(await request('/admin/ml-readiness',generateAccessToken({sub:patient.id,role:'patient',authorizationVersion:1}))).status===403);
 const adminResponse=await request('/admin/ml-readiness',generateAccessToken({sub:admin.id,role:'admin',authorizationVersion:1}));check('admin receives aggregate-only readiness report',adminResponse.status===200&&adminResponse.body?.data?.level==='INSUFFICIENT'&&!JSON.stringify(adminResponse.body).includes(patient.id));
 }catch(error){failed++;console.error(error);}finally{
  await cleanup();const residue=(await pool.query(`SELECT
   (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
   (SELECT count(*) FROM medorbit.doctors WHERE id=ANY($2::uuid[]))::int doctors,
   (SELECT count(*) FROM medorbit.doctor_posts WHERE id=ANY($3::uuid[]))::int posts,
   (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int events,
   (SELECT count(*) FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[]))::int profiles,
   (SELECT count(*) FROM medorbit.specialties WHERE id=ANY($4::uuid[]))::int specialties`,[users,doctors,posts,specialties])).rows[0];
  check('S8.5 fixtures leave zero residue',Object.values(residue).every(v=>v===0),JSON.stringify(residue));console.log(`S8.5 residual counts: ${JSON.stringify(residue)}`);console.log(`\nS8.5 ML readiness: ${passed} passed, ${failed} failed`);await pool.end();if(failed)process.exitCode=1;
 }
})();
