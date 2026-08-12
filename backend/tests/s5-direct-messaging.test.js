const crypto=require('crypto');
const {Pool}=require('pg');
const {io:socketClient}=require('socket.io-client');
const {apiBase,poolConfig}=require('./helpers/test-environment');
const {generateAccessToken,generateRefreshToken}=require('../src/utils/jwt');
const messaging=require('../src/services/messaging.service');

const pool=new Pool(poolConfig),run=Date.now(),marker=`S5${String(run).slice(-8)}`,users=[];
let passed=0,failed=0;
function check(name,ok,detail=''){if(ok){passed++;console.log(`  ✓ ${name}`);}else{failed++;console.error(`  ✗ ${name}${detail?` — ${detail}`:''}`);}}
function token(u,version=u.version||1){return generateAccessToken({sub:u.id,role:u.role,authorizationVersion:version});}
async function request(method,path,auth,body){const headers=auth?{Authorization:`Bearer ${auth}`}:{ };if(body!==undefined)headers['Content-Type']='application/json';const r=await fetch(`${apiBase}${path}`,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});let data=null;try{data=await r.json();}catch{}return{status:r.status,body:data};}
async function user(key,role='patient',withPatient=role==='patient'){
 const u={id:crypto.randomUUID(),role,email:`${marker}_${key}@medorbit.test`,version:1};users.push(u.id);
 await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version) VALUES($1,$2,'s5-test',$3,true,true,1)`,[u.id,u.email,role]);
 await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en) VALUES($1,'اختبار','رسائل',$2,'Messaging')`,[u.id,key]);
 if(withPatient){u.patientId=crypto.randomUUID();await pool.query(`INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)`,[u.patientId,u.id]);}
 return u;
}
async function doctor(key,status='approved'){
 const u=await user(key,'doctor',true);u.doctorId=crypto.randomUUID();
 await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,approval_status,approved_at) VALUES($1,$2,$3,$4,NOW())`,[u.doctorId,u.id,`${marker}-${key}`,status]);return u;
}
async function relationship(doc,patient,status='active'){
 const id=crypto.randomUUID();await pool.query(`INSERT INTO medorbit.doctor_patient_relationships(id,doctor_id,patient_id,status,source,started_at,ended_at)
 VALUES($1,$2,$3,$4::varchar,'manual_assign',NOW(),CASE WHEN $4::varchar IN ('ended','revoked') THEN NOW() ELSE NULL END)`,[id,doc.doctorId,patient.patientId,status]);return id;
}
function connect(authToken){return socketClient(apiBase.replace(/\/api$/,''),{auth:{token:authToken},transports:['websocket'],forceNew:true,reconnection:false,timeout:2500});}
function connected(socket){return new Promise(resolve=>{socket.once('connect',()=>resolve(true));socket.once('connect_error',()=>resolve(false));});}
function subscribe(socket,id){return new Promise(resolve=>socket.emit('conversation.subscribe',{conversation_id:id},resolve));}
function waitEvent(socket,event,ms=2500){return new Promise(resolve=>{const timer=setTimeout(()=>resolve(null),ms);socket.once(event,data=>{clearTimeout(timer);resolve(data);});});}
async function cleanup(){
 await pool.query(`DELETE FROM medorbit.outbox_events WHERE event_type='direct.message.sent' AND aggregate_id IN(SELECT id FROM medorbit.direct_messages WHERE sender_user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[]) OR entity_id IN(SELECT conversation_id FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.direct_conversations WHERE id IN(SELECT conversation_id FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]) OR doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id IN(SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])) OR patient_id IN(SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])`,[users]).catch(()=>{});
 await pool.query(`DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])`,[users]).catch(()=>{});
}
async function residual(){return(await pool.query(`SELECT
 (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
 (SELECT count(*) FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))::int conversations,
 (SELECT count(*) FROM medorbit.direct_messages WHERE sender_user_id=ANY($1::uuid[]))::int messages,
 (SELECT count(*) FROM medorbit.notifications WHERE user_id=ANY($1::uuid[]))::int notifications,
 (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int events`,[users])).rows[0];}

(async()=>{console.log('\nS5 direct messaging adversarial tests\n');const sockets=[];try{
 const chatbotBefore=(await pool.query(`SELECT (SELECT count(*) FROM medorbit.chatbot_conversations)::int conversations,(SELECT count(*) FROM medorbit.chatbot_messages)::int messages`)).rows[0];
 const patient=await user('patient'),other=await user('other'),doc=await doctor('doctor'),unrelatedDoc=await doctor('unrelated'),suspended=await doctor('suspended','suspended');
 const admin=await user('admin','admin',false),superAdmin=await user('super','super_admin',false);
 const activeRelationship=await relationship(doc,patient),endedRelationship=await relationship(doc,other,'ended');
 const followOnly=await user('follow');await pool.query(`INSERT INTO medorbit.user_follows(user_id,doctor_id) VALUES($1,$2)`,[followOnly.id,doc.doctorId]);

 let r=await request('POST','/messages/conversations',token(patient),{counterpartId:doc.doctorId});const conversationId=r.body?.data?.id;
 check('active related patient can create conversation',r.status===201&&conversationId,JSON.stringify(r.body));
 const duplicate=await request('POST','/messages/conversations',token(patient),{counterpartId:doc.doctorId});
 check('duplicate create returns canonical conversation',duplicate.status===200&&duplicate.body?.data?.id===conversationId);
 check('doctor gets same canonical conversation',(await request('POST','/messages/conversations',token(doc),{counterpartId:patient.patientId})).body?.data?.id===conversationId);
 check('unrelated patient can initiate approved doctor conversation',(await request('POST','/messages/conversations',token(other),{counterpartId:doc.doctorId})).status===201);
 check('unrelated doctor denied',(await request('POST','/messages/conversations',token(unrelatedDoc),{counterpartId:patient.patientId})).status===404);
 check('follow-only patient can initiate independently',(await request('POST','/messages/conversations',token(followOnly),{counterpartId:doc.doctorId})).status===201);
 check('ended relationship does not block ordinary patient initiation',(await request('POST','/messages/conversations',token(other),{counterpartId:doc.doctorId})).status===200);
 await pool.query(`UPDATE medorbit.doctor_patient_relationships SET status='revoked' WHERE id=$1`,[endedRelationship]);
 check('revoked relationship remains separate from accepted messaging',(await request('POST','/messages/conversations',token(other),{counterpartId:doc.doctorId})).status===200);
 check('suspended doctor denied',(await request('POST','/messages/conversations',token(suspended),{counterpartId:patient.patientId})).status===403);
 check('exactly two eligible members',Number((await pool.query(`SELECT count(*) FROM medorbit.conversation_members WHERE conversation_id=$1`,[conversationId])).rows[0].count)===2);
 check('admin is not automatically a member',Number((await pool.query(`SELECT count(*) FROM medorbit.conversation_members WHERE conversation_id=$1 AND user_id=$2`,[conversationId,admin.id])).rows[0].count)===0);
 check('client ownership fields rejected',(await request('POST','/messages/conversations',token(patient),{counterpartId:doc.doctorId,user_id:other.id})).status===400);

 const patientMessageId=crypto.randomUUID();r=await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:'Patient hello',client_message_id:patientMessageId});
 check('patient member can send',r.status===201&&r.body?.data?.sender_user_id===patient.id);
 const doctorMessageId=crypto.randomUUID();r=await request('POST',`/messages/conversations/${conversationId}/messages`,token(doc),{body:'Doctor hello',client_message_id:doctorMessageId});
 check('doctor member can send',r.status===201&&r.body?.data?.sender_user_id===doc.id);
 check('unrelated user cannot send',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(other),{body:'probe',client_message_id:crypto.randomUUID()})).status===404);
 check('UUID possession grants no access',(await request('GET',`/messages/conversations/${conversationId}/messages`,token(other))).status===404);
 check('client sender identity rejected',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:'spoof',client_message_id:crypto.randomUUID(),sender_user_id:doc.id})).status===400);
 check('empty message rejected',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:' ',client_message_id:crypto.randomUUID()})).status===400);
 check('oversized message rejected',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:'x'.repeat(4001),client_message_id:crypto.randomUUID()})).status===400);
 const notificationBefore=Number((await pool.query(`SELECT count(*) FROM medorbit.notifications WHERE user_id=$1`,[doc.id])).rows[0].count);
 const retryId=crypto.randomUUID(),secret=`secret-${marker}`;
 const firstRetry=await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:secret,client_message_id:retryId});
 const secondRetry=await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:secret,client_message_id:retryId});
 check('idempotent retry returns same message',firstRetry.body?.data?.id===secondRetry.body?.data?.id&&secondRetry.body?.data?.idempotent===true);
 check('retry creates one DB row',Number((await pool.query(`SELECT count(*) FROM medorbit.direct_messages WHERE conversation_id=$1 AND sender_user_id=$2 AND client_message_id=$3`,[conversationId,patient.id,retryId])).rows[0].count)===1);
 check('retry creates one notification',Number((await pool.query(`SELECT count(*) FROM medorbit.notifications WHERE user_id=$1`,[doc.id])).rows[0].count)===notificationBefore+1);
 check('retry creates one user event',Number((await pool.query(`SELECT count(*) FROM medorbit.user_events WHERE entity_id=$1`,[firstRetry.body.data.id])).rows[0].count)===1);
 for(let i=0;i<3;i++)await request('POST',`/messages/conversations/${conversationId}/messages`,token(doc),{body:`page-${i}`,client_message_id:crypto.randomUUID()});
 const page1=await request('GET',`/messages/conversations/${conversationId}/messages?limit=2`,token(patient));
 const page2=await request('GET',`/messages/conversations/${conversationId}/messages?limit=2&cursor=${encodeURIComponent(page1.body.data.next_cursor)}`,token(patient));
 check('history cursor pagination is stable',page1.status===200&&page2.status===200&&page1.body.data.items.every(a=>!page2.body.data.items.some(b=>a.id===b.id)));
 check('member can read history',page1.body.data.items.length===2);
 check('admin cannot read without membership',(await request('GET',`/messages/conversations/${conversationId}/messages`,token(admin))).status===404);
 check('super admin cannot read without membership',(await request('GET',`/messages/conversations/${conversationId}/messages`,token(superAdmin))).status===404);
 const beforeRead=await request('GET','/messages/conversations',token(patient));
 check('unread count is PostgreSQL-backed',beforeRead.body.data.items.find(x=>x.id===conversationId).unread_count>=4);
 const latest=page1.body.data.items[page1.body.data.items.length-1];await request('POST',`/messages/conversations/${conversationId}/read`,token(patient),{message_id:latest.id});
 const afterRead=await request('GET','/messages/conversations',token(patient));
 check('mark-read persists',afterRead.body.data.items.find(x=>x.id===conversationId).unread_count===0);

 const patientSocket=connect(token(patient)),otherSocket=connect(token(other));sockets.push(patientSocket,otherSocket);
 check('valid access token connects',await connected(patientSocket));check('unrelated valid user socket connects',await connected(otherSocket));
 const refreshSocket=connect(generateRefreshToken({sub:patient.id,role:'patient',authorizationVersion:1}));sockets.push(refreshSocket);
 check('refresh token rejected by socket',!(await connected(refreshSocket)));
 const invalidSocket=connect('not-a-token');sockets.push(invalidSocket);check('invalid token rejected by socket',!(await connected(invalidSocket)));
 check('non-member cannot subscribe',!(await subscribe(otherSocket,conversationId)).ok);
 check('member can subscribe',(await subscribe(patientSocket,conversationId)).ok===true);
 let eventPromise=waitEvent(patientSocket,'message.created');const liveId=crypto.randomUUID();
 const liveSend=await request('POST',`/messages/conversations/${conversationId}/messages`,token(doc),{body:'live-safe',client_message_id:liveId});
 const liveEvent=await eventPromise;
 check('member receives already-persisted message',liveEvent?.id===liveSend.body?.data?.id&&Number((await pool.query(`SELECT count(*) FROM medorbit.direct_messages WHERE id=$1`,[liveEvent?.id])).rows[0].count)===1);
 let leaked=false;otherSocket.once('message.created',()=>{leaked=true;});await new Promise(resolve=>setTimeout(resolve,150));
 check('unrelated socket receives nothing',!leaked);
 patientSocket.disconnect();const missedId=crypto.randomUUID();await request('POST',`/messages/conversations/${conversationId}/messages`,token(doc),{body:'missed-safe',client_message_id:missedId});
 const reconnect=connect(token(patient));sockets.push(reconnect);check('reconnect reauthenticates',await connected(reconnect));
 const missed=await request('GET',`/messages/conversations/${conversationId}/messages?after=${encodeURIComponent(page1.body.data.latest_cursor)}`,token(patient));
 check('reconnect can fetch missed persisted message',missed.body.data.items.some(m=>m.client_message_id===missedId));
 const staleSocket=connect(token(patient,0));sockets.push(staleSocket);check('stale authorization version rejected',!(await connected(staleSocket)));
 const noEmitterId=crypto.randomUUID();const direct=await messaging.sendMessage({conversationId,userId:patient.id,body:'persist without local emitter',clientMessageId:noEmitterId});
 check('realtime emission absence does not lose message',direct.created&&Number((await pool.query(`SELECT count(*) FROM medorbit.direct_messages WHERE id=$1`,[direct.message.id])).rows[0].count)===1);

 await pool.query(`UPDATE medorbit.doctors SET approval_status='suspended' WHERE id=$1`,[doc.doctorId]);
 check('suspended doctor send denied',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(doc),{body:'blocked',client_message_id:crypto.randomUUID()})).status===403);
 check('suspended conversation subscription denied',!(await subscribe(reconnect,conversationId)).ok);
 await pool.query(`UPDATE medorbit.doctors SET approval_status='approved' WHERE id=$1`,[doc.doctorId]);
 await pool.query(`UPDATE medorbit.doctor_patient_relationships SET status='ended',ended_at=NOW() WHERE id=$1`,[activeRelationship]);
 check('ended relationship does not revoke accepted text thread',(await request('POST',`/messages/conversations/${conversationId}/messages`,token(patient),{body:'still-text-only',client_message_id:crypto.randomUUID()})).status===201);
 check('members retain historical read access after relationship ends',(await request('GET',`/messages/conversations/${conversationId}/messages`,token(patient))).status===200);

 const notificationText=JSON.stringify((await pool.query(`SELECT title_ar,title_en,message_ar,message_en FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])`,[users])).rows);
 check('notifications exclude full message body',!notificationText.includes(secret)&&!notificationText.includes('Patient hello'));
 const eventText=JSON.stringify((await pool.query(`SELECT metadata FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])`,[users])).rows);
 check('user events exclude message body',!eventText.includes(secret)&&!eventText.includes('Patient hello'));
 const auditText=JSON.stringify((await pool.query(`SELECT old_values,new_values FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])`,[users])).rows);
 check('audit logs do not copy message bodies',!auditText.includes(secret)&&!auditText.includes('Patient hello'));
 const apiText=JSON.stringify((await request('GET',`/messages/conversations/${conversationId}/messages?limit=5`,token(patient))).body);
 check('messaging APIs expose no clinical record data',!/(diagnosis|medical_record|prescription|appointment_id)/i.test(apiText));
 check('follow creates no clinical relationship',Number((await pool.query(`SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE patient_id=$1`,[followOnly.patientId])).rows[0].count)===0);
 const chatbotAfter=(await pool.query(`SELECT (SELECT count(*) FROM medorbit.chatbot_conversations)::int conversations,(SELECT count(*) FROM medorbit.chatbot_messages)::int messages`)).rows[0];
 check('AI chatbot tables remain untouched',JSON.stringify(chatbotBefore)===JSON.stringify(chatbotAfter));
 }catch(err){failed++;console.error('  ✗ suite error:',err.stack||err.message);}finally{
  for(const socket of sockets)socket.disconnect();await cleanup();const counts=await residual();console.log(`S5 residual counts: ${JSON.stringify(counts)}`);
  check('S5 fixtures leave zero residual rows',Object.values(counts).every(v=>Number(v)===0));await pool.end();
 }
 console.log(`\nS5 direct messaging: ${passed} passed, ${failed} failed`);process.exit(failed?1:0);
})();
