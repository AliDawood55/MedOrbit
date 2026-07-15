const db = require('../../config/database');

const normalizeText = (value = '') => String(value)
  .toLowerCase()
  .replace(/[أإآ]/g, 'ا')
  .replace(/ى/g, 'ي')
  .replace(/ة/g, 'ه')
  .replace(/\s+/g, ' ')
  .trim();

const SYMPTOM_SPECIALTY_MAP = {
  headache: 'Neurology',
  'chest pain': 'Cardiology',
  'stomach pain': 'Gastroenterology',
  cough: 'Pulmonology',
  fever: 'General Practice'
};

const MEDICATION_ALIASES = {
  panadol: ['Panadol', 'Paracetamol', 'Acetaminophen'],
  paracetamol: ['Paracetamol', 'Acetaminophen', 'Panadol'],
  acetaminophen: ['Acetaminophen', 'Paracetamol', 'Panadol'],
  ibuprofen: ['Ibuprofen', 'Advil'],
  advil: ['Advil', 'Ibuprofen']
};

const EMERGENCY_KEYWORDS = {
  en: ['severe chest pain', 'difficulty breathing', 'unconscious', 'stroke symptoms'],
  ar: ['الم صدر شديد', 'صعوبه تنفس', 'فقدان الوعي', 'اعراض جلطه']
};

const SYMPTOM_LABELS = {
  headache: { en: 'headache', ar: 'الصداع' },
  'صداع': { en: 'headache', ar: 'الصداع' },
  fever: { en: 'fever', ar: 'الحرارة' },
  cough: { en: 'cough', ar: 'الكحة' },
  'chest pain': { en: 'chest pain', ar: 'ألم الصدر' },
  'stomach pain': { en: 'stomach pain', ar: 'ألم المعدة' }
};

const cloneEntities = (entities) => ({
  ...entities,
  symptoms: [...(entities.symptoms || [])],
  specialties: [...(entities.specialties || [])],
  medications: [...(entities.medications || [])],
  diseases: [...(entities.diseases || [])],
  locations: [...(entities.locations || [])],
  associatedSymptoms: [...(entities.associatedSymptoms || [])],
  doctorNames: [...(entities.doctorNames || [])],
  dates: [...(entities.dates || [])],
  times: [...(entities.times || [])],
  raw: [...(entities.raw || [])]
});

const appendUnique = (items, value) => {
  if (!value) return;
  const exists = items.some((item) => String(item).toLowerCase() === String(value).toLowerCase());
  if (!exists) items.push(value);
};

const getLanguage = (language, entities, memory) => {
  if (language === 'ar' || language === 'en') return language;
  if (entities.language === 'arabic') return 'ar';
  if (entities.language === 'english') return 'en';
  if (memory?.entities?.language === 'arabic') return 'ar';
  if (memory?.entities?.language === 'english') return 'en';
  return 'en';
};

const hasEmergency = (message, entities, language) => {
  if (entities.emergency) return true;

  const normalized = normalizeText(message);
  const phrases = language === 'ar' ? EMERGENCY_KEYWORDS.ar : EMERGENCY_KEYWORDS.en;
  return phrases.some((phrase) => normalized.includes(normalizeText(phrase)));
};

const emergencyReply = (language) => {
  if (language === 'ar') {
    return 'قد تكون هذه أعراض طارئة. يرجى طلب عناية طبية عاجلة أو الاتصال بالإسعاف فوراً. لا أستطيع تأكيد التشخيص عبر المحادثة.';
  }

  return 'These may be emergency symptoms. Please seek urgent medical attention or call emergency services now. I cannot confirm a diagnosis in chat.';
};

const symptomLabel = (symptom, language) => {
  const key = String(symptom || '').toLowerCase();
  return SYMPTOM_LABELS[key]?.[language] || symptom || (language === 'ar' ? 'الأعراض' : 'the symptom');
};

