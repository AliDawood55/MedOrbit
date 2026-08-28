const ContactPage=(()=>{
    const byId=id=>document.getElementById(id),isAr=()=>I18n.getLang()==='ar';
    const LIMITS={name:120,email:320,subject:160,message:4000};
    let submitting=false;

    function setText(id,ar,en){byId(id).textContent=isAr()?ar:en;}
    function localize(){
        const copy={
            contactTitle:['تواصل معنا','Contact Us'],
            contactSubtitle:['أرسل رسالة دعم آمنة إلى فريق إدارة MedOrbit.','Send a secure support message to the MedOrbit administration team.'],
            contactNameLabel:['الاسم','Name'],
            contactEmailLabel:['البريد الإلكتروني','Email'],
            contactSubjectLabel:['الموضوع','Subject'],
            contactMessageLabel:['الرسالة','Message'],
            contactMessageHelp:['لا تدرج كلمات مرور أو رموز وصول أو تفاصيل طبية غير ضرورية.','Do not include passwords, tokens, or unnecessary medical details.'],
            sendContactLabel:['إرسال الرسالة','Send message'],
            contactHelpTitle:['كيف يمكننا المساعدة','How we can help'],
            contactSafeTitle:['معالجة آمنة','Handled securely'],
            contactSafeCopy:['يمكن للمسؤولين المخولين فقط فتح رسائل التواصل.','Only authorized administrators can open contact messages.'],
            contactNotifyTitle:['توجيه سريع','Routed promptly'],
            contactNotifyCopy:['يتلقى المسؤولون النشطون إشعاراً آمناً من دون نص رسالتك.','Active administrators receive a safe notification without your message body.']
        };
        Object.entries(copy).forEach(([id,v])=>setText(id,v[0],v[1]));
        updateCharCount();
        [['contactName','contactNameError'],['contactEmail','contactEmailError'],['contactSubject','contactSubjectError'],['contactMessage','contactMessageError']]
            .forEach(([fieldId,errorId])=>{if(!byId(errorId).classList.contains('hidden'))clearFieldError(fieldId,errorId,false);});
    }

    function feedback(message,type){
        const node=byId('contactFeedback');
        node.textContent='';
        const icon=document.createElement('i');
        icon.className=`fas ${type==='success'?'fa-circle-check':'fa-triangle-exclamation'}`;
        const text=document.createElement('span');
        text.textContent=message;
        node.append(icon,text);
        node.className=`page-feedback ${type} fade-in-item`;
    }
    function hideFeedback(){const node=byId('contactFeedback');node.className='page-feedback hidden';node.textContent='';}

    function updateCharCount(){
        const count=byId('contactMessage').value.length;
        const label=byId('contactMessageCount');
        label.textContent=`${count} / ${LIMITS.message}`;
        label.classList.toggle('warn',count>LIMITS.message*0.9);
    }

    function setFieldError(fieldId,errorId,message){
        byId(fieldId).closest('.form-field').classList.add('invalid');
        byId(fieldId).setAttribute('aria-invalid','true');
        const errorNode=byId(errorId);
        errorNode.textContent=message;
        errorNode.classList.remove('hidden');
    }
    function clearFieldError(fieldId,errorId,removeInvalid=true){
        if(removeInvalid){
            byId(fieldId).closest('.form-field').classList.remove('invalid');
            byId(fieldId).removeAttribute('aria-invalid');
        }
        const errorNode=byId(errorId);
        errorNode.textContent='';
        errorNode.classList.add('hidden');
    }

function validate(){
        let firstInvalidId=null;
        const fail=(fieldId,errorId,message)=>{setFieldError(fieldId,errorId,message);if(!firstInvalidId)firstInvalidId=fieldId;};

        const guest=!API.isAuthenticated();
        if(guest){
            const name=byId('contactName').value.trim();
            if(!name)fail('contactName','contactNameError',isAr()?'الاسم مطلوب.':'Name is required.');
            else if(name.length>LIMITS.name)fail('contactName','contactNameError',isAr()?`الاسم يجب ألا يتجاوز ${LIMITS.name} حرفاً.`:`Name must not exceed ${LIMITS.name} characters.`);

            const emailValue=byId('contactEmail').value.trim();
            if(!emailValue)fail('contactEmail','contactEmailError',isAr()?'البريد الإلكتروني مطلوب.':'Email is required.');
            else if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailValue))fail('contactEmail','contactEmailError',isAr()?'أدخل بريداً إلكترونياً صحيحاً.':'Enter a valid email address.');
        }

        const subject=byId('contactSubject').value.trim();
        if(!subject)fail('contactSubject','contactSubjectError',isAr()?'الموضوع مطلوب.':'Subject is required.');
        else if(subject.length>LIMITS.subject)fail('contactSubject','contactSubjectError',isAr()?`الموضوع يجب ألا يتجاوز ${LIMITS.subject} حرفاً.`:`Subject must not exceed ${LIMITS.subject} characters.`);

        const message=byId('contactMessage').value.trim();
        if(!message)fail('contactMessage','contactMessageError',isAr()?'الرسالة مطلوبة.':'Message is required.');
        else if(message.length>LIMITS.message)fail('contactMessage','contactMessageError',isAr()?`الرسالة يجب ألا تتجاوز ${LIMITS.message} حرفاً.`:`Message must not exceed ${LIMITS.message} characters.`);

        return firstInvalidId;
    }

    function describeError(err){
        if(err?.status===undefined||err?.status===null){
            return isAr()?'تعذر الوصول إلى الخادم. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.':'Could not reach the server. Check your connection and try again.';
        }
        if(err.status===429)return err.message;
        if(err.status>=500)return isAr()?'حدث خطأ في الخادم. حاول مرة أخرى بعد قليل.':'A server error occurred. Please try again shortly.';
        return err.message||(isAr()?'تعذر إرسال الرسالة.':'Unable to send message.');
    }

    async function submit(event){
        event.preventDefault();
        if(submitting)return;
        hideFeedback();
        ['contactName:contactNameError','contactEmail:contactEmailError','contactSubject:contactSubjectError','contactMessage:contactMessageError']
            .forEach(pair=>clearFieldError(...pair.split(':')));

        const firstInvalidId=validate();
        if(firstInvalidId){
            byId(firstInvalidId).focus();
            feedback(isAr()?'يرجى تصحيح الحقول المظللة أدناه.':'Please fix the highlighted fields below.','error');
            return;
        }

        submitting=true;
        const button=byId('sendContact');
        button.classList.add('loading');
        button.disabled=true;
        try{
            const body={subject:byId('contactSubject').value.trim(),message:byId('contactMessage').value.trim()};
            if(!API.isAuthenticated()){
                body.name=byId('contactName').value.trim();
                body.email=byId('contactEmail').value.trim();
            }
            await API.contact.submit(body);
            byId('contactForm').reset();
            byId('guestIdentityFields').classList.toggle('hidden',API.isAuthenticated());
            updateCharCount();
            feedback(isAr()?'وصلت رسالتك إلى فريق الإدارة.':'Your message reached the administration team.','success');
        }catch(err){
            feedback(describeError(err),'error');
        }finally{
            submitting=false;
            button.classList.remove('loading');
            button.disabled=false;
        }
    }

    function init(){
        localize();
        byId('guestIdentityFields').classList.toggle('hidden',API.isAuthenticated());
        window.addEventListener('languageChanged',localize);
        byId('contactForm').addEventListener('submit',submit);
        byId('contactMessage').addEventListener('input',updateCharCount);
        [['contactName','contactNameError'],['contactEmail','contactEmailError'],['contactSubject','contactSubjectError'],['contactMessage','contactMessageError']]
            .forEach(([fieldId,errorId])=>byId(fieldId).addEventListener('input',()=>clearFieldError(fieldId,errorId)));
        if(typeof Motion!=='undefined')Motion.staggerIn(document.querySelector('.experience-grid'),null,{stepMs:60,maxDelayMs:120});
    }

    return{init};
})();
