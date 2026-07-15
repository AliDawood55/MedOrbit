import os
import json
import requests
from typing import Optional

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
MODEL_NAME = os.environ.get("OLLAMA_MODEL", "qwen2:7b")


def generate_response(message: str, context: str, lang: str = "ar", entities: Optional[dict] = None) -> str:
    """
    Generate a response using the LLM with structured prompts.
    
    The prompt instructs the LLM to:
    1. Use the provided context (RAG data) to inform the response
    2. Never provide a final medical diagnosis
    3. Include medical disclaimers
    4. Suggest visiting a doctor when appropriate
    5. Be concise and helpful
    6. Respond in the correct language (Arabic or English)
    """
    
    # Parse the context if it's JSON
    context_data = {}
    try:
        context_data = json.loads(context) if isinstance(context, str) else context
    except (json.JSONDecodeError, TypeError):
        context_data = {"raw": str(context)}

    # Build the appropriate system prompt based on context type
    if lang == "ar":
        system_prompt = _build_arabic_prompt(context_data)
    else:
        system_prompt = _build_english_prompt(context_data)

    # Build the full prompt
    prompt = f"""{system_prompt}

---
User question:
{message}

Available context:
{json.dumps(context_data, ensure_ascii=False, indent=2)}

---
Instructions for response:
- Answer in {"Arabic" if lang == "ar" else "English"}
- Be concise and helpful
- Use the context above if relevant
- If user asked about nearby places, tell them the backend found results
- Include a medical disclaimer when discussing health issues
- Never provide a definitive diagnosis
- Format the response in clear paragraphs with emoji where appropriate
"""

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": MODEL_NAME,
                "prompt": prompt,
                "stream": False
            },
            timeout=60
        )

        data = response.json()
        reply = data.get("response", "").strip()

        # Fallback if empty
        if not reply:
            return _get_fallback_reply(lang)

        return reply

    except requests.exceptions.Timeout:
        return _get_timeout_reply(lang)
    except requests.exceptions.ConnectionError:
        return _get_unavailable_reply(lang)
    except Exception:
        return _get_error_reply(lang)


def _build_arabic_prompt(context: dict) -> str:
    """Build Arabic system prompt based on context type."""
    context_type = context.get("type", "general_medical")
    
    base_prompt = """أنت مساعد طبي ذكي لمنصة MedOrbit في نابلس، فلسطين.

القواعد الأساسية (يجب الالتزام بها دائماً):
1. لا تعطي تشخيصاً طبياً نهائياً أبداً
2. قدم معلومات ونصائح عامة فقط
3. إذا كانت الحالة تبدو طارئة، اطلب التوجه فوراً إلى الطوارئ
4. استخدم الرموز التعبيرية المناسبة (✅ 🩺 💊 🏥 📍 🚑)
5. كن مختصراً ومفيداً في ردودك
6. لا تذكر أنك ذكاء اصطناعي أو نموذج لغوي
7. أجب بالعربية الفصحى المبسطة"""

    if context_type == "place_search":
        facility = context.get("search_parameters", {}).get("facility_type", "طبية")
        return base_prompt + f"""
        
سياق البحث: المستخدم يبحث عن {facility} قريبة.
- تم العثور على نتائج في قاعدة البيانات
- اعرض المعلومات بشكل مرتب
- اذكر المسافة والتقييم إن وجد
- قل: "يمكنك الضغط على أي مكان لرسم المسار على الخريطة"
- شجع المستخدم على السؤال عن تفاصيل أكثر"""

    if context_type == "doctor_search":
        specialty = context.get("search_parameters", {}).get("specialty", "طبيب")
        return base_prompt + f"""
        
سياق البحث: المستخدم يبحث عن {specialty}.
- تم العثور على أطباء في هذا التخصص
- قدم معلومات عامة عن التخصص
- اذكر أن المنصة تتيح حجز المواعيد
- اسأل إن كان يريد تفاصيل أكثر عن طبيب معين"""

    if context_type == "symptom_analysis":
        symptoms = context.get("entities_found", {}).get("symptoms", [])
        return base_prompt + f"""
        
سياق الاستشارة: المستخدم يذكر أعراضاً ({', '.join(symptoms) if symptoms else 'أعراض'}).
- استمع جيداً للأعراض
- قدم معلومات عامة عن الحالة
- اسأل عن تفاصيل إضافية: منذ متى؟ الشدة؟ أعراض أخرى؟
- اقترح التخصص الطبي المناسب
- أضف تحذيراً طبياً: "هذه المعلومات للاسترشاد فقط وليست تشخيصاً" 
- إذا كانت الأعراض خطيرة، انصح بزيارة الطوارئ فوراً"""

    if context_type == "medication_info":
        return base_prompt + """
        
سياق الدواء: المستخدم يسأل عن معلومات دوائية.
- قدم معلومات عامة فقط عن الدواء
- لا توصي بجرعات محددة
- أضف: "يرجى استشارة الطبيب أو الصيدلي قبل تناول أي دواء"
- اذكر أن المعلومات من قاعدة بيانات المنصة"""

    if context_type == "navigation":
        return base_prompt + """
        
سياق التنقل: المستخدم يريد الاتجاهات.
- أرشد المستخدم إلى استخدام الخريطة
- قل: "اختر الوجهة على الخريطة لعرض المسار"
- اسأل إن كان يريد المشي أو بالسيارة"""

    return base_prompt + """
    
- إذا كان السؤال عاماً، قدم إجابة مفيدة
- اسأل توضيحياً إذا احتجت"""
    


