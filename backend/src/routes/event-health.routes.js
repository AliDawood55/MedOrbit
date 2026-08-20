const express=require('express');
const db=require('../config/database');
const env=require('../config/env');
const {authenticate,authorizeAdmin}=require('../middleware/auth');
const router=express.Router();
// Outbox/Kafka health is operational telemetry about the platform's internals,
// not product data — admins only, never anonymous.
router.get('/',authenticate,authorizeAdmin,async(req,res,next)=>{try{const result=await db.query(`SELECT status,count(*)::int AS count FROM medorbit.outbox_events GROUP BY status`);
 const counts={pending:0,publishing:0,published:0,failed:0,dead:0};for(const row of result.rows)counts[row.status]=row.count;
 res.json({success:true,data:{kafkaEnabled:env.kafka.enabled,workerMode:'separate-process',topic:env.kafka.outboxTopic,outbox:counts}});
 }catch(error){next(error);}});
module.exports=router;
