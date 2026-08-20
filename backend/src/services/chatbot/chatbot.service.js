const db = require('../../config/database');

const aiClient = require('./ai-client.service');
const entityService = require('./entity.service');
const memoryService = require('./memory.service');
const ragService = require('./rag.service');

const chatbotRepository = require('../../repositories/chatbot.repository');
const conversationRepository = require('../../repositories/conversation.repository');
const clinicRepository = require('../../repositories/clinic.repository');

/**
 * ChatbotService — Core orchestrator
 * 
 * Handles message processing with:
 * - Authenticated or anonymous user support
 * - Conversation creation/continuation
 * - AI service integration
 * - Intent-based data retrieval (RAG)
 * - Conversation memory management
 * - Structured response formatting
 */
class ChatbotService {

    /**
     * Process a user message and return a structured response.
     * Supports both authenticated users (userId) and anonymous sessions.
     */
    async processMessage({ message, conversationId, userId, latitude, longitude }) {
        const client = await db.getClient();

        try {
            await client.query('BEGIN');

            // ============================================
            // 1. GET OR CREATE CONVERSATION
            // ============================================
            let convId = conversationId;
            let isNewConversation = false;

            // Ownership check — a caller-supplied conversationId is never
            // trusted as-is. Authenticated callers may only continue a
            // conversation that belongs to them; anonymous callers may only
            // continue one with no owner at all. Anything else (wrong
            // owner, or the id doesn't exist) silently falls through to
            // starting a fresh conversation below — never a 403, so a
            // caller can't use the response to probe whether an id exists
            // or belongs to someone else.
            if (convId) {
                const existingConv = await conversationRepository.findById(convId);
                const ownedByCaller = existingConv && (
                    userId ? existingConv.user_id === userId : existingConv.user_id === null
                );
                if (!ownedByCaller) {
                    convId = null;
                }
            }

            if (!convId) {
                // Check if user has an active conversation
                if (userId) {
                    const existing = await conversationRepository.findByUserId(userId, { limit: 1 });
                    // We'll create a new one regardless for clean separation
                }

                const sessionId = Date.now().toString() + (userId ? '-' + userId.slice(0, 8) : '');
                const newConv = await chatbotRepository.createConversation(sessionId, userId || null);
                convId = newConv.id;
                isNewConversation = true;

                // Create default title
                const defaultTitle = this.detectLanguage(message) === 'ar' ? 'محادثة جديدة' : 'New conversation';
                await conversationRepository.upsertTitle(convId, defaultTitle, true);
            }

            // ============================================
            // 2. SAVE USER MESSAGE
            // ============================================
            await chatbotRepository.saveUserMessage(convId, message);

            // ============================================
            // 3. VALIDATE COORDINATES
            // ============================================
            latitude = (typeof latitude === 'number' && !isNaN(latitude) && latitude >= -90 && latitude <= 90) ? latitude : null;
            longitude = (typeof longitude === 'number' && !isNaN(longitude) && longitude >= -180 && longitude <= 180) ? longitude : null;

            // ============================================
            // 4. GET CONVERSATION MEMORY FOR CONTEXT
            // ============================================
            const context = await chatbotRepository.findContextByConversationId(convId);
            const recentMessages = await chatbotRepository.findMessagesByConversationId(convId, { limit: 10 });

            // ============================================
            // 5. CALL AI SERVICE
            // ============================================
            const ai = await aiClient.sendMessage({
                message,
                conversationId: convId,
                latitude,
                longitude,
                context: {
                    lastIntent: context?.last_intent || null,
                    currentTopic: context?.current_topic || null,
                    entities: context?.entities_json || {},
                    recentMessages: recentMessages.slice(-3).map(m => ({
                        role: m.message_type,
                        text: m.message_text
                    }))
                }
            });

            // ============================================
            // 6. NORMALIZE ENTITIES
            // ============================================
            const entities = await entityService.normalizeEntities(ai.entities || {});
            let reply = ai.reply;
            let places = [];
            let clinics = [];
            let doctors = [];

            // ============================================
            // 7. HANDLE INTENTS
            // ============================================

            // show_route — Reuse last known places
            if (ai.intent === 'show_route') {
                const lastPlaces = await memoryService.getLastPlacesFromMessages(client, convId);
                if (lastPlaces && lastPlaces.length > 0) {
                    places = lastPlaces;
                    reply = reply || '📍 تم تحديد المسار إلى الوجهة المحددة. اضغط على أي مكان لرسم المسار.';
                } else {
                    reply = '❌ لا توجد نتائج بحث سابقة. ابحث أولاً عن أقرب عيادة أو صيدلية.';
                }
            }

            // find_nearest — Query PostgreSQL for nearby places
            if (ai.intent === 'find_nearest') {
                if (!latitude || !longitude) {
                    reply = '📍 يرجى تفعيل الموقع أولاً حتى أتمكن من البحث عن الأماكن القريبة.';
                } else {
                    const type = entities.type || ai.entities?.type || 'clinic';

                    const nearbyPlaces = await clinicRepository.findNearby({
                        userLat: latitude,
                        userLng: longitude,
                        type,
                        radiusKm: 10,
                        limit: 10
                    });

                    if (nearbyPlaces.length > 0) {
                        reply = ragService.formatClinics(nearbyPlaces, type);
                        places = nearbyPlaces.map(c => ({
                            id: c.id,
                            name: c.name_ar || c.name_en,
                            nameAr: c.name_ar,
                            nameEn: c.name_en,
                            lat: parseFloat(c.latitude),
                            lng: parseFloat(c.longitude),
                            type: c.type,
                            address: c.address_ar || c.address_en,
                            phone: c.phone,
                            distance: c.distance_meters,
                            rating: c.average_rating,
                            services: c.services
                        }));

                        // Save places to conversation
                        for (const p of places) {
                            await conversationRepository.savePlace({
                                conversationId: convId,
                                userId,
                                placeName: p.name,
                                placeType: p.type || type,
                                latitude: p.lat,
                                longitude: p.lng,
                                address: p.address,
                                phone: p.phone,
                                distanceKm: p.distance ? (p.distance / 1000) : null
                            });
                        }
                    } else {
                        const typeLabels = {
                            pharmacy: 'صيدليات',
                            hospital: 'مستشفيات',
                            clinic: 'عيادات',
                            laboratory: 'مختبرات',
                            dental: 'أطباء أسنان',
                            radiology: 'مراكز أشعة',
                            emergency: 'طوارئ'
                        };
                        const label = typeLabels[type] || 'أماكن طبية';
                        reply = `❌ لا توجد ${label} قريبة حالياً.`;
                    }
                }
            }

            // find_doctor — Search doctors by specialty
            if (ai.intent === 'find_doctor') {
                const specialty = entities.specialty || entities.specialties?.[0];
                if (specialty) {
                    const doctorResults = await this.searchDoctorsBySpecialty(specialty);
                    doctors = doctorResults;
                    if (doctorResults.length > 0) {
                        reply = ragService.formatDoctors(doctorResults);
                    } else {
                        reply = `❌ لم أجد أطباء في تخصص "${specialty}" حالياً.`;
                    }
                }
            }

            // ============================================
            // 8. SAVE BOT MESSAGE WITH METADATA
            // ============================================
            const metadata = {
                entities,
                places,
                clinics,
                doctors,
                conversationContext: {
                    lastIntent: ai.intent,
                    confidence: ai.confidence,
                    hasLocation: !!(latitude && longitude)
                }
            };

            await chatbotRepository.saveBotMessage({
                conversationId: convId,
                messageText: reply,
                intent: ai.intent,
                confidence: ai.confidence || 0,
                metadata
            });

            // ============================================
            // 9. UPDATE CONVERSATION CONTEXT (MEMORY)
            // ============================================
            await chatbotRepository.upsertContext({
                conversationId: convId,
                lastIntent: ai.intent,
                currentTopic: ai.intent,
                entities: {
                    ...entities,
                    lastLatitude: latitude,
                    lastLongitude: longitude
                }
            });

            // ============================================
            // 10. UPDATE LAST MESSAGE TIMESTAMP
            // ============================================
            await conversationRepository.updateLastMessageAt(convId);

            // Auto-generate title from first user message if still default
            if (isNewConversation) {
                const titleText = message.length > 60 ? message.substring(0, 60).trim() + '...' : message;
                await conversationRepository.upsertTitle(convId, titleText, true);
            }

            await client.query('COMMIT');

            // ============================================
            // 11. RETURN STRUCTURED RESPONSE
            // ============================================
            return {
                conversationId: convId,
                reply,
                intent: ai.intent,
                confidence: ai.confidence || 0,
                places,
                clinics,
                doctors,
                route: null,
                suggestions: this.getSuggestions(ai.intent)
            };

        } catch (error) {
            await client.query('ROLLBACK');
            console.error('chatbot.service ERROR:', error.message || error);

            return {
                conversationId: conversationId || null,
                reply: '⚠️ حدث خطأ في المعالجة. يرجى المحاولة مرة أخرى.',
                intent: 'error',
                confidence: 0,
                places: [],
                clinics: [],
                doctors: [],
                route: null,
                suggestions: []
            };

        } finally {
            client.release();
        }
    }

