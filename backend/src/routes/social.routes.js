const express = require('express');
const rateLimit = require('express-rate-limit');
const db = require('../config/database');
const { authenticate, authorizeAdmin } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const { findEligiblePost, findFollowableDoctor } = require('../services/socialPolicy.service');
const { recordUserEvent } = require('../services/userEvent.service');
const { createAudit } = require('../services/audit.service');
const { getRankedFeed } = require('../services/recommendation.service');

const feedRoutes = express.Router();
const socialDoctorRoutes = express.Router();
const adminSocialRoutes = express.Router();

const mutationLimiter = rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false });
const commentLimiter = rateLimit({ windowMs: 60_000, max: 10, standardHeaders: true, legacyHeaders: false });

feedRoutes.get('/posts', authenticate, async (req,res,next) => {
    try {
        const limit = Math.min(Math.max(Number.parseInt(req.query.limit,10) || 10,1),30);
        const ranked=await getRankedFeed({userId:req.user?.sub||null,limit,cursor:req.query.cursor||null});
        return success(res,ranked,'Feed retrieved');
    } catch (err) { if(err.code==='INVALID_CURSOR') return error(res,'Invalid cursor',400,'INVALID_CURSOR'); return next(err); }
});

feedRoutes.get('/posts/:id/comments', authenticate, async (req,res,next) => {
    try {
        if (!await findEligiblePost(req.params.id)) return error(res,'Post not found',404,'NOT_FOUND');
        const result = await db.query(
            `SELECT c.id,c.body,c.created_at,c.updated_at,
                    pr.first_name_ar,pr.last_name_ar,pr.first_name_en,pr.last_name_en,pr.profile_image_url
             FROM medorbit.post_comments c JOIN medorbit.users u ON u.id=c.user_id
             LEFT JOIN medorbit.user_profiles pr ON pr.user_id=u.id
             WHERE c.post_id=$1 AND c.deleted_at IS NULL AND c.moderation_status='approved'
               AND u.is_active=true AND u.deleted_at IS NULL
             ORDER BY c.created_at,c.id LIMIT 100`, [req.params.id]
        );
        return success(res,result.rows,'Comments retrieved');
    } catch (err) { return next(err); }
});

feedRoutes.post('/posts/:id/like', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        if (!await findEligiblePost(req.params.id,client)) { await client.query('ROLLBACK'); return error(res,'Post not found',404,'NOT_FOUND'); }
        const inserted=await client.query(`INSERT INTO medorbit.post_likes(post_id,user_id) VALUES($1,$2) ON CONFLICT(post_id,user_id) DO NOTHING RETURNING id`,[req.params.id,req.user.sub]);
        if (inserted.rows[0]) await recordUserEvent({userId:req.user.sub,eventType:'post_like',entityType:'doctor_post',entityId:req.params.id},client);
        const count=(await client.query('SELECT count(*)::int count FROM medorbit.post_likes WHERE post_id=$1',[req.params.id])).rows[0].count;
        await client.query('COMMIT');
        return success(res,{liked:true,like_count:count,created:!!inserted.rows[0]},'Post liked');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

feedRoutes.delete('/posts/:id/like', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        const removed=await client.query('DELETE FROM medorbit.post_likes WHERE post_id=$1 AND user_id=$2 RETURNING id',[req.params.id,req.user.sub]);
        if (removed.rows[0]) await recordUserEvent({userId:req.user.sub,eventType:'post_unlike',entityType:'doctor_post',entityId:req.params.id},client);
        const count=(await client.query('SELECT count(*)::int count FROM medorbit.post_likes WHERE post_id=$1',[req.params.id])).rows[0].count;
        await client.query('COMMIT');
        return success(res,{liked:false,like_count:count,removed:!!removed.rows[0]},'Post unliked');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

feedRoutes.post('/posts/:id/comments', commentLimiter, authenticate, async (req,res,next) => {
    const body=String(req.body.body || '').trim();
    if (!body || body.length>1000) return error(res,'Comment must be between 1 and 1000 characters',400,'VALIDATION_ERROR');
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        if (!await findEligiblePost(req.params.id,client)) { await client.query('ROLLBACK'); return error(res,'Post not found',404,'NOT_FOUND'); }
        const created=await client.query(`INSERT INTO medorbit.post_comments(post_id,user_id,body) VALUES($1,$2,$3) RETURNING id,body,created_at,updated_at`,[req.params.id,req.user.sub,body]);
        await recordUserEvent({userId:req.user.sub,eventType:'post_comment',entityType:'doctor_post',entityId:req.params.id,metadata:{comment_id:created.rows[0].id}},client);
        await client.query('COMMIT');
        return success(res,created.rows[0],'Comment created',201);
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

feedRoutes.delete('/comments/:id', mutationLimiter, authenticate, async (req,res,next) => {
    try {
        const result=await db.query(`UPDATE medorbit.post_comments SET deleted_at=NOW(),updated_at=NOW() WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL RETURNING id`,[req.params.id,req.user.sub]);
        if(!result.rows[0]) return error(res,'Comment not found',404,'NOT_FOUND');
        return success(res,{id:result.rows[0].id},'Comment deleted');
    } catch(err){ return next(err); }
});

feedRoutes.post('/posts/:id/view', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        if (!await findEligiblePost(req.params.id,client)) { await client.query('ROLLBACK'); return error(res,'Post not found',404,'NOT_FOUND'); }
        const day=new Date().toISOString().slice(0,10);
        const recorded=await recordUserEvent({userId:req.user.sub,eventType:'post_view',entityType:'doctor_post',entityId:req.params.id,dedupeKey:`post_view:${req.user.sub}:${req.params.id}:${day}`},client);
        await client.query('COMMIT');
        return success(res,{recorded:!!recorded},'Post view recorded');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

socialDoctorRoutes.post('/:id/follow', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        const followable=await findFollowableDoctor(req.params.id,client);
        if(!followable){ await client.query('ROLLBACK'); return error(res,'Doctor not found',404,'NOT_FOUND'); }
        if(followable.user_id===req.user.sub){ await client.query('ROLLBACK'); return error(res,'You cannot follow yourself',400,'SELF_FOLLOW_NOT_ALLOWED'); }
        const inserted=await client.query(`INSERT INTO medorbit.user_follows(user_id,doctor_id) VALUES($1,$2) ON CONFLICT(user_id,doctor_id) DO NOTHING RETURNING id`,[req.user.sub,req.params.id]);
        if(inserted.rows[0]) await recordUserEvent({userId:req.user.sub,eventType:'doctor_follow',entityType:'doctor',entityId:req.params.id},client);
        const count=(await client.query('SELECT count(*)::int count FROM medorbit.user_follows WHERE doctor_id=$1',[req.params.id])).rows[0].count;
        await client.query('COMMIT');
        return success(res,{following:true,follower_count:count,created:!!inserted.rows[0]},'Doctor followed');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

socialDoctorRoutes.delete('/:id/follow', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        const removed=await client.query('DELETE FROM medorbit.user_follows WHERE user_id=$1 AND doctor_id=$2 RETURNING id',[req.user.sub,req.params.id]);
        if(removed.rows[0]) await recordUserEvent({userId:req.user.sub,eventType:'doctor_unfollow',entityType:'doctor',entityId:req.params.id},client);
        const count=(await client.query('SELECT count(*)::int count FROM medorbit.user_follows WHERE doctor_id=$1',[req.params.id])).rows[0].count;
        await client.query('COMMIT');
        return success(res,{following:false,follower_count:count,removed:!!removed.rows[0]},'Doctor unfollowed');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

socialDoctorRoutes.post('/:id/view', mutationLimiter, authenticate, async (req,res,next) => {
    const client=await db.getClient();
    try {
        await client.query('BEGIN');
        if(!await findFollowableDoctor(req.params.id,client)){ await client.query('ROLLBACK'); return error(res,'Doctor not found',404,'NOT_FOUND'); }
        const day=new Date().toISOString().slice(0,10);
        const recorded=await recordUserEvent({userId:req.user.sub,eventType:'doctor_profile_view',entityType:'doctor',entityId:req.params.id,
            dedupeKey:`doctor_profile_view:${req.user.sub}:${req.params.id}:${day}`},client);
        await client.query('COMMIT');
        return success(res,{recorded:!!recorded},'Doctor profile view recorded');
    } catch(err){ await client.query('ROLLBACK').catch(()=>{}); return next(err); } finally { client.release(); }
});

adminSocialRoutes.get('/posts',authenticate,authorizeAdmin,async(req,res,next)=>{
    try{
        const moderation=req.query.moderation_status || null;
        const result=await db.query(`SELECT p.id,p.title_ar,p.title_en,p.body,p.category,p.status,p.moderation_status,p.published_at,p.created_at,
          d.id doctor_id,pr.first_name_ar,pr.last_name_ar,pr.first_name_en,pr.last_name_en
          FROM medorbit.doctor_posts p JOIN medorbit.doctors d ON d.id=p.doctor_id JOIN medorbit.users u ON u.id=d.user_id
          LEFT JOIN medorbit.user_profiles pr ON pr.user_id=u.id WHERE p.deleted_at IS NULL AND ($1::varchar IS NULL OR p.moderation_status=$1)
          ORDER BY p.created_at DESC LIMIT 100`,[moderation]);
        return success(res,result.rows.map((post)=>({
            ...post,
            title:post.title_ar||post.title_en||null
        })),'Moderation posts retrieved');
    }catch(err){return next(err);}
});

adminSocialRoutes.post('/posts/:id/moderate',authenticate,authorizeAdmin,async(req,res,next)=>{
    const action=String(req.body.action || '');
    if(!['approve','reject','hide'].includes(action)) return error(res,'Invalid moderation action',400,'VALIDATION_ERROR');
    const client=await db.getClient();
    try{
        await client.query('BEGIN');
        const status=action==='approve'?'approved':action==='reject'?'rejected':'hidden';
        const result=await client.query(`UPDATE medorbit.doctor_posts SET moderation_status=$2,updated_at=NOW() WHERE id=$1 AND deleted_at IS NULL RETURNING id,status,moderation_status`,[req.params.id,status]);
        if(!result.rows[0]){await client.query('ROLLBACK');return error(res,'Post not found',404,'NOT_FOUND');}
        await createAudit({user_id:req.user.sub,user_role:req.user.role,action:'DOCTOR_POST_MODERATED',entity_type:'DOCTOR_POST',entity_id:req.params.id,new_values:{moderation_status:status}},client);
        await client.query('COMMIT');
        return success(res,result.rows[0],'Post moderated');
    }catch(err){await client.query('ROLLBACK').catch(()=>{});return next(err);}finally{client.release();}
});

adminSocialRoutes.get('/comments',authenticate,authorizeAdmin,async(req,res,next)=>{
    try{
        const moderation=req.query.moderation_status || null;
        const result=await db.query(`SELECT c.id,c.post_id,c.body,c.moderation_status,c.created_at,
          pr.first_name_ar,pr.last_name_ar,pr.first_name_en,pr.last_name_en
          FROM medorbit.post_comments c JOIN medorbit.users u ON u.id=c.user_id
          LEFT JOIN medorbit.user_profiles pr ON pr.user_id=u.id
          WHERE c.deleted_at IS NULL AND ($1::varchar IS NULL OR c.moderation_status=$1)
          ORDER BY c.created_at DESC LIMIT 100`,[moderation]);
        return success(res,result.rows,'Moderation comments retrieved');
    }catch(err){return next(err);}
});

adminSocialRoutes.post('/comments/:id/moderate',authenticate,authorizeAdmin,async(req,res,next)=>{
    const action=String(req.body.action || '');
    if(!['approve','reject','hide'].includes(action)) return error(res,'Invalid moderation action',400,'VALIDATION_ERROR');
    try{
        const status=action==='approve'?'approved':action==='reject'?'rejected':'hidden';
        const result=await db.query(`UPDATE medorbit.post_comments SET moderation_status=$2,updated_at=NOW() WHERE id=$1 AND deleted_at IS NULL RETURNING id,moderation_status`,[req.params.id,status]);
        if(!result.rows[0]) return error(res,'Comment not found',404,'NOT_FOUND');
        return success(res,result.rows[0],'Comment moderated');
    }catch(err){return next(err);}
});

module.exports={feedRoutes,socialDoctorRoutes,adminSocialRoutes};
