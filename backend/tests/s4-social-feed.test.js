const crypto=require('crypto');
const {Pool}=require('pg');
const {apiBase,poolConfig}=require('./helpers/test-environment');
const {generateAccessToken}=require('../src/utils/jwt');

const pool=new Pool(poolConfig); const run=Date.now(); const marker=`S4${String(run).slice(-8)}`;
const users=[]; const ids={}; let passed=0,failed=0;
function check(name,ok,detail=''){if(ok){passed++;console.log(`  ✓ ${name}`);}else{failed++;console.error(`  ✗ ${name}${detail?` — ${detail}`:''}`);}}
function token(user,version=1){return generateAccessToken({sub:user.id,role:user.role,authorizationVersion:version});}
async function request(method,path,auth,body){const headers=auth?{Authorization:`Bearer ${auth}`}:{ };if(body!==undefined)headers['Content-Type']='application/json';const r=await fetch(`${apiBase}${path}`,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});let data=null;try{data=await r.json();}catch{}return{status:r.status,body:data};}
async function user(key,role='patient',patient=true){const u={id:crypto.randomUUID(),role,email:`${marker}_${key}@medorbit.test`};users.push(u.id);await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version) VALUES($1,$2,'s4-test',$3,true,true,1)`,[u.id,u.email,role]);await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en) VALUES($1,'اختبار','اجتماعي',$2,'Social')`,[u.id,key]);if(patient){u.patientId=crypto.randomUUID();await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)',[u.patientId,u.id]);}return u;}
async function doctor(key,status='approved'){const u=await user(key,'doctor',true);u.doctorId=crypto.randomUUID();await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,approval_status,approved_at) VALUES($1,$2,$3,$4,NOW())`,[u.doctorId,u.id,`${marker}-${key}`,status]);return u;}
async function createPost(doc,body,isPublished=false,title='Social title'){return request('POST','/doctors/me/posts',token(doc),{titleEn:title,body,category:'health_tip',isPublished,doctor_id:crypto.randomUUID()});}
async function cleanup(){
 await pool.query(`DELETE FROM medorbit.processed_events WHERE event_id IN (SELECT id FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN (SELECT id FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN (SELECT id FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.post_comments WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.post_likes WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]) OR doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctor_posts WHERE doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.medical_records WHERE patient_id IN(SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])) OR patient_id IN(SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])',[users]).catch(()=>{});
 await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])',[users]).catch(()=>{});
}
async function residual(){return(await pool.query(`SELECT
 (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
 (SELECT count(*) FROM medorbit.doctor_posts WHERE doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])))::int posts,
 (SELECT count(*) FROM medorbit.post_likes WHERE user_id=ANY($1::uuid[]))::int likes,
 (SELECT count(*) FROM medorbit.post_comments WHERE user_id=ANY($1::uuid[]))::int comments,
 (SELECT count(*) FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]))::int follows,
 (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int events`,[users])).rows[0];}