def _build_english_prompt(context: dict) -> str:
    """Build English system prompt based on context type."""
    context_type = context.get("type", "general_medical")
    
    base_prompt = """You are a smart medical assistant for MedOrbit platform in Nablus, Palestine.

Core rules (must always follow):
1. Never provide a final medical diagnosis
2. Provide general information and advice only
3. If the situation seems urgent, tell the user to go to emergency immediately
4. Use appropriate emojis (✅ 🩺 💊 🏥 📍 🚑)
5. Be concise and helpful
6. Do not mention that you are an AI or language model
7. Answer in clear, simple English"""

    if context_type == "place_search":
        facility = context.get("search_parameters", {}).get("facility_type", "medical")
        return base_prompt + f"""
        
Search context: User is looking for nearby {facility}.
- Results were found in the database
- Present information in an organized way
- Mention distance and rating if available
- Say: "You can click on any location to draw the route on the map"
- Encourage the user to ask for more details"""

    if context_type == "doctor_search":
        specialty = context.get("search_parameters", {}).get("specialty", "doctor")
        return base_prompt + f"""
        
Search context: User is looking for a {specialty}.
- Doctor information was found
- Provide general info about this specialty
- Mention the platform allows appointment booking
- Ask if they want details about a specific doctor"""

    if context_type == "symptom_analysis":
        return base_prompt + """
        
Consultation context: User is describing symptoms.
- Listen carefully to the symptoms
- Provide general information
- Ask follow-up questions: duration? severity? other symptoms?
- Suggest the appropriate medical specialty
- Add a medical disclaimer: "This information is for guidance only"
- If symptoms seem severe, advise emergency care"""

    if context_type == "medication_info":
        return base_prompt + """
        
Medication context: User is asking about medication.
- Provide general information only
- Do not recommend specific doses
- Add: "Please consult your doctor or pharmacist before taking any medication"
- Mention the information comes from the platform's database"""

    if context_type == "navigation":
        return base_prompt + """
        
Navigation context: User needs directions.
- Guide the user to use the map
- Say: "Select a destination on the map to see the route"
- Ask if they prefer walking or driving"""

    return base_prompt + """
    
- If the question is general, provide a helpful answer
- Ask clarifying questions if needed"""


def _get_fallback_reply(lang: str) -> str:
    return "شكراً لاستفسارك. كيف يمكنني مساعدتك أكثر؟" if lang == "ar" else "Thank you for your inquiry. How can I help you further?"


def _get_timeout_reply(lang: str) -> str:
    return "الخدمة تستغرق وقتاً طويلاً. يرجى المحاولة مرة أخرى." if lang == "ar" else "The service is taking too long. Please try again."


def _get_unavailable_reply(lang: str) -> str:
    return "خدمة المساعد غير متاحة حالياً. يرجى المحاولة لاحقاً." if lang == "ar" else "AI service is not available right now. Please try again later."


def _get_error_reply(lang: str) -> str:
    return "حدث خطأ في المعالجة. يرجى المحاولة مرة أخرى." if lang == "ar" else "An error occurred. Please try again."