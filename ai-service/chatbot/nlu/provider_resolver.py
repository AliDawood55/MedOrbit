from typing import Dict, List, Optional


class ProviderResolver:
    """
    Lightweight provider ranking system.
    Ranks doctors, clinics, and hospitals by rating, distance,
    availability, insurance acceptance, and experience.
    Runs locally in the AI service (no DB calls) — works on
    data already retrieved by the backend.
    """

    def rank_doctors(self, doctors: List[Dict], preferences: Optional[Dict] = None) -> List[Dict]:
        """
        Rank doctors by weighted score.
        
        Weighting factors:
        - Rating (40%)
        - Experience (20%)  
        - Fee (20%) — lower is better
        - Accepting patients (10%)
        - Insurance match (10%)
        """
        if not doctors:
            return []

        preferences = preferences or {}
        preferred_insurance = preferences.get("insurance", "").lower()
        max_fee = preferences.get("max_fee")
        min_rating = preferences.get("min_rating", 0)

        scored = []
        for doc in doctors:
            score = 0.0
            details = []

            # Rating score (0-40 points)
            rating = float(doc.get("average_rating", doc.get("rating", 0)) or 0)
            rating_score = (rating / 5.0) * 40
            score += rating_score
            if rating >= min_rating:
                details.append(f"rating={rating:.1f}/5")

            # Experience score (0-20 points)
            experience = int(doc.get("years_of_experience", 0) or 0)
            exp_score = min(experience / 30.0, 1.0) * 20
            score += exp_score
            if experience > 0:
                details.append(f"exp={experience}yr")

            # Fee score (0-20 points) — lower is better
            fee = float(doc.get("consultation_fee", doc.get("fee", 0)) or 0)
            if fee > 0:
                if max_fee and fee > max_fee:
                    fee_score = 0
                else:
                    fee_score = max(0, 20 - (fee / 50))  # Reduce by 1 per 50₪ over 0
                score += fee_score
                details.append(f"fee={fee:.0f}₪")
            else:
                score += 10  # Neutral if no fee info
                details.append("fee=unknown")

            # Accepting patients (0-10 points)
            accepting = doc.get("is_accepting_patients", doc.get("isAccepting", True))
            if accepting:
                score += 10
                details.append("accepting=yes")
            else:
                details.append("accepting=no")

            # Insurance match (0-10 points)
            doctor_insurance = doc.get("insurance_accepted", [])
            if preferred_insurance and doctor_insurance:
                if any(preferred_insurance in ins.lower() for ins in doctor_insurance):
                    score += 10
                    details.append("insurance=match")
            else:
                score += 5  # Neutral

            scored.append({
                **doc,
                "_score": round(score, 2),
                "_score_details": "; ".join(details),
                "_rank_factors": {
                    "rating_score": round(rating_score, 2),
                    "experience_score": round(exp_score, 2),
                    "fee_score": round(fee_score, 2) if fee > 0 else 10,
                    "accepting_score": 10 if accepting else 0,
                    "insurance_score": 10 if preferred_insurance and doctor_insurance and any(
                        preferred_insurance in ins.lower() for ins in doctor_insurance
                    ) else (5 if doctor_insurance else 0)
                }
            })

        # Sort by score descending
        scored.sort(key=lambda x: x["_score"], reverse=True)

        # Add rank
        for i, item in enumerate(scored):
            item["_rank"] = i + 1

        return scored

    def rank_clinics(self, clinics: List[Dict], preferences: Optional[Dict] = None) -> List[Dict]:
        """
        Rank clinics by weighted score.
        
        Weighting factors:
        - Distance (40%) — closer is better
        - Rating (30%)
        - Insurance match (15%)
        - Service availability (15%)
        """
        if not clinics:
            return []

        preferences = preferences or {}
        preferred_insurance = preferences.get("insurance", "").lower()
        preferred_services = preferences.get("services", [])

        scored = []
        for clinic in clinics:
            score = 0.0
            details = []

            # Distance score (0-40 points)
            distance_m = float(clinic.get("distance_meters", clinic.get("distance", 0)) or 0)
            distance_km = distance_m / 1000
            if distance_km <= 0.5:
                dist_score = 40  # Very close
            elif distance_km <= 1.0:
                dist_score = 35
            elif distance_km <= 2.0:
                dist_score = 28
            elif distance_km <= 5.0:
                dist_score = 20
            elif distance_km <= 10.0:
                dist_score = 10
            else:
                dist_score = 5
            score += dist_score
            details.append(f"dist={distance_km:.1f}km")

            # Rating score (0-30 points)
            rating = float(clinic.get("average_rating", clinic.get("rating", 0)) or 0)
            rating_score = (rating / 5.0) * 30
            score += rating_score
            if rating:
                details.append(f"rating={rating:.1f}")

            # Insurance match (0-15 points)
            clinic_insurance = clinic.get("insurance_accepted", [])
            if preferred_insurance and clinic_insurance:
                if any(preferred_insurance in ins.lower() for ins in clinic_insurance):
                    score += 15
                    details.append("insurance=yes")
            else:
                score += 7  # Neutral

            # Service availability (0-15 points)
            clinic_services = clinic.get("services", [])
            if preferred_services and clinic_services:
                matched = sum(1 for s in preferred_services if s.lower() in [cs.lower() for cs in clinic_services])
                service_score = (matched / len(preferred_services)) * 15 if preferred_services else 0
                score += service_score
                if matched > 0:
                    details.append(f"services={matched}/{len(preferred_services)}")
            else:
                score += 7  # Neutral

            scored.append({
                **clinic,
                "_score": round(score, 2),
                "_score_details": "; ".join(details),
                "_distance_km": round(distance_km, 2)
            })

        scored.sort(key=lambda x: x["_score"], reverse=True)
        for i, item in enumerate(scored):
            item["_rank"] = i + 1

        return scored

    def rank_hospitals(self, hospitals: List[Dict], preferences: Optional[Dict] = None) -> List[Dict]:
        """Rank hospitals using the same logic as clinics (distance + rating)."""
        return self.rank_clinics(hospitals, preferences)

    def get_best_provider(self, ranked: List[Dict]) -> Optional[Dict]:
        """Get the highest-ranked provider."""
        return ranked[0] if ranked else None

    def format_provider_response(self, ranked: List[Dict], provider_type: str = "doctor", language: str = "ar") -> str:
        """
        Format ranked providers into a readable response string.
        """
        if not ranked:
            if language == "ar":
                return f"❌ لا توجد نتائج متاحة حالياً."
            return f"❌ No results available."

        lines = []
        if language == "ar":
            type_titles = {
                "doctor": "👨‍⚕️ الأطباء (مرتبة حسب التقييم):\n",
                "clinic": "🏥 العيادات (مرتبة حسب المسافة والتقييم):\n",
                "hospital": "🏥 المستشفيات (مرتبة حسب المسافة):\n",
                "pharmacy": "💊 الصيدليات (مرتبة حسب المسافة):\n"
            }
            lines.append(type_titles.get(provider_type, "📋 النتائج:\n"))

            for i, provider in enumerate(ranked[:5]):
                rank = i + 1
                score = provider.get("_score", 0)

                if provider_type == "doctor":
                    name = provider.get("first_name_ar") or provider.get("name") or f"طبيب {rank}"
                    specialty = provider.get("specialty_ar") or provider.get("specialty", "")
                    rating = provider.get("average_rating", provider.get("rating", "—"))
                    fee = provider.get("consultation_fee", provider.get("fee", "—"))
                    lines.append(f"\n{rank}. {name}")
                    if specialty:
                        lines.append(f"   تخصص: {specialty}")
                    lines.append(f"   ⭐ {rating} | 💰 {fee}₪")
                    lines.append(f"   🔥 التوافق: {score}%")

                elif provider_type in ("clinic", "hospital", "pharmacy"):
                    name = provider.get("name_ar") or provider.get("name", f"مكان {rank}")
                    dist = provider.get("_distance_km", "—")
                    rating = provider.get("average_rating", provider.get("rating", "—"))
                    phone = provider.get("phone", "")
                    lines.append(f"\n{rank}. {name}")
                    lines.append(f"   📍 {dist} كم | ⭐ {rating}")
                    if phone:
                        lines.append(f"   📞 {phone}")

            lines.append(f"\n💡 اختر رقم النتيجة لمعرفة المزيد.")

        else:
            type_titles = {
                "doctor": "👨‍⚕️ Doctors (ranked by rating):\n",
                "clinic": "🏥 Clinics (ranked by distance & rating):\n",
                "hospital": "🏥 Hospitals (ranked by distance):\n",
                "pharmacy": "💊 Pharmacies (ranked by distance):\n"
            }
            lines.append(type_titles.get(provider_type, "📋 Results:\n"))

            for i, provider in enumerate(ranked[:5]):
                rank = i + 1

                if provider_type == "doctor":
                    name = provider.get("first_name_en") or provider.get("name") or f"Doctor {rank}"
                    specialty = provider.get("specialty_en") or provider.get("specialty", "")
                    rating = provider.get("average_rating", provider.get("rating", "—"))
                    fee = provider.get("consultation_fee", provider.get("fee", "—"))
                    lines.append(f"\n{rank}. {name}")
                    if specialty:
                        lines.append(f"   Specialty: {specialty}")
                    lines.append(f"   ⭐ {rating} | 💰 ${fee}")
                    lines.append(f"   🔥 Match: {score}%")

                elif provider_type in ("clinic", "hospital", "pharmacy"):
                    name = provider.get("name_en") or provider.get("name", f"Place {rank}")
                    dist = provider.get("_distance_km", "—")
                    rating = provider.get("average_rating", provider.get("rating", "—"))
                    phone = provider.get("phone", "")
                    lines.append(f"\n{rank}. {name}")
                    lines.append(f"   📍 {dist} km | ⭐ {rating}")
                    if phone:
                        lines.append(f"   📞 {phone}")

            lines.append(f"\n💡 Select a number to learn more.")

        return "\n".join(lines)