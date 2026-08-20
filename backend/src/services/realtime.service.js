let io = null;

function setRealtimeServer(server) { io = server; }
function emitToConversation(conversationId, event, payload) {
    if (!io) return false;
    try { io.to(`conversation:${conversationId}`).emit(event, payload); return true; }
    catch { return false; }
}
function emitMessageCreated(message) { return emitToConversation(message.conversation_id, 'message.created', message); }

module.exports = { setRealtimeServer,emitToConversation,emitMessageCreated };