const buildSymptomQuestion = (entities, language) => {
  const symptoms = entities.symptoms || [];
  const primarySymptom = symptoms.includes('headache') ? 'headache' : entities.symptom || symptoms[0];
  const uniqueClinicalSymptoms = new Set(symptoms.map((symptom) => (symptom === 'صداع' ? 'headache' : symptom)));
  const label = symptomLabel(primarySymptom, language);
  const missing = [];

  if (!entities.duration) missing.push('duration');
  if (!entities.severity) missing.push('severity');
  if (!entities.locations?.length) missing.push('location');
  if (!entities.associatedSymptoms?.length && uniqueClinicalSymptoms.size < 2) missing.push('associatedSymptoms');

  if (language === 'ar') {
    if (primarySymptom === 'headache') {
      return {
        missing,
        reply: 'منذ متى بدأ الصداع؟ وهل يوجد حرارة أو دوخة؟'
      };
    }

    if (primarySymptom === 'chest pain') {
      return {
        missing,
        reply: 'ما شدة ألم الصدر؟ ومتى بدأ؟ وهل يوجد صعوبة في التنفس؟'
      };
    }

    if (missing.includes('duration')) {
      return {
        missing,
        reply: `منذ متى بدأ ${label}؟ وهل توجد أعراض أخرى؟`
      };
    }

    if (missing.includes('severity')) {
      return {
        missing,
        reply: `ما شدة ${label}: خفيف، متوسط، أم شديد؟`
      };
    }

    return {
      missing,
      reply: 'شكراً. بناءً على المعلومات المتاحة، يمكنني مساعدتك في اختيار التخصص المناسب أو العثور على طبيب.'
    };
  }

  if (primarySymptom === 'chest pain') {
    return {
      missing,
      reply: 'How severe is the pain? When did it start?'
    };
  }

  if (missing.includes('duration') && missing.includes('associatedSymptoms')) {
    return {
      missing,
      reply: `When did the ${label} start, and do you also have fever, dizziness, cough, or other symptoms?`
    };
  }

  if (missing.includes('severity')) {
    return {
      missing,
      reply: `How severe is the ${label}: mild, moderate, or severe?`
    };
  }

  if (missing.includes('duration')) {
    return {
      missing,
      reply: `When did the ${label} start?`
    };
  }

  return {
    missing,
    reply: 'Thanks. Based on what you shared, I can help prepare a doctor recommendation or explain what information to share with a clinician.'
  };
};

const findSpecialty = async (specialtyName) => {
  if (!specialtyName) return null;

  const result = await db.query(
    `SELECT id, name_ar, name_en, description_ar, description_en
     FROM medorbit.specialties
     WHERE is_active = true AND name_en ILIKE $1
     LIMIT 1`,
    [specialtyName]
  );

  return result.rows[0] || null;
};

const findMedication = async (medicationName) => {
  if (!medicationName) return null;
  const lookupNames = MEDICATION_ALIASES[String(medicationName).toLowerCase()] || [medicationName];

  const result = await db.query(
    `SELECT id, name_ar, name_en, generic_name, drug_class, active_ingredients, contraindications, side_effects
     FROM medorbit.medications
     WHERE is_active = true
       AND (
         name_en = ANY($1::text[])
         OR generic_name = ANY($1::text[])
         OR brand_names && $1::text[]
       )
     LIMIT 1`,
    [lookupNames]
  );

  return result.rows[0] || null;
};

const applyDoctorPreparation = async (entities, language) => {
  const prepared = cloneEntities(entities);
  const symptom = prepared.symptom || prepared.symptoms?.[0];
  const mappedSpecialty = prepared.specialty || SYMPTOM_SPECIALTY_MAP[String(symptom || '').toLowerCase()];

  if (mappedSpecialty) {
    appendUnique(prepared.specialties, mappedSpecialty);
    prepared.specialty = prepared.specialties[0] || mappedSpecialty;
  }

  const specialty = await findSpecialty(prepared.specialty);
  const specialtyName = specialty?.name_en || prepared.specialty;
  const reply = language === 'ar'
    ? `التخصص المناسب غالباً هو ${specialtyName || 'طبيب عام'}. يمكنني مساعدتك في البحث عن طبيب مناسب.`
    : `The likely specialty is ${specialtyName || 'General Practice'}. I can help prepare a doctor search for you.`;

  return {
    entities: prepared,
    reply,
    workflow: {
      name: 'doctor_recommendation',
      state: 'prepared',
      recommendedSpecialty: specialty || (specialtyName ? { name_en: specialtyName } : null)
    }
  };
};

