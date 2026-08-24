# Deferred Backend Surfaces

This register records database or code surfaces that are deliberately not active product features. It prevents a client from inferring an API contract from a historical migration or source file.

## Video consultations (`009_s6_video_consultations.sql`)

**Status:** historical and inert; explicitly deferred.

Migration `009_s6_video_consultations.sql` created `medorbit.video_consultations` and its indexes. As of 2026-08-25, MedOrbit has no mounted HTTP route, Socket.IO signalling event, media service, worker, or supported client navigation for video consultations. The table must therefore not be used as evidence that video consultation is an available feature.

Do not modify migrations `001` through `015`. A future video-consultation product must start with a versioned API and Socket.IO contract, authorization/privacy review, media-provider design, retention policy, and additive migration(s). Existing historical rows must be handled deliberately rather than exposed by a new endpoint automatically.

## Doctor-clinic assignments

**Status:** active, with one source of truth.

`medorbit.doctor_clinic_assignments` is the authoritative relationship for clinic assignment and scheduling validation. Public doctor profile projections share one route-level query. `GET /api/doctors/:id/clinics` remains available for compatibility but is a compact projection of that same source; it is not a second relationship model.