(async()=>{console.log('\nS4 doctor social feed adversarial tests\n');try{
 const patient=await user('patient'); const other=await user('other'); const admin=await user('admin','admin',false);
 const doc1=await doctor('doctor1'); const doc2=await doctor('doctor2'); const suspended=await doctor('suspended','suspended');
 const draft=await createPost(doc1,'Draft body',false);
 check('approved doctor can create draft',draft.status===201&&draft.body.data.status==='draft'&&draft.body.data.moderation_status==='pending',JSON.stringify(draft.body));
 const published=await createPost(doc1,'Published body',true,'Published title'); const postId=published.body?.data?.id;
 check('approved doctor auto-publishes under model B',published.status===201&&published.body.data.status==='published'&&published.body.data.moderation_status==='approved');
 check('client doctor_id cannot control author',postId&&Number((await pool.query('SELECT count(*) FROM medorbit.doctor_posts WHERE id=$1 AND doctor_id=$2',[postId,doc1.doctorId])).rows[0].count)===1);
 check('suspended doctor cannot create post',(await createPost(suspended,'blocked',true)).status===403);
 check('doctor cannot edit another doctor post',(await request('PUT',`/doctors/me/posts/${postId}`,token(doc2),{body:'tamper'})).status===404);
 check('doctor can update own post',(await request('PUT',`/doctors/me/posts/${postId}`,token(doc1),{body:'Updated published body'})).status===200);
 const own=await request('GET','/doctors/me/posts',token(doc1));
 check('doctor own list exposes lifecycle and engagement fields',own.status===200&&own.body.data.some(p=>p.id===postId&&'moderation_status'in p&&'like_count'in p));

 // The health feed used to be anonymously readable. Under the guest policy
 // (guest -> home.html only) it is product data and requires an account, so
 // the feed's own contract is now exercised through a signed-in reader.
 check('anonymous caller cannot read the feed',(await request('GET','/feed/posts?limit=1',null)).status===401);
 check('anonymous caller cannot read post comments',(await request('GET',`/feed/posts/${postId}/comments`,null)).status===401);
 const anonymous=await request('GET','/feed/posts?limit=1',token(patient));
 check('feed includes eligible post',anonymous.status===200&&anonymous.body.data.items[0]?.id===postId);
 check('feed DTO excludes email/internal user id',!JSON.stringify(anonymous.body).includes('@medorbit.test')&&!JSON.stringify(anonymous.body).includes(doc1.id));
 check('draft post excluded from feed',!anonymous.body.data.items.some(p=>p.id===draft.body.data.id));
 const second=await createPost(doc1,'Second published',true,'Second'); const third=await createPost(doc1,'Third published',true,'Third');
 const page1=await request('GET','/feed/posts?limit=2',token(patient)); const page2=await request('GET',`/feed/posts?limit=2&cursor=${encodeURIComponent(page1.body.data.next_cursor)}`,token(patient));
 check('cursor pagination is stable',page1.status===200&&page1.body.data.items.length===2&&page2.status===200&&page2.body.data.items.every(p=>!page1.body.data.items.some(x=>x.id===p.id)));
 check('feed ordering deterministic',page1.body.data.items.every((p,i,a)=>i===0||new Date(a[i-1].published_at)>=new Date(p.published_at)));

 const like=await request('POST',`/feed/posts/${postId}/like`,token(patient),{user_id:other.id});
 check('authenticated user can like and client user_id ignored',like.status===200&&like.body.data.created&&Number((await pool.query('SELECT count(*) FROM medorbit.post_likes WHERE post_id=$1 AND user_id=$2',[postId,patient.id])).rows[0].count)===1);
 const duplicateLike=await request('POST',`/feed/posts/${postId}/like`,token(patient),{});
 check('duplicate like prevented',duplicateLike.status===200&&!duplicateLike.body.data.created&&duplicateLike.body.data.like_count===1);
 check('like event created once',Number((await pool.query("SELECT count(*) FROM medorbit.user_events WHERE user_id=$1 AND entity_id=$2 AND event_type='post_like'",[patient.id,postId])).rows[0].count)===1);
 const personalized=await request('GET','/feed/posts?limit=10',token(patient));
 check('authenticated feed reports like flag',personalized.body.data.items.find(p=>p.id===postId)?.liked_by_me===true);
 const unlike=await request('DELETE',`/feed/posts/${postId}/like`,token(patient));
 check('unlike removes state and records event',unlike.status===200&&unlike.body.data.removed&&Number((await pool.query("SELECT count(*) FROM medorbit.user_events WHERE user_id=$1 AND entity_id=$2 AND event_type='post_unlike'",[patient.id,postId])).rows[0].count)===1);

 check('unauthenticated cannot comment',(await request('POST',`/feed/posts/${postId}/comments`,null,{body:'hello'})).status===401);
 check('empty comment rejected',(await request('POST',`/feed/posts/${postId}/comments`,token(patient),{body:' '})).status===400);
 check('oversized comment rejected',(await request('POST',`/feed/posts/${postId}/comments`,token(patient),{body:'x'.repeat(1001)})).status===400);
 const comment=await request('POST',`/feed/posts/${postId}/comments`,token(patient),{body:'Helpful medical post',user_id:other.id}); const commentId=comment.body?.data?.id;
 check('authenticated user can comment',comment.status===201&&commentId);
 const comments=await request('GET',`/feed/posts/${postId}/comments`,token(patient));
 check('comment DTO is safe',comments.status===200&&comments.body.data.some(c=>c.id===commentId)&&!JSON.stringify(comments.body).includes('@medorbit.test')&&!JSON.stringify(comments.body).includes(patient.id));
 check('comment creates event',Number((await pool.query("SELECT count(*) FROM medorbit.user_events WHERE user_id=$1 AND entity_id=$2 AND event_type='post_comment'",[patient.id,postId])).rows[0].count)===1);
 await request('POST',`/admin/social/comments/${commentId}/moderate`,token(admin),{action:'hide'});
 check('hidden comment excluded',!(await request('GET',`/feed/posts/${postId}/comments`,token(patient))).body.data.some(c=>c.id===commentId));

 const follow=await request('POST',`/doctors/${doc1.doctorId}/follow`,token(patient),{user_id:other.id});
 check('user can follow approved doctor and client id ignored',follow.status===200&&follow.body.data.created&&Number((await pool.query('SELECT count(*) FROM medorbit.user_follows WHERE user_id=$1 AND doctor_id=$2',[patient.id,doc1.doctorId])).rows[0].count)===1);
 check('duplicate follow prevented',!(await request('POST',`/doctors/${doc1.doctorId}/follow`,token(patient),{})).body.data.created);
 check('follow creates event once',Number((await pool.query("SELECT count(*) FROM medorbit.user_events WHERE user_id=$1 AND entity_id=$2 AND event_type='doctor_follow'",[patient.id,doc1.doctorId])).rows[0].count)===1);
 check('cannot follow suspended doctor',(await request('POST',`/doctors/${suspended.doctorId}/follow`,token(patient),{})).status===404);
 check('follow creates no care relationship',Number((await pool.query('SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE patient_id=$1 AND doctor_id=$2',[patient.patientId,doc1.doctorId])).rows[0].count)===0);
 const protectedRecord=crypto.randomUUID();await pool.query(`INSERT INTO medorbit.medical_records(id,record_number,patient_id,doctor_id,diagnosis,is_draft,visible_to_patient) VALUES($1,$2,$3,$4,'private',false,false)`,[protectedRecord,`${marker}-MR`,other.patientId,doc1.doctorId]);
 check('follow grants no clinical access',(await request('GET',`/medical-records/${protectedRecord}`,token(patient))).status===404);
 const followedFeed=await request('GET','/feed/posts?limit=10',token(patient));
 check('authenticated feed reports follow flag',followedFeed.body.data.items.find(p=>p.id===postId)?.following_doctor===true);
 const unfollow=await request('DELETE',`/doctors/${doc1.doctorId}/follow`,token(patient));
 check('unfollow removes state and records event',unfollow.status===200&&unfollow.body.data.removed&&Number((await pool.query("SELECT count(*) FROM medorbit.user_events WHERE user_id=$1 AND entity_id=$2 AND event_type='doctor_unfollow'",[patient.id,doc1.doctorId])).rows[0].count)===1);

 check('patient cannot moderate post',(await request('POST',`/admin/social/posts/${postId}/moderate`,token(patient),{action:'hide'})).status===403);
 const hidden=await request('POST',`/admin/social/posts/${postId}/moderate`,token(admin),{action:'hide'});
 check('admin can hide post',hidden.status===200&&hidden.body.data.moderation_status==='hidden');
 check('hidden post excluded from feed',!(await request('GET','/feed/posts?limit=30',token(patient))).body.data.items.some(p=>p.id===postId));
 check('doctor cannot self-bypass hidden moderation',(await request('PUT',`/doctors/me/posts/${postId}`,token(doc1),{isPublished:true})).status===403);
 const eventBefore=Number((await pool.query('SELECT count(*) FROM medorbit.user_events WHERE user_id=$1',[patient.id])).rows[0].count);
 check('cannot like hidden post',(await request('POST',`/feed/posts/${postId}/like`,token(patient),{})).status===404);
 check('failed social mutation creates no success event',Number((await pool.query('SELECT count(*) FROM medorbit.user_events WHERE user_id=$1',[patient.id])).rows[0].count)===eventBefore);
 check('cannot comment on hidden post',(await request('POST',`/feed/posts/${postId}/comments`,token(patient),{body:'blocked'})).status===404);
 await request('POST',`/admin/social/posts/${postId}/moderate`,token(admin),{action:'approve'});
 check('admin can restore approved post',(await request('GET','/feed/posts?limit=30',token(patient))).body.data.items.some(p=>p.id===postId));
 await request('POST',`/admin/social/posts/${second.body.data.id}/moderate`,token(admin),{action:'reject'});
 check('rejected post excluded from feed',!(await request('GET','/feed/posts?limit=30',token(patient))).body.data.items.some(p=>p.id===second.body.data.id));

 await pool.query("UPDATE medorbit.doctors SET approval_status='suspended' WHERE id=$1",[doc1.doctorId]);
 check('suspended doctor post excluded from feed',!(await request('GET','/feed/posts?limit=30',token(patient))).body.data.items.some(p=>p.id===postId));
 check('suspended doctor cannot update post',(await request('PUT',`/doctors/me/posts/${postId}`,token(doc1),{body:'blocked'})).status===403);
 await pool.query("UPDATE medorbit.doctors SET approval_status='approved' WHERE id=$1",[doc1.doctorId]);
 const deleted=await request('DELETE',`/doctors/me/posts/${third.body.data.id}`,token(doc1));
 check('doctor soft-deletes own post',deleted.status===200&&Number((await pool.query('SELECT count(*) FROM medorbit.doctor_posts WHERE id=$1 AND deleted_at IS NOT NULL',[third.body.data.id])).rows[0].count)===1);
 check('soft-deleted post excluded from feed',!(await request('GET','/feed/posts?limit=30',token(patient))).body.data.items.some(p=>p.id===third.body.data.id));
 const events=await pool.query('SELECT event_type,metadata FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])',[users]);
 check('event payload contains no PHI',events.rows.every(e=>!/(patient|appointment|diagnosis|clinical|email|token|password)/i.test(JSON.stringify(e.metadata))));
 check('view event is daily-idempotent',(await request('POST',`/feed/posts/${postId}/view`,token(patient),{})).status===200&&(await request('POST',`/feed/posts/${postId}/view`,token(patient),{})).body.data.recorded===false);
 }catch(err){failed++;console.error('  ✗ suite error:',err.stack||err.message);}finally{await cleanup();const counts=await residual();console.log(`S4 residual counts: ${JSON.stringify(counts)}`);check('S4 fixtures leave zero residual rows',Object.values(counts).every(v=>Number(v)===0));await pool.end();}
 console.log(`\nS4 social feed: ${passed} passed, ${failed} failed`);if(failed)process.exitCode=1;
})();
