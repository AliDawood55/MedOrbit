const clinicRepository = require('../../repositories/clinic.repository');

/**
 * RAG Service — Response formatting and data retrieval
 * 
 * Handles:
 * - Formatting clinics, doctors, and places into readable text
 * - Generating structured response data for the frontend
 * - Type-aware Arabic formatting
 */
class RAGService {

    /**
     * Format clinic/hospital/pharmacy results for display
     */
    formatClinics(clinics, type) {
        if (!clinics || clinics.length === 0) {
            return '❌ لا يوجد أماكن قريبة حالياً.';
        }

        const titles = {
            pharmacy: '💊 أقرب صيدليات:\n\n',
            hospital: '🏥 أقرب مستشفيات:\n\n',
            clinic: '🩺 أقرب عيادات:\n\n',
            laboratory: '🔬 أقرب مختبرات:\n\n',
            dental: '🦷 أقرب أطباء أسنان:\n\n',
            radiology: '📡 أقرب مراكز أشعة:\n\n',
            emergency: '🚑 أقرب طوارئ:\n\n',
            medical_center: '🏥 أقرب مراكز طبية:\n\n',
            optical: '👓 أقرب مراكز بصرية:\n\n'
        };

        let text = titles[type] || '🏥 أقرب الأماكن الطبية:\n\n';

        clinics.forEach((c, index) => {
            const distanceMeters = parseFloat(c.distance_meters) || 0;
            const distanceKm = distanceMeters / 1000;
            const distanceText = distanceKm < 0.1
                ? 'قريب جداً ✅'
                : `${distanceKm.toFixed(2)} كم`;

            const rating = c.average_rating ? Number(c.average_rating).toFixed(1) : '—';

            text += `━━━━━━━━━━━━━━━━━━━━\n`;
            text += `🔢 ${index + 1}. ${c.name_ar || c.name_en}\n\n`;
            text += `⭐ التقييم: ${rating}\n`;
            text += `📍 البعد: ${distanceText}\n`;

            if (c.phone) {
                text += `📞 الهاتف: ${c.phone}\n`;
            }

            if (c.services && c.services.length > 0) {
                text += `🛠️ الخدمات: ${c.services.slice(0, 3).join('، ')}\n`;
            }

            text += `🗺️ https://www.google.com/maps?q=${c.latitude},${c.longitude}\n\n`;
        });

        text += `━━━━━━━━━━━━━━━━━━━━\n`;
        return text;
    }

    /**
     * Format doctor search results
     */
    formatDoctors(doctors) {
        if (!doctors || doctors.length === 0) {
            return '❌ لم أجد أطباء في هذا التخصص حالياً.';
        }

        let text = '👨‍⚕️ الأطباء المتاحون:\n\n';

        doctors.forEach((d, index) => {
            const name = d.first_name_ar || d.first_name_en + ' ' + (d.last_name_ar || d.last_name_en);
            const fee = d.consultation_fee ? `${d.consultation_fee} شيكل` : '—';
            const rating = d.average_rating ? `⭐ ${Number(d.average_rating).toFixed(1)}` : '';
            const experience = d.years_of_experience ? `${d.years_of_experience} سنوات خبرة` : '';

            text += `━━━━━━━━━━━━━━━━━━━━\n`;
            text += `🔢 ${index + 1}. ${name}\n`;
            text += `   ${d.specialty_ar || d.specialty_en || ''}\n`;
            if (rating) text += `   ${rating}\n`;
            if (fee) text += `   💰 الكشف: ${fee}\n`;
            if (experience) text += `   📅 ${experience}\n`;
            text += '\n';
        });

        text += `━━━━━━━━━━━━━━━━━━━━\n`;
        text += '💡 يمكنك حجز موعد أو السؤال عن العيادة.';
        return text;
    }

    /**
     * Format a single place for map card rendering
     */
    formatPlaceCard(place) {
        return {
            id: place.id,
            name: place.name_ar || place.name_en,
            nameAr: place.name_ar,
            nameEn: place.name_en,
            type: place.type || 'clinic',
            lat: parseFloat(place.latitude),
            lng: parseFloat(place.longitude),
            address: place.address_ar || place.address_en,
            phone: place.phone,
            distance: place.distance_meters ? parseFloat(place.distance_meters) : null,
            distanceKm: place.distance_meters ? (parseFloat(place.distance_meters) / 1000).toFixed(2) : null,
            rating: place.average_rating ? parseFloat(place.average_rating) : null,
            services: place.services || [],
            operatingHours: place.operating_hours || null,
            insurance: place.insurance_accepted || []
        };
    }

    /**
     * Format multiple places for map rendering
     */
    formatPlacesForMap(places) {
        if (!places || !Array.isArray(places)) return [];
        return places.map(p => this.formatPlaceCard(p));
    }
}

module.exports = new RAGService();