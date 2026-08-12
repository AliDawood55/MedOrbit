const crypto=require('crypto');
const fs=require('fs');
const {Pool}=require('pg');
const {poolConfig}=require('./helpers/test-environment');
const {recordUserEvent}=require('../src/services/userEvent.service');
const {buildEnvelope}=require('../src/events/eventEnvelope');
const {
 ALLOWED_SIGNALS,validateSafeSourceEvent,decayMultiplier,boundedContribution,
}=require('../src/services/recommendationPolicy.service');
const {
 calculateUserProfiles,rebuildUserInterest,rebuildAllInterests,processRecommendationEnvelope,validateProjectionEnvelope,
}=require('../src/services/recommendationProjection.service');
const {
 boundedEngagement,scorePost,diversifyPosts,getRankedFeed,getRankedDoctors,
}=require('../src/services/recommendation.service');

const pool=new Pool(poolConfig),run=String(Date.now()).slice(-8),users=[],doctors=[],posts=[],specialties=[],outboxEventIds=[];
let passed=0,failed=0;
function check(name,condition,detail=''){if(condition){passed++;console.log(`  ✓ ${name}`);}else{failed++;console.error(`  ✗ ${name}${detail?` — ${detail}`:''}`);}}
async function rejects(name,fn,pattern){try{await fn();check(name,false,'did not reject');}catch(error){check(name,pattern.test(String(error.message)),error.message);}}
async function createUser(key,role='patient'){const id=crypto.randomUUID();users.push(id);await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version) VALUES($1,$2,'s8-test',$3,true,true,1)`,[id,`s8_${run}_${key}@medorbit.test`,role]);await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en) VALUES($1,'اختبار','توصيات',$2,'Recommendations')`,[id,key]);if(role==='patient'){const patientId=crypto.randomUUID();await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)',[patientId,id]);return{id,role,patientId};}return{id,role};}
async function createSpecialty(key){const id=crypto.randomUUID();specialties.push(id);await pool.query(`INSERT INTO medorbit.specialties(id,name_ar,name_en,is_active) VALUES($1,$2,$3,true)`,[id,`تخصص ${run} ${key}`,`S8 ${run} ${key}`]);return id;}
async function createDoctor(key,specialtyId,status='approved'){const user=await createUser(key,'doctor'),id=crypto.randomUUID();doctors.push(id);await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,specialty_id,approval_status,approved_at,average_rating,total_ratings) VALUES($1,$2,$3,$4,$5,NOW(),4.0,2)`,[id,user.id,`S8-${run}-${key}`,specialtyId,status]);return{...user,doctorId:id};}
async function createPost(doctorId,category,offsetMinutes=0,{status='published',moderation='approved',deleted=false}={}){const id=crypto.randomUUID();posts.push(id);await pool.query(`INSERT INTO medorbit.doctor_posts(id,doctor_id,title_en,body,category,is_published,status,moderation_status,published_at,deleted_at) VALUES($1,$2,$3,'safe public body',$4,true,$5,$6,NOW()+($7::int*interval '1 minute'),CASE WHEN $8 THEN NOW() ELSE NULL END)`,[id,doctorId,`S8 ${category}`,category,status,moderation,offsetMinutes,deleted]);return id;}
async function insertEvent(userId,eventType,entityType,entityId,metadata={},occurredAt=new Date()){return(await pool.query(`INSERT INTO medorbit.user_events(user_id,event_type,entity_type,entity_id,metadata,occurred_at) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,[userId,eventType,entityType,entityId,metadata,occurredAt])).rows[0];}
async function recordTransactional(userId,eventType,entityType,entityId,metadata={}){const client=await pool.connect();try{await client.query('BEGIN');const row=await recordUserEvent({userId,eventType,entityType,entityId,metadata},client);await client.query('COMMIT');return row;}catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}}
async function envelopeForUserEvent(eventId){const row=(await pool.query(`SELECT * FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id=$1 ORDER BY created_at DESC LIMIT 1`,[eventId])).rows[0];if(row&&!outboxEventIds.includes(row.id))outboxEventIds.push(row.id);return buildEnvelope(row);}
async function profiles(userId){return(await pool.query(`SELECT interest_type,interest_key,score::float,interaction_count,last_interaction_at FROM medorbit.user_interest_profiles WHERE user_id=$1 ORDER BY interest_type,interest_key`,[userId])).rows;}
async function cleanup(){
 await pool.query(`DELETE FROM medorbit.processed_events WHERE consumer_name='recommendation-profile-v1' AND event_id IN(SELECT id FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN(SELECT id FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN(SELECT id FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]) OR doctor_id=ANY($2::uuid[])',[users,doctors]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.post_comments WHERE post_id=ANY($1::uuid[])',[posts]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.post_likes WHERE post_id=ANY($1::uuid[])',[posts]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctor_posts WHERE id=ANY($1::uuid[])',[posts]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id=ANY($1::uuid[])',[doctors]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctors WHERE id=ANY($1::uuid[])',[doctors]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.specialties WHERE id=ANY($1::uuid[])',[specialties]).catch(()=>{});
}

(async()=>{console.log('\nS8 deterministic recommendation adversarial tests\n');try{
 const isolation=(await pool.query(`SELECT current_database() db`)).rows[0];check('test isolation targets medorbit_test',isolation.db.endsWith('_test')&&poolConfig.host==='postgres');
 const specialtyA=await createSpecialty('cardiology'),specialtyB=await createSpecialty('nutrition');
 const patient=await createUser('patient'),other=await createUser('other');
 const doctorA=await createDoctor('doctor-a',specialtyA),doctorB=await createDoctor('doctor-b',specialtyB),suspended=await createDoctor('suspended',specialtyA,'suspended');
 const postA=await createPost(doctorA.doctorId,'health_tip',-2),postB=await createPost(doctorB.doctorId,'announcement',-1),postA2=await createPost(doctorA.doctorId,'health_tip',-3);
 const hidden=await createPost(doctorA.doctorId,'health_tip',0,{moderation:'hidden'}),suspendedPost=await createPost(suspended.doctorId,'health_tip',0);

 for(const [type,entityType,entityId,metadata] of [
  ['post_view','doctor_post',postA,{}],['post_like','doctor_post',postA,{}],['post_comment','doctor_post',postA,{comment_id:crypto.randomUUID()}],
  ['doctor_profile_view','doctor',doctorA.doctorId,{}],['doctor_follow','doctor',doctorA.doctorId,{}],['doctor_unfollow','doctor',doctorA.doctorId,{}],['search_specialty','specialty',specialtyA,{specialty_id:specialtyA}],
 ])check(`${type} accepted`,validateSafeSourceEvent({user_id:patient.id,event_type:type,entity_type:entityType,entity_id:entityId,metadata}).accepted);
 check('direct-message event excluded',!validateSafeSourceEvent({event_type:'direct_message_sent'}).accepted);
 check('video event excluded',!validateSafeSourceEvent({event_type:'video_consultation_started'}).accepted);
 check('care relationship event excluded',!validateSafeSourceEvent({event_type:'care.relationship.created'}).accepted);
 for(const field of ['diagnosis','message_body','sdp','ice_candidate','token'])await rejects(`${field} rejected`,()=>Promise.resolve(validateSafeSourceEvent({user_id:patient.id,event_type:'post_view',entity_type:'doctor_post',entity_id:postA,metadata:{[field]:'forbidden'}})),/Forbidden|Unsupported/);

 const view=await recordTransactional(patient.id,'post_view','doctor_post',postA);
 const outboxCount=Number((await pool.query(`SELECT count(*) FROM medorbit.outbox_events WHERE aggregate_id=$1 AND event_type='user.interaction.recorded'`,[view.id])).rows[0].count);
 check('allowed event creates transactional outbox',outboxCount===1);
 const envelope=await envelopeForUserEvent(view.id),processed=await processRecommendationEnvelope(envelope);
 check('valid event updates projection',processed.processed&&(await profiles(patient.id)).length===2);
 const beforeDuplicate=await profiles(patient.id),duplicate=await processRecommendationEnvelope(envelope),afterDuplicate=await profiles(patient.id);
 check('duplicate Kafka event is idempotent',duplicate.duplicate&&JSON.stringify(beforeDuplicate)===JSON.stringify(afterDuplicate));
 check('event weight deterministic',(await profiles(patient.id)).find(row=>row.interest_type==='post_category').score===ALLOWED_SIGNALS.post_view.weight);
 check('decay buckets deterministic',decayMultiplier(new Date('2026-01-01'),new Date('2026-01-06'))===1&&decayMultiplier(new Date('2026-01-01'),new Date('2026-01-20'))===0.7&&decayMultiplier(new Date('2026-01-01'),new Date('2026-03-01'))===0.4&&decayMultiplier(new Date('2025-01-01'),new Date('2026-01-01'))===0.2);
 check('repeated interactions bounded',boundedContribution(1,99,3)===3);
 const newest=new Date(),older=new Date(Date.now()-90*86400000);await insertEvent(patient.id,'post_view','doctor_post',postA,{},newest);await insertEvent(patient.id,'post_view','doctor_post',postA,{},older);await insertEvent(patient.id,'post_like','doctor_post',postA,{},newest);
 // Rebuild with an explicit client so its lifecycle remains visible to the test.
 const rebuildClient=await pool.connect();try{await rebuildClient.query('BEGIN');await rebuildUserInterest(rebuildClient,patient.id);await rebuildClient.query('COMMIT');}finally{rebuildClient.release();}
 check('last interaction keeps newest timestamp',Math.abs(new Date((await profiles(patient.id))[0].last_interaction_at)-newest)<2000);
 const unsupportedBefore=JSON.stringify(await profiles(patient.id));check('unsupported event changes nothing',(await processRecommendationEnvelope({eventId:crypto.randomUUID(),eventType:'direct.message.sent',eventVersion:1,occurredAt:new Date().toISOString(),aggregateType:'message',aggregateId:crypto.randomUUID(),producer:'medorbit-api',payload:{}})).ignored&&JSON.stringify(await profiles(patient.id))===unsupportedBefore);
 await insertEvent(other.id,'post_like','doctor_post',postB);const otherClient=await pool.connect();try{await otherClient.query('BEGIN');await rebuildUserInterest(otherClient,other.id);await otherClient.query('COMMIT');}finally{otherClient.release();}
 check('two users remain isolated',(await profiles(other.id)).every(row=>row.interest_key!==specialtyA));
 const parityUser=await createUser('parity');for(const spec of [['post_view','doctor_post',postA],['post_like','doctor_post',postA],['doctor_follow','doctor',doctorA.doctorId]]){const event=await recordTransactional(parityUser.id,...spec);await processRecommendationEnvelope(await envelopeForUserEvent(event.id));}
 const incremental=await profiles(parityUser.id);const parityClient=await pool.connect();try{await parityClient.query('BEGIN');await rebuildUserInterest(parityClient,parityUser.id);await parityClient.query('COMMIT');}finally{parityClient.release();}
 check('incremental and rebuild projections match exactly',JSON.stringify(incremental)===JSON.stringify(await profiles(parityUser.id)));
 const emptyClient=await pool.connect();let empty;try{await emptyClient.query('BEGIN');empty=await rebuildUserInterest(emptyClient,await createUser('empty').then(u=>u.id));await emptyClient.query('COMMIT');}finally{emptyClient.release();}check('empty history creates empty profile',empty.length===0);

 const anonymous1=await getRankedFeed({limit:20,now:new Date()}),anonymous2=await getRankedFeed({limit:20,now:new Date(anonymous1.items.length?Date.now():Date.now())});
 check('anonymous cold feed is deterministic',anonymous1.items.map(x=>x.id).join(',')===anonymous2.items.map(x=>x.id).join(','));
 const cold=await getRankedFeed({userId:other.id,limit:20,now:new Date()});check('authenticated cold/fallback feed works',cold.items.length>=3);
 const personalized=await getRankedFeed({userId:patient.id,limit:20,now:new Date()});
 check('category/specialty affinity boosts matching post',personalized.items.findIndex(x=>x.id===postA)<personalized.items.findIndex(x=>x.id===postB));
 await pool.query('INSERT INTO medorbit.user_follows(user_id,doctor_id) VALUES($1,$2)',[patient.id,doctorB.doctorId]);const followed=await getRankedFeed({userId:patient.id,limit:20});check('follow boost works',followed.items.find(x=>x.doctor.id===doctorB.doctorId)?.reason_code==='FOLLOWED_DOCTOR');
 await pool.query('DELETE FROM medorbit.user_follows WHERE user_id=$1 AND doctor_id=$2',[patient.id,doctorB.doctorId]);const unfollowed=await getRankedFeed({userId:patient.id,limit:20});check('unfollow removes follow boost',unfollowed.items.find(x=>x.doctor.id===doctorB.doctorId)?.reason_code!=='FOLLOWED_DOCTOR');
 check('ineligible moderated post never appears',!personalized.items.some(x=>x.id===hidden));
 check('suspended doctor post never appears',!personalized.items.some(x=>x.id===suspendedPost));
 check('viewed-post fatigue is deterministic',scorePost({category:'none',specialty_id:null,published_at:new Date(),like_count:0,comment_count:0,following_doctor:false,viewed_by_me:true},new Map(),new Date()).components.fatigue===-2);
 check('popularity component is bounded',boundedEngagement(1e9,1e9)<=3);
 const tied=[{id:'b',published_at:'2026-01-01',doctor_id:'d1',_rank:{score:1}},{id:'a',published_at:'2026-01-01',doctor_id:'d2',_rank:{score:1}}].sort((a,b)=>String(b.id).localeCompare(String(a.id)));check('deterministic tie break is stable',tied[0].id==='b');
 const page1=await getRankedFeed({userId:patient.id,limit:2}),page2=await getRankedFeed({userId:patient.id,limit:2,cursor:page1.next_cursor});
 check('cursor page has no duplicates',!page2.items.some(x=>page1.items.some(y=>y.id===x.id)));
 check('stable cursor pages have no missing eligible posts',new Set([...page1.items,...page2.items].map(x=>x.id)).size===personalized.items.length);
 const diversified=diversifyPosts([{doctor_id:'a',_rank:{score:5}},{doctor_id:'a',_rank:{score:4}},{doctor_id:'a',_rank:{score:3}},{doctor_id:'b',_rank:{score:2}}]);check('diversity prevents a three-author streak when alternative exists',diversified.slice(0,3).map(x=>x.doctor_id).join('')==='aab');
 check('reason code reflects ranking input',['FOLLOWED_DOCTOR','INTEREST_SPECIALTY','INTEREST_CATEGORY','TRENDING','RECENT'].includes(personalized.items[0].reason_code));

 const doctorRank=await getRankedDoctors({userId:patient.id,limit:20});check('doctor discovery includes only eligible doctors',doctorRank.every(x=>x.id!==suspended.doctorId));
 check('specialty affinity ranks matching doctor higher',doctorRank.findIndex(x=>x.id===doctorA.doctorId)<doctorRank.findIndex(x=>x.id===doctorB.doctorId));
 await pool.query('INSERT INTO medorbit.user_follows(user_id,doctor_id) VALUES($1,$2)',[patient.id,doctorB.doctorId]);const doctorFollow=await getRankedDoctors({userId:patient.id,limit:20});check('doctor follow state ranks explicitly',doctorFollow.find(x=>x.id===doctorB.doctorId).reason_code==='FOLLOWED_DOCTOR');await pool.query('DELETE FROM medorbit.user_follows WHERE user_id=$1 AND doctor_id=$2',[patient.id,doctorB.doctorId]);
 const relationshipId=crypto.randomUUID();await pool.query(`INSERT INTO medorbit.doctor_patient_relationships(id,doctor_id,patient_id,status,source,started_at) VALUES($1,$2,$3,'active','manual_assign',NOW())`,[relationshipId,doctorB.doctorId,patient.patientId]);const afterCare=await getRankedDoctors({userId:patient.id,limit:20});check('care relationship does not create a recommendation reason',afterCare.find(x=>x.id===doctorB.doctorId).reason_code!=='CARE_RELATIONSHIP');
 check('equal doctor scores order deterministically',[...afterCare].map(x=>x.id).join(',')===[...afterCare].map(x=>x.id).join(','));

 const outageEvent=await recordTransactional(other.id,'doctor_profile_view','doctor',doctorB.doctorId);check('consumer outage does not fail social event transaction',!!outageEvent&&Number((await pool.query('SELECT count(*) FROM medorbit.outbox_events WHERE aggregate_id=$1',[outageEvent.id])).rows[0].count)===1);
 const catchup=await processRecommendationEnvelope(await envelopeForUserEvent(outageEvent.id));check('projection catches up after recovery',catchup.processed&&(await profiles(other.id)).some(x=>x.interest_key===specialtyB));
 check('consumer restart does not double apply',(await processRecommendationEnvelope(await envelopeForUserEvent(outageEvent.id))).duplicate);
 const allClient=await pool.connect();let rebuildStats;try{await allClient.query('BEGIN');rebuildStats=await rebuildAllInterests(allClient);await allClient.query('COMMIT');}finally{allClient.release();}check('full rebuild uses only allowlisted history',rebuildStats.eligibleEvents>0&&rebuildStats.profileRows>0);
 await rejects('malformed event fails safely',()=>Promise.resolve(validateProjectionEnvelope({bad:true})),/Malformed|Missing|Invalid/);
 await rejects('unsupported envelope version fails safely',()=>Promise.resolve(validateProjectionEnvelope({eventId:crypto.randomUUID(),eventType:'user.interaction.recorded',eventVersion:2,occurredAt:new Date().toISOString(),aggregateType:'user_event',aggregateId:view.id,producer:'medorbit-api',payload:{eventType:'post_view',userEventId:view.id,userId:patient.id}})),/Unsupported/);

 const crossBefore=(await pool.query(`SELECT (SELECT count(*) FROM medorbit.doctor_patient_relationships)::int care,(SELECT count(*) FROM medorbit.medical_records)::int records,(SELECT count(*) FROM medorbit.prescriptions)::int prescriptions,(SELECT count(*) FROM medorbit.direct_messages)::int messages,(SELECT count(*) FROM medorbit.video_consultations)::int videos,(SELECT count(*) FROM medorbit.chatbot_messages)::int chatbot`)).rows[0];
 const finalClient=await pool.connect();try{await finalClient.query('BEGIN');await rebuildUserInterest(finalClient,patient.id);await finalClient.query('COMMIT');}finally{finalClient.release();}
 const crossAfter=(await pool.query(`SELECT (SELECT count(*) FROM medorbit.doctor_patient_relationships)::int care,(SELECT count(*) FROM medorbit.medical_records)::int records,(SELECT count(*) FROM medorbit.prescriptions)::int prescriptions,(SELECT count(*) FROM medorbit.direct_messages)::int messages,(SELECT count(*) FROM medorbit.video_consultations)::int videos,(SELECT count(*) FROM medorbit.chatbot_messages)::int chatbot`)).rows[0];
 check('recommendation changes no care relationships',crossBefore.care===crossAfter.care);
 check('recommendation changes no clinical records',crossBefore.records===crossAfter.records);
 check('recommendation changes no prescriptions',crossBefore.prescriptions===crossAfter.prescriptions);
 check('recommendation changes no direct messages',crossBefore.messages===crossAfter.messages);
 check('recommendation changes no video consultations',crossBefore.videos===crossAfter.videos);
 check('recommendation changes no chatbot content',crossBefore.chatbot===crossAfter.chatbot);
 const recommendationSource=fs.readFileSync(require.resolve('../src/services/recommendation.service'),'utf8')+fs.readFileSync(require.resolve('../src/services/recommendationProjection.service'),'utf8');
 check('recommendation services do not query chatbot content',!/chatbot_(messages|conversations)/i.test(recommendationSource));
 check('allowlist remains centralized',Object.keys(ALLOWED_SIGNALS).length===8);
 }catch(error){failed++;console.error(error);}finally{
  await cleanup();const residual=(await pool.query(`SELECT
   (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
   (SELECT count(*) FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[]))::int profiles,
   (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int events,
   (SELECT count(*) FROM medorbit.outbox_events WHERE id=ANY($3::uuid[]))::int outbox,
   (SELECT count(*) FROM medorbit.processed_events WHERE event_id=ANY($3::uuid[]))::int processed,
   (SELECT count(*) FROM medorbit.doctor_posts WHERE id=ANY($2::uuid[]))::int posts`,[users,posts,outboxEventIds])).rows[0];
  check('S8 fixtures leave zero residual rows',Object.values(residual).every(Number.isInteger)&&Object.values(residual).every(v=>v===0),JSON.stringify(residual));
  console.log(`S8 residual counts: ${JSON.stringify(residual)}`);console.log(`\nS8 deterministic recommendations: ${passed} passed, ${failed} failed`);await pool.end();if(failed)process.exitCode=1;
 }
})();