    /**
     * Search doctors by specialty name
     */
    async searchDoctorsBySpecialty(specialty) {
        const DoctorRepository = require('../../repositories/doctor.repository');
        const doctors = await DoctorRepository.findBySpecialty(specialty, { limit: 5 });
        return doctors.map(d => ({
            id: d.id,
            name: d.first_name_ar || d.first_name_en + ' ' + (d.last_name_ar || d.last_name_en),
            specialty: d.specialty_ar || d.specialty_en,
            rating: d.average_rating,
            fee: d.consultation_fee,
            experience: d.years_of_experience,
            isAccepting: d.is_accepting_patients,
            image: d.profile_image_url
        }));
    }

    /**
     * Detect message language
     */
    detectLanguage(message) {
        if (!message) return 'en';
        return /[\u0600-\u06FF]/.test(message) ? 'ar' : 'en';
    }

    /**
     * Get contextual suggestions based on intent
     */
    getSuggestions(intent) {
        const suggestionMap = {
            'find_nearest': ['أظهر المسار', 'من يعمل هناك؟', 'ما هي الخدمات؟'],
            'find_doctor': ['حدد موعد', 'هل يوجد تقييمات؟', 'أين تقع العيادة؟'],
            'symptom_analysis': ['اعثر على طبيب', 'ما هو التخصص المناسب؟'],
            'medication_info': ['ما هي الجرعة؟', 'ما هي الآثار الجانبية؟'],
            'show_route': ['مدة الوصول؟', 'هل هناك مواقف؟']
        };
        return suggestionMap[intent] || ['أقرب عيادة', 'أقرب صيدلية', 'أقرب مستشفى'];
    }
}

module.exports = new ChatbotService();