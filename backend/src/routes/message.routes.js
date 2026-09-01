const express=require('express');
const rateLimit=require('express-rate-limit');
const {authenticate}=require('../middleware/auth');
const {success,error}=require('../utils/response');
const messaging=require('../services/messaging.service');
const {MessagingPolicyError}=require('../services/messagingPolicy.service');

const router=express.Router();
// Messaging authorization is conversation-member based. Do not reject an
// admin here: the service returns the same 404 for every non-member, which
// keeps private conversation existence undisclosed.
router.use(authenticate);
const createLimiter=rateLimit({windowMs:15*60*1000,max:20,standardHeaders:true,legacyHeaders:false});
const sendLimiter=rateLimit({windowMs:60*1000,max:120,standardHeaders:true,legacyHeaders:false});
function handle(err,res,next){return err instanceof MessagingPolicyError?error(res,err.message,err.status,err.code):next(err);}

router.post('/conversations',authenticate,createLimiter,async(req,res,next)=>{
    try{
        if('role'in req.body||'relationship_id'in req.body||'relationshipId'in req.body||'user_id'in req.body||'userId'in req.body)
            return error(res,'Client ownership fields are not accepted',400,'VALIDATION_ERROR');
        const result=await messaging.createConversation({userId:req.user.sub,role:req.user.role,
            counterpartId:req.body.counterpartId||req.body.counterpart_id});
        return success(res,result.conversation,result.created?'Conversation created':'Conversation retrieved',result.created?201:200);
    }catch(err){return handle(err,res,next);}
});
router.get('/conversations',authenticate,async(req,res,next)=>{
    try{return success(res,await messaging.listConversations(req.user.sub,req.query),'Conversations retrieved');}
    catch(err){return handle(err,res,next);}
});
router.get('/conversations/:id/messages',authenticate,async(req,res,next)=>{
    try{return success(res,await messaging.listMessages(req.params.id,req.user.sub,req.query),'Messages retrieved');}
    catch(err){return handle(err,res,next);}
});
router.post('/conversations/:id/messages',authenticate,sendLimiter,async(req,res,next)=>{
    try{
        if('sender_user_id'in req.body||'senderUserId'in req.body)
            return error(res,'Client sender identity is not accepted',400,'VALIDATION_ERROR');
        const result=await messaging.sendMessage({conversationId:req.params.id,userId:req.user.sub,body:req.body.body,
            clientMessageId:req.body.client_message_id||req.body.clientMessageId});
        return success(res,{...result.message,idempotent:!result.created},result.created?'Message sent':'Message already accepted',result.created?201:200);
    }catch(err){return handle(err,res,next);}
});
router.post('/conversations/:id/read',authenticate,async(req,res,next)=>{
    try{return success(res,await messaging.markRead(req.params.id,req.user.sub,req.body?.message_id||null),'Conversation marked read');}
    catch(err){return handle(err,res,next);}
});

router.post('/conversations/:id/accept',authenticate,async(req,res,next)=>{
    try{return success(res,await messaging.respondToRequest(req.params.id,req.user.sub,'accepted'),'Message request accepted');}
    catch(err){return handle(err,res,next);}
});

router.post('/conversations/:id/decline',authenticate,async(req,res,next)=>{
    try{return success(res,await messaging.respondToRequest(req.params.id,req.user.sub,'declined'),'Message request declined');}
    catch(err){return handle(err,res,next);}
});
module.exports=router;
