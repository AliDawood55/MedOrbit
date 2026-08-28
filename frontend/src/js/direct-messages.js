const DirectMessages=(()=>{
    let conversations=[],selected=null,socket=null,currentUser=null,nextCursor=null,latestCursor=null,ownDoctorId=null;
    let sending=false,connState='idle';
    let threadSyncTimer=null,listSyncTimer=null,threadSyncInFlight=false,listSyncInFlight=false;
    const renderedIds=new Set();
    const byId=id=>document.getElementById(id),isAr=()=>I18n.getLang()==='ar',copy=(ar,en)=>isAr()?ar:en;
    const uuid=()=>crypto.randomUUID?crypto.randomUUID():'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0,v=c==='x'?r:(r&3|8);return v.toString(16);});
    const cursorFor=message=>btoa(JSON.stringify([message.created_at,message.id])).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    const isNearBottom=el=>!el||(el.scrollHeight-el.scrollTop-el.clientHeight<120);
    const formatTime=iso=>new Date(iso).toLocaleTimeString(isAr()?'ar':'en-US',{hour:'2-digit',minute:'2-digit'});

const CONNECTION_LABELS={
        connecting:['جارٍ الاتصال…','Connecting…'],
        online:['متصل','Connected'],
        reconnecting:['إعادة الاتصال…','Reconnecting…'],
        offline:['غير متصل بالإنترنت','Offline'],
        unavailable:['تعذّر الاتصال المباشر','Live updates unavailable']
    };
    function setConnection(state){
        connState=state;
        const node=byId('connectionState');
        if(!node)return;
        node.className=`connection-state ${state}`;
        node.classList.toggle('hidden',state==='idle');
        const label=CONNECTION_LABELS[state];
        node.textContent=label?copy(label[0],label[1]):'';
        byId('connectionRetryBtn')?.remove();
        if(state==='unavailable'){
            const btn=document.createElement('button');
            btn.type='button';btn.id='connectionRetryBtn';btn.className='connection-retry';
            btn.textContent=copy('إعادة المحاولة','Retry');
            btn.addEventListener('click',()=>{
                if(!socket)return connectSocket();
                setConnection('connecting');
                socket.io.reconnection(true);
                socket.connect();
            });
            node.after(btn);
        }
    }

    function localize(){
        byId('messagesTitle').textContent=copy('الرسائل','Messages');
        byId('messagesSubtitle').textContent=copy('محادثات نصية خاصة داخل MedOrbit','Private text conversations inside MedOrbit');
        byId('conversationListTitle').textContent=copy('المحادثات','Conversations');
        byId('loadOlderBtn').textContent=copy('عرض رسائل أقدم','Load older messages');
        byId('sendLabel').textContent=copy('إرسال','Send');
        byId('messageInput').placeholder=copy('اكتب رسالة نصية…','Write a text message…');
        byId('messageInput').setAttribute('aria-label',copy('اكتب رسالة نصية','Write a text message'));
        byId('newConversationLabel').textContent=copy('رسالة جديدة','New message');
        byId('recipientPickerTitle').textContent=copy('بدء محادثة نصية','Start a text conversation');
        byId('recipientPickerHint').textContent=currentUser?.role==='doctor'?copy('ابحث عن طبيب معتمد أو مريض اختار استقبال طلبات الأطباء.','Find an approved doctor or an opted-in patient.'):copy('ابحث عن طبيب معتمد.','Find an approved doctor.');
        byId('recipientSearchInput').placeholder=copy('ابحث بالاسم أو التخصص أو المدينة','Search by name, specialty, or city');
        byId('recipientSearchLabel').textContent=copy('بحث','Search');
        byId('jumpLatestBtn')?.setAttribute('aria-label',copy('الانتقال إلى أحدث رسالة','Jump to latest message'));
        if(!selected)byId('threadName').textContent=copy('اختر محادثة','Select a conversation');
        if(selected)renderRequestState();
        if(connState!=='idle')setConnection(connState);
        renderConversations();
    }

    function emptyNode(message){const node=document.createElement('div');node.className='messages-empty';node.textContent=message;return node;}

function describeError(err,fallback){
        if(!err)return fallback;
        if(err.status===undefined||err.status===null)return copy('تعذر الوصول إلى الخادم. تحقق من اتصالك بالإنترنت.','Could not reach the server. Check your internet connection.');
        if(err.status===401)return copy('انتهت صلاحية الجلسة. الرجاء تسجيل الدخول مجدداً.','Your session has expired. Please log in again.');
        if(err.status===403)return copy('لا تملك صلاحية الوصول إلى هذه المحادثة.','You do not have access to this conversation.');
        if(err.status>=500)return copy('حدث خطأ في الخادم. حاول مرة أخرى بعد قليل.','A server error occurred. Please try again shortly.');
        return err.message||fallback;
    }

    function errorNode(err,fallback,onRetry){
        const wrap=document.createElement('div');wrap.className='conversation-error';
        const text=document.createElement('p');text.textContent=describeError(err,fallback);
        const retry=document.createElement('button');retry.type='button';retry.className='btn btn-secondary btn-sm';retry.textContent=copy('إعادة المحاولة','Retry');
        retry.addEventListener('click',onRetry);
        wrap.append(text,retry);
        return wrap;
    }

    function conversationSkeleton(){
        const frag=document.createDocumentFragment();
        for(let i=0;i<5;i++){
            const row=document.createElement('div');row.className='conversation-skeleton';
            const avatar=document.createElement('div');avatar.className='skeleton conversation-skeleton-avatar';
            const lines=document.createElement('div');lines.className='conversation-skeleton-lines';
            const l1=document.createElement('div');l1.className='skeleton';l1.style.width='70%';l1.style.height='11px';
            const l2=document.createElement('div');l2.className='skeleton';l2.style.width='45%';l2.style.height='10px';
            lines.append(l1,l2);
            row.append(avatar,lines);
            frag.appendChild(row);
        }
        return frag;
    }

    function messageSkeleton(){
        const frag=document.createDocumentFragment();
        [false,true,false].forEach(mine=>{
            const row=document.createElement('div');row.className=`message-skeleton${mine?' mine':''}`;
            const bar=document.createElement('div');bar.className='skeleton';
            row.appendChild(bar);
            frag.appendChild(row);
        });
        return frag;
    }

    function renderConversations(){
        const root=byId('conversationList');
        root.textContent='';
        if(!conversations.length){root.appendChild(emptyNode(copy('لا توجد محادثات بعد. ابدأ من ملف طبيب أو زر رسالة جديدة.','No conversations yet. Start from a doctor profile or New message.')));return;}
        conversations.forEach(conversation=>{
            const button=document.createElement('button');
            button.type='button';
            button.className=`conversation-item${selected?.id===conversation.id?' active':''}`;
            const avatar=document.createElement('span');avatar.className='conversation-avatar';
            if(conversation.other_avatar_url){const image=document.createElement('img');image.src=API.assetUrl(conversation.other_avatar_url);image.alt='';avatar.appendChild(image);}
            else avatar.textContent=(conversation.other_display_name||'?').trim().charAt(0).toUpperCase();
            const text=document.createElement('span');text.className='conversation-copy';
            const row=document.createElement('span');row.className='conversation-name-row';
            const name=document.createElement('span');name.className='conversation-name';name.textContent=conversation.other_display_name;
            const role=document.createElement('span');role.className='role-badge';role.textContent=conversation.other_role==='doctor'?copy('طبيب','Doctor'):copy('مريض','Patient');
            row.append(name,role);
            const preview=document.createElement('span');preview.className='conversation-preview';
            preview.textContent=conversation.request_status==='pending'?copy('طلب مراسلة بانتظار الرد','Message request awaiting response'):(conversation.last_message_preview||copy('ابدأ المحادثة','Start the conversation'));
            text.append(row,preview);
            button.append(avatar,text);
            if(Number(conversation.unread_count)>0){const badge=document.createElement('span');badge.className='unread-badge';badge.textContent=Number(conversation.unread_count)>9?'9+':String(conversation.unread_count);button.appendChild(badge);}
            button.addEventListener('click',()=>selectConversation(conversation));
            root.appendChild(button);
        });
    }

    function appendMessage(message,{prepend=false,animate=false}={}){
        if(renderedIds.has(message.id))return;
        renderedIds.add(message.id);
        const history=byId('messageHistory');
        history.querySelector('.messages-empty')?.remove();
        const bubble=document.createElement('article');
        bubble.className=`message-bubble${message.sender_user_id===currentUser.id?' mine':''}`;
        bubble.dataset.messageId=message.id;
        const body=document.createElement('div');body.className='message-body';body.textContent=message.body;
        const time=document.createElement('time');time.className='message-time';time.dateTime=message.created_at;time.textContent=formatTime(message.created_at);
        bubble.append(body,time);
        if(animate)bubble.classList.add('fade-in-item');
        prepend?history.prepend(bubble):history.appendChild(bubble);
        latestCursor=cursorFor(message);
    }

    function showJumpLatest(){byId('jumpLatestBtn')?.classList.remove('hidden');}
    function hideJumpLatest(){byId('jumpLatestBtn')?.classList.add('hidden');}

    async function loadHistory({older=false,missed=false}={}){
        if(!selected)return;
        const history=byId('messageHistory');
        const wasNearBottom=isNearBottom(history);
        const query={limit:50};
        if(older&&nextCursor)query.cursor=nextCursor;
        if(missed&&latestCursor)query.after=latestCursor;
        if(!older&&!missed)history.replaceChildren(messageSkeleton());

        let response;
        try{
            response=await API.messaging.history(selected.id,query);
        }catch(err){
            if(!older&&!missed)history.replaceChildren(errorNode(err,copy('تعذر تحميل الرسائل.','Unable to load messages.'),()=>loadHistory().catch(()=>{})));
            throw err;
        }

        const items=response?.data?.items||[];
        if(!older&&!missed){renderedIds.clear();history.textContent='';}
        if(older)[...items].reverse().forEach(message=>appendMessage(message,{prepend:true}));
        else items.forEach(message=>appendMessage(message,{animate:missed}));
        nextCursor=response?.data?.next_cursor||null;
        if(response?.data?.latest_cursor)latestCursor=response.data.latest_cursor;
        byId('loadOlderBtn').classList.toggle('hidden',!nextCursor);
        if(!items.length&&!older&&!missed)history.appendChild(emptyNode(selected.request_status==='pending'?copy('لا يمكن تبادل الرسائل حتى قبول الطلب.','Messages unlock after the request is accepted.'):copy('لا توجد رسائل بعد. ابدأ بتحية واضحة.','No messages yet. Start with a clear greeting.')));
        if(!older&&(!missed||wasNearBottom)){history.scrollTop=history.scrollHeight;hideJumpLatest();}
        const last=items[items.length-1];
        if(last)try{await API.messaging.markRead(selected.id,last.id);}catch{ }
    }

async function syncSelectedConversation(){
        if(!selected||selected.request_status!=='accepted')return;
        const conversationId=selected.id;
        const history=byId('messageHistory');
        const wasNearBottom=isNearBottom(history);
        const query={limit:50};
        if(latestCursor)query.after=latestCursor;
        let response;
        try{
            response=await API.messaging.history(conversationId,query);
        }catch{
            return;
        }
        if(selected?.id!==conversationId)return;
        const items=response?.data?.items||[];
        if(!items.length)return;
        let appended=false;
        items.forEach(message=>{
            if(renderedIds.has(message.id))return;
            const pendingMatch=message.client_message_id&&findPendingBubble(message.client_message_id);
            if(pendingMatch)reconcileBubble(pendingMatch,message);
            else appendMessage(message,{animate:true});
            appended=true;
        });
        if(!appended)return;
        if(wasNearBottom){history.scrollTop=history.scrollHeight;hideJumpLatest();}
        else showJumpLatest();
        const last=items[items.length-1];
        if(last)try{await API.messaging.markRead(conversationId,last.id);}catch{ }
        await runListSync();
    }

    async function runThreadSync(){
        if(threadSyncInFlight)return;
        threadSyncInFlight=true;
        try{await syncSelectedConversation();}
        finally{threadSyncInFlight=false;}
    }

    async function runListSync(){
        if(listSyncInFlight)return;
        listSyncInFlight=true;
        try{await refreshConversationList();}
        finally{listSyncInFlight=false;}
    }

function scheduleThreadSync(){
        if(threadSyncTimer){clearTimeout(threadSyncTimer);threadSyncTimer=null;}
        if(!selected||selected.request_status!=='accepted')return;
        if(document.visibilityState!=='visible'||!navigator.onLine)return;
        const delay=connState==='online'?30000:8000;
        threadSyncTimer=setTimeout(async()=>{
            threadSyncTimer=null;
            await runThreadSync();
            scheduleThreadSync();
        },delay);
    }

    function scheduleListSync(){
        if(listSyncTimer){clearTimeout(listSyncTimer);listSyncTimer=null;}
        if(document.visibilityState!=='visible'||!navigator.onLine)return;
        listSyncTimer=setTimeout(async()=>{
            listSyncTimer=null;
            await runListSync();
            scheduleListSync();
        },20000);
    }

    function renderRequestState(){
        const banner=byId('messageRequestBanner'),actions=byId('requestActions');
        actions.textContent='';
        const pending=selected?.request_status==='pending';
        banner.classList.toggle('hidden',!pending);
        byId('messageInput').disabled=!selected||pending;
        byId('sendMessageBtn').disabled=!selected||pending;
        if(!pending)return;
        const canRespond=Boolean(selected.can_respond_to_request);
        byId('requestTitle').textContent=canRespond?copy('طلب مراسلة من طبيب معتمد','Message request from an approved doctor'):copy('طلب المراسلة بانتظار رد المريض','Message request awaiting the patient');
        byId('requestHint').textContent=canRespond?copy('قبول الطلب يفتح محادثة نصية فقط ولا يمنح أي صلاحية طبية.','Accepting opens text messaging only and grants no clinical access.'):copy('لن تتمكن من إرسال رسالة حتى يقبل المريض الطلب.','You cannot send until the patient accepts the request.');
        if(canRespond){
            const accept=document.createElement('button');accept.type='button';accept.className='btn btn-primary btn-sm';accept.textContent=copy('قبول','Accept');accept.addEventListener('click',()=>respond('accept'));
            const decline=document.createElement('button');decline.type='button';decline.className='btn btn-ghost btn-sm';decline.textContent=copy('رفض','Decline');decline.addEventListener('click',()=>respond('decline'));
            actions.append(accept,decline);
        }
    }

    async function respond(decision){
        byId('requestActions').querySelectorAll('button').forEach(button=>button.disabled=true);
        try{
            if(decision==='accept'){
                const response=await API.messaging.accept(selected.id);
                selected=response.data;
                await loadConversations(selected.id);
            }else{
                await API.messaging.decline(selected.id);
                selected=null;
                if(threadSyncTimer){clearTimeout(threadSyncTimer);threadSyncTimer=null;}
                document.body.classList.remove('messages-thread-open');
                await loadConversations();
                byId('threadName').textContent=copy('اختر محادثة','Select a conversation');
                byId('threadRole').textContent='';
                byId('messageHistory').replaceChildren(emptyNode(copy('تم رفض طلب المراسلة.','The message request was declined.')));
                renderRequestState();
            }
            window.dispatchEvent(new CustomEvent('notifications:changed'));
        }catch(err){
            Toast.error(describeError(err,copy('تعذر تحديث الطلب.','Unable to update request.')));
            renderRequestState();
        }
    }

async function subscribe(){
        if(!socket?.connected||!selected||selected.request_status!=='accepted')return;
        socket.emit('conversation.subscribe',{conversation_id:selected.id},reply=>{
            if(!reply?.ok)Toast.error(copy('تعذر الانضمام إلى هذه المحادثة المباشرة.','Unable to join this live conversation.'));
        });
    }

    async function selectConversation(conversation){
        if(selected&&socket?.connected)socket.emit('conversation.unsubscribe',{conversation_id:selected.id});

sending=false;
        selected=conversation;
        document.body.classList.add('messages-thread-open');
        byId('threadName').textContent=conversation.other_display_name;
        byId('threadRole').textContent=conversation.other_role==='doctor'?copy('طبيب','Doctor'):copy('مريض','Patient');
        renderRequestState();
        renderConversations();
        hideJumpLatest();
        try{
            await loadHistory();
            await subscribe();
            scheduleThreadSync();
        }catch(err){
            byId('messageHistory').replaceChildren(errorNode(err,copy('تعذر تحميل الرسائل.','Unable to load messages.'),()=>selectConversation(conversation)));
        }
    }

    async function loadConversations(preferredId=null){
        let response;
        try{
            response=await API.messaging.list();
        }catch(err){
            byId('conversationList').replaceChildren(errorNode(err,copy('تعذر تحميل المحادثات.','Unable to load conversations.'),()=>{byId('conversationList').replaceChildren(conversationSkeleton());loadConversations(preferredId).catch(()=>{});}));
            throw err;
        }
        conversations=response?.data?.items||[];
        renderConversations();
        const candidate=conversations.find(conversation=>conversation.id===(preferredId||selected?.id));
        if(candidate)await selectConversation(candidate);
    }

async function refreshConversationList(){
        try{
            const response=await API.messaging.list();
            conversations=response?.data?.items||[];
            renderConversations();
        }catch{ }
    }

    function loadSocketLibrary(){if(window.io)return Promise.resolve();return new Promise((resolve,reject)=>{const script=document.createElement('script');script.src=API.getOrigin()+'/socket.io/socket.io.js';script.onload=resolve;script.onerror=reject;document.head.appendChild(script);});}

    async function connectSocket(){
        try{
            await loadSocketLibrary();
            setConnection('connecting');

socket=window.io(API.getOrigin(),{
                auth:cb=>cb({token:API.getAccessToken()}),
                transports:['websocket','polling'],
                reconnection:true,
                reconnectionAttempts:8,
                reconnectionDelay:800,
                reconnectionDelayMax:8000
            });
            socket.on('connect',async()=>{
                setConnection('online');
                try{await subscribe();}catch{ }

if(selected)await runThreadSync();
                scheduleThreadSync();
            });
            socket.on('disconnect',()=>{if(connState!=='unavailable')setConnection(navigator.onLine?'reconnecting':'offline');scheduleThreadSync();});
            socket.on('connect_error',()=>{if(connState!=='unavailable')setConnection(navigator.onLine?'reconnecting':'offline');scheduleThreadSync();});
            socket.io.on('reconnect_attempt',()=>{if(connState!=='unavailable')setConnection(navigator.onLine?'reconnecting':'offline');scheduleThreadSync();});
            socket.io.on('reconnect_failed',()=>{setConnection('unavailable');scheduleThreadSync();});
            socket.on('message.created',async message=>{
                if(message.conversation_id!==selected?.id)return;
                if(renderedIds.has(message.id))return;
                const history=byId('messageHistory');
                const wasNearBottom=isNearBottom(history);

const pendingMatch=message.client_message_id&&findPendingBubble(message.client_message_id);
                if(pendingMatch)reconcileBubble(pendingMatch,message);
                else appendMessage(message,{animate:true});
                if(message.sender_user_id===currentUser.id||wasNearBottom){history.scrollTop=history.scrollHeight;hideJumpLatest();}
                else showJumpLatest();
                try{await API.messaging.markRead(selected.id,message.id);}catch{ }
                await refreshConversationList();
            });
        }catch{
            setConnection('unavailable');
        }
    }

function pendingBubble(clientId,body){
        const bubble=document.createElement('article');
        bubble.className='message-bubble mine pending fade-in-item';
        bubble.dataset.clientId=clientId;
        const bodyEl=document.createElement('div');bodyEl.className='message-body';bodyEl.textContent=body;
        const meta=document.createElement('div');meta.className='message-meta';
        meta.append(spinnerNode(),statusText(copy('جارٍ الإرسال…','Sending…')));
        bubble.append(bodyEl,meta);
        return bubble;
    }
    function spinnerNode(){const s=document.createElement('span');s.className='spinner spinner-sm';return s;}
    function statusText(text){const s=document.createElement('span');s.className='message-status-text';s.textContent=text;return s;}

function findPendingBubble(clientId){
        return Array.from(byId('messageHistory').querySelectorAll('.message-bubble[data-client-id]'))
            .find(b=>b.dataset.clientId===clientId)||null;
    }

function reconcileBubble(bubble,message){
        if(renderedIds.has(message.id))return;
        renderedIds.add(message.id);
        bubble.dataset.messageId=message.id;
        bubble.className='message-bubble mine';
        bubble.querySelector('.message-body').textContent=message.body;
        const time=document.createElement('time');time.className='message-time';time.dateTime=message.created_at;time.textContent=formatTime(message.created_at);
        bubble.querySelector('.message-meta')?.replaceWith(time);
        latestCursor=cursorFor(message);
    }

    function markBubbleFailed(bubble,clientId,body,input){
        bubble.classList.remove('pending','fade-in-item');
        bubble.classList.add('failed');
        const meta=bubble.querySelector('.message-meta');
        meta.textContent='';
        meta.appendChild(statusText(copy('تعذر الإرسال','Send failed')));
        const retry=document.createElement('button');retry.type='button';retry.className='message-bubble-action';retry.textContent=copy('إعادة المحاولة','Retry');
        retry.addEventListener('click',()=>retrySend(clientId,body,bubble));
        const dismiss=document.createElement('button');dismiss.type='button';dismiss.className='message-bubble-action';dismiss.textContent=copy('حذف','Dismiss');

dismiss.addEventListener('click',()=>{if(!input.value.trim()){input.value=body;autoResize(input);}bubble.remove();input.focus();});
        meta.append(retry,dismiss);
    }

    async function performSend(clientId,body,bubble,input){
        try{
            const response=await API.messaging.send(selected.id,body,clientId);
            const message=response.data;
            if(renderedIds.has(message.id)){

if(bubble.dataset.messageId!==String(message.id))bubble.remove();
            }else{
                reconcileBubble(bubble,message);
            }
            await refreshConversationList();
        }catch(err){
            if(bubble.dataset.messageId){

return;
            }
            markBubbleFailed(bubble,clientId,body,input);
            Toast.error(describeError(err,copy('تعذر إرسال الرسالة.','Unable to send the message.')));
        }
    }

    async function retrySend(clientId,body,bubble){
        bubble.classList.remove('failed');
        bubble.classList.add('pending');
        const meta=document.createElement('div');meta.className='message-meta';
        meta.append(spinnerNode(),statusText(copy('جارٍ إعادة الإرسال…','Retrying…')));
        bubble.querySelector('.message-meta')?.replaceWith(meta);
        await performSend(clientId,body,bubble,byId('messageInput'));
    }

    function autoResize(el){if(!el)return;el.style.height='auto';el.style.height=Math.min(el.scrollHeight,120)+'px';}

    async function send(event){
        event.preventDefault();
        if(sending)return;
        if(!selected||selected.request_status!=='accepted')return;
        const input=byId('messageInput');
        const body=input.value.trim();
        if(!body)return;

        sending=true;
        const button=byId('sendMessageBtn');
        button.classList.add('loading');
        button.disabled=true;

        const clientId=uuid();
        const history=byId('messageHistory');
        history.querySelector('.messages-empty')?.remove();
        const bubble=pendingBubble(clientId,body);
        history.appendChild(bubble);
        history.scrollTop=history.scrollHeight;
        hideJumpLatest();
        input.value='';
        autoResize(input);

        try{
            await performSend(clientId,body,bubble,input);
        }finally{
            sending=false;
            button.classList.remove('loading');
            button.disabled=false;
            input.focus();
        }
    }

    function recipientName(item){
        const primary=isAr()?[item.first_name_ar,item.last_name_ar]:[item.first_name_en,item.last_name_en];
        const fallback=isAr()?[item.first_name_en,item.last_name_en]:[item.first_name_ar,item.last_name_ar];
        return primary.filter(Boolean).join(' ').trim()||fallback.filter(Boolean).join(' ').trim()||copy('مستخدم MedOrbit','MedOrbit user');
    }

    function renderRecipients(recipients){
        const root=byId('recipientResults');
        root.textContent='';
        if(!recipients.length){root.appendChild(emptyNode(copy('لا توجد نتائج مؤهلة.','No eligible results.')));return;}
        recipients.forEach(recipient=>{
            const button=document.createElement('button');button.type='button';button.className='recipient-card';
            const avatar=document.createElement('span');avatar.className='conversation-avatar';
            if(recipient.profile_image_url||recipient.avatar_url){const image=document.createElement('img');image.src=API.assetUrl(recipient.profile_image_url||recipient.avatar_url);image.alt='';avatar.appendChild(image);}
            else avatar.textContent=recipientName(recipient).charAt(0).toUpperCase();
            const detail=document.createElement('span');
            const name=document.createElement('strong');name.textContent=recipientName(recipient);
            const meta=document.createElement('small');meta.textContent=[recipient.kind==='doctor'?copy('طبيب معتمد','Verified doctor'):copy('مريض متاح للمراسلة','Patient open to messages'),isAr()?(recipient.specialty_ar||recipient.specialty_en):(recipient.specialty_en||recipient.specialty_ar),recipient.city].filter(Boolean).join(' · ');
            detail.append(name,meta);
            const arrow=document.createElement('i');arrow.className='fas fa-chevron-left';
            button.append(avatar,detail,arrow);
            button.addEventListener('click',()=>startConversation(recipient.id));
            root.appendChild(button);
        });
    }

    async function searchRecipients(){
        const root=byId('recipientResults');
        root.replaceChildren(emptyNode(copy('جارٍ البحث…','Searching…')));
        try{
            const search=byId('recipientSearchInput').value.trim();
            const requests=[API.doctors.list({search,limit:20})];
            if(currentUser.role==='doctor')requests.push(API.patientProfiles.discover({search,limit:20}));
            const responses=await Promise.all(requests);
            const doctors=(responses[0]?.data?.doctors||[]).filter(doctor=>doctor.id!==ownDoctorId).map(doctor=>({...doctor,kind:'doctor'}));
            const patients=(responses[1]?.data?.items||[]).map(patient=>({...patient,kind:'patient'}));
            renderRecipients([...patients,...doctors]);
        }catch(err){
            root.replaceChildren(emptyNode(describeError(err,copy('تعذر البحث.','Search failed.'))));
        }
    }

    async function startConversation(counterpartId){
        byId('recipientResults').querySelectorAll('button').forEach(button=>button.disabled=true);
        try{
            const response=await API.messaging.start(counterpartId);
            byId('recipientPicker').classList.add('hidden');
            await loadConversations(response.data.id);
            if(response.data.request_status==='pending')Toast.success(copy('تم إرسال طلب مراسلة آمن.','A safe message request was sent.'));
        }catch(err){
            Toast.error(describeError(err,copy('تعذر بدء المحادثة.','Unable to start conversation.')));
            await searchRecipients();
        }
    }

    function openPicker(){byId('recipientPicker').classList.remove('hidden');byId('recipientSearchInput').focus();searchRecipients();}

async function bootstrap(){
        try{
            const state=await AuthGate.verifySession();
            if(state!=='valid')return;
            currentUser=AuthGate.getVerifiedUser();
            if(!['patient','doctor'].includes(currentUser?.role)){location.href='dashboard.html';return;}
            if(currentUser.role==='doctor')ownDoctorId=(await API.doctors.myProfile()).data.id;
            const counterpart=new URLSearchParams(location.search).get('counterpart');
            let preferred=new URLSearchParams(location.search).get('id');
            if(counterpart){
                const started=await API.messaging.start(counterpart);
                preferred=started?.data?.id;
                window.history.replaceState({},'',`direct-messages.html?id=${encodeURIComponent(preferred)}`);
            }
            byId('conversationList').replaceChildren(conversationSkeleton());
            await loadConversations(preferred);
            await connectSocket();
            scheduleListSync();
        }catch(err){
            byId('conversationList').replaceChildren(errorNode(err,copy('تعذر تحميل المحادثات.','Unable to load conversations.'),()=>{byId('conversationList').replaceChildren(conversationSkeleton());bootstrap();}));
        }
    }

    async function init(){
        if(!API.requireAuth())return;
        setConnection('idle');
        localize();
        window.addEventListener('languageChanged',localize);

window.addEventListener('online',()=>{
            if(socket&&!socket.connected&&connState!=='connecting'){setConnection('connecting');socket.io.reconnection(true);socket.connect();}
            if(selected)runThreadSync();
            runListSync();
            scheduleThreadSync();
            scheduleListSync();
        });
        window.addEventListener('offline',()=>{
            setConnection('offline');
            if(threadSyncTimer){clearTimeout(threadSyncTimer);threadSyncTimer=null;}
            if(listSyncTimer){clearTimeout(listSyncTimer);listSyncTimer=null;}
        });

document.addEventListener('visibilitychange',()=>{
            if(document.visibilityState==='visible'){
                if(navigator.onLine){
                    if(selected)runThreadSync();
                    runListSync();
                }
                scheduleThreadSync();
                scheduleListSync();
            }else{
                if(threadSyncTimer){clearTimeout(threadSyncTimer);threadSyncTimer=null;}
                if(listSyncTimer){clearTimeout(listSyncTimer);listSyncTimer=null;}
            }
        });
        byId('jumpLatestBtn')?.addEventListener('click',()=>{const history=byId('messageHistory');history.scrollTop=history.scrollHeight;hideJumpLatest();});
        byId('messageHistory')?.addEventListener('scroll',Dom.throttle(()=>{if(isNearBottom(byId('messageHistory')))hideJumpLatest();},200));
        byId('messageInput')?.addEventListener('input',event=>autoResize(event.target));
        byId('messageInput')?.addEventListener('keydown',event=>{
            if(event.key==='Enter'&&!event.shiftKey){
                event.preventDefault();
                const form=byId('messageForm');
                form.requestSubmit?form.requestSubmit():send(new Event('submit',{cancelable:true}));
            }
        });
        byId('messageForm').addEventListener('submit',send);
        byId('loadOlderBtn').addEventListener('click',()=>loadHistory({older:true}).catch(err=>Toast.error(describeError(err,copy('تعذر تحميل الرسائل الأقدم.','Unable to load older messages.')))));
        byId('newConversationBtn').addEventListener('click',openPicker);
        byId('closeRecipientPicker').addEventListener('click',()=>byId('recipientPicker').classList.add('hidden'));
        byId('recipientSearchBtn').addEventListener('click',searchRecipients);
        byId('recipientSearchInput').addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();searchRecipients();}});
        byId('threadBackBtn').addEventListener('click',()=>document.body.classList.remove('messages-thread-open'));
        await bootstrap();
    }

    return{init};
})();
