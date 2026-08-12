const {Server}=require('socket.io');
const {verifyAccessToken}=require('./utils/jwt');
const {resolveAuthorizationContext}=require('./middleware/auth');
const {isAllowedCorsOrigin}=require('./config/cors');
const {getConversationAccess}=require('./services/messagingPolicy.service');
const {setRealtimeServer}=require('./services/realtime.service');

function initRealtime(httpServer){
    const io=new Server(httpServer,{cors:{origin(origin,callback){callback(null,isAllowedCorsOrigin(origin));},methods:['GET','POST'],
        credentials:process.env.CORS_ORIGIN!=='*'},transports:['websocket','polling'],maxHttpBufferSize:32*1024});
    io.use(async(socket,next)=>{
        try{
            const header=socket.handshake.headers.authorization;
            const raw=socket.handshake.auth?.token||(header?.startsWith('Bearer ')?header.slice(7):null);
            if(!raw)return next(new Error('UNAUTHORIZED'));
            const user=await resolveAuthorizationContext(verifyAccessToken(raw));
            if(!user)return next(new Error('UNAUTHORIZED'));
            socket.user=user;return next();
        }catch{return next(new Error('UNAUTHORIZED'));}
    });
    io.on('connection',socket=>{
        socket.on('conversation.subscribe',async(payload={},acknowledge=()=>{})=>{
            try{
                const conversationId=payload.conversation_id||payload.conversationId;
                await getConversationAccess(conversationId,socket.user.sub,{requireActiveEligibility:true});
                await socket.join(`conversation:${conversationId}`);
                acknowledge({ok:true,conversation_id:conversationId});
            }catch(err){acknowledge({ok:false,code:err.code||'FORBIDDEN'});}
        });
        socket.on('conversation.unsubscribe',async(payload={})=>{
            const conversationId=payload.conversation_id||payload.conversationId;
            if(conversationId)await socket.leave(`conversation:${conversationId}`);
        });
    });
    setRealtimeServer(io);return io;
}
module.exports={initRealtime};
