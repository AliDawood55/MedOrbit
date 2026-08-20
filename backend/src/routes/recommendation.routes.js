const express = require('express');
const rateLimit = require('express-rate-limit');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { recordUserEvent } = require('../services/userEvent.service');
const { getRankedDoctors } = require('../services/recommendation.service');

const router = express.Router();
const signalLimiter = rateLimit({ windowMs:60_000,max:30,standardHeaders:true,legacyHeaders:false });

router.get('/doctors',authenticate,async(req,res,next)=>{
    try{
        const limit=Math.min(Math.max(Number.parseInt(req.query.limit,10)||10,1),30);
        const doctors=await getRankedDoctors({userId:req.user?.sub||null,limit});
        return success(res,{doctors},'Recommended doctors retrieved');
    }catch(err){return next(err);}
});

router.post('/specialties/:id/search',signalLimiter,authenticate,async(req,res,next)=>{
    const client=await db.getClient();
    try{
        await client.query('BEGIN');
        const specialty=(await client.query('SELECT id FROM medorbit.specialties WHERE id=$1 AND is_active=true',[req.params.id])).rows[0];
        if(!specialty){await client.query('ROLLBACK');return error(res,'Specialty not found',404,'NOT_FOUND');}
        const day=new Date().toISOString().slice(0,10);
        const recorded=await recordUserEvent({userId:req.user.sub,eventType:'search_specialty',entityType:'specialty',entityId:specialty.id,
            metadata:{specialty_id:specialty.id},dedupeKey:`search_specialty:${req.user.sub}:${specialty.id}:${day}`},client);
        await client.query('COMMIT');
        return success(res,{recorded:!!recorded},'Specialty search recorded');
    }catch(err){await client.query('ROLLBACK').catch(()=>{});return next(err);}finally{client.release();}
});

module.exports=router;