const applyMedicationPreparation = async (entities, language) => {
  const medication = entities.medication || entities.medications?.[0];
  const medicationInfo = await findMedication(medication);

  if (language === 'ar') {
    const name = medicationInfo?.name_en || medication || 'هذا الدواء';
    return {
      reply: `يمكنني مشاركة معلومات عامة عن ${name}، لكن هذا لا يغني عن استشارة الطبيب أو الصيدلي، خاصة إذا لديك حساسية أو أمراض مزمنة أو أدوية أخرى.`,
      workflow: {
        name: 'medication_information',
        state: medicationInfo ? 'matched' : 'needs_review',
        medication: medicationInfo
      }
    };
  }

  const name = medicationInfo?.name_en || medication || 'this medication';
  const details = medicationInfo?.generic_name ? ` Generic name: ${medicationInfo.generic_name}.` : '';
  return {
    reply: `I can share general information about ${name}.${details} This does not replace advice from a doctor or pharmacist, especially if you have allergies, chronic conditions, or other medications.`,
    workflow: {
      name: 'medication_information',
      state: medicationInfo ? 'matched' : 'needs_review',
      medication: medicationInfo
    }
  };
};

const applyWorkflow = async ({ intent, confidence, entities, memory, message, language }) => {
  const resolvedLanguage = getLanguage(language, entities, memory);
  const previousTopic = memory?.topic;
  const previousIntent = memory?.lastIntent;
  let activeIntent = intent;
  let preparedEntities = cloneEntities(entities);

  if (
    activeIntent === 'unknown'
    && (previousTopic === 'symptom' || previousIntent === 'symptom_analysis')
    && (preparedEntities.duration || preparedEntities.severity || preparedEntities.age || preparedEntities.gender)
  ) {
    activeIntent = 'symptom_analysis';
  }

  if (hasEmergency(message, preparedEntities, resolvedLanguage)) {
    preparedEntities.emergency = true;
    return {
      intent: activeIntent === 'unknown' ? 'symptom_analysis' : activeIntent,
      confidence: Math.max(confidence, 0.95),
      entities: preparedEntities,
      reply: emergencyReply(resolvedLanguage),
      workflow: {
        name: 'medical_safety',
        state: 'emergency_detected',
        requiresUrgentCare: true
      }
    };
  }

  if (activeIntent === 'find_doctor') {
    const doctorPreparation = await applyDoctorPreparation(preparedEntities, resolvedLanguage);
    return {
      intent: activeIntent,
      confidence,
      entities: doctorPreparation.entities,
      reply: doctorPreparation.reply,
      workflow: doctorPreparation.workflow
    };
  }

  if (activeIntent === 'medication_info') {
    const medicationPreparation = await applyMedicationPreparation(preparedEntities, resolvedLanguage);
    return {
      intent: activeIntent,
      confidence,
      entities: preparedEntities,
      reply: medicationPreparation.reply,
      workflow: medicationPreparation.workflow
    };
  }

  if (activeIntent === 'symptom_analysis') {
    const question = buildSymptomQuestion(preparedEntities, resolvedLanguage);
    return {
      intent: activeIntent,
      confidence,
      entities: preparedEntities,
      reply: question.reply,
      workflow: {
        name: 'symptom_analysis',
        state: question.missing.length > 0 ? 'collecting_information' : 'ready_for_recommendation',
        missing: question.missing
      }
    };
  }

  if (activeIntent === 'platform_support') {
    return {
      intent: activeIntent,
      confidence,
      entities: preparedEntities,
      reply: resolvedLanguage === 'ar'
        ? 'يمكنني مساعدتك في استخدام المنصة، مثل الحجز أو الحساب أو رفع التقارير.'
        : 'I can help with platform tasks such as appointments, account settings, or uploading reports.',
      workflow: {
        name: 'platform_support',
        state: 'ready'
      }
    };
  }

  if (activeIntent === 'small_talk') {
    return {
      intent: activeIntent,
      confidence,
      entities: preparedEntities,
      reply: resolvedLanguage === 'ar' ? 'أهلاً! كيف يمكنني مساعدتك صحياً اليوم؟' : 'Hello! How can I help with your health needs today?',
      workflow: {
        name: 'small_talk',
        state: 'ready'
      }
    };
  }

  return {
    intent: activeIntent,
    confidence,
    entities: preparedEntities,
    reply: null,
    workflow: {
      name: 'unknown',
      state: 'needs_clarification'
    }
  };
};

module.exports = {
  applyWorkflow
};
