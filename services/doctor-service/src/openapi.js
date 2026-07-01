export const openapi = {
  openapi: "3.0.3",
  info: {
    title: "MedOrbit Doctor Service",
    version: "0.1.0",
    description: "Doctor catalog, specialties, search & filter, ratings, verification workflow.",
  },
  components: {
    securitySchemes: { bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" } },
  },
  paths: {
    "/api/v1/specialties": { get: { summary: "List specialties (bilingual)", responses: { 200: { description: "Specialties" } } } },
    "/api/v1/doctors": { get: { summary: "Search verified doctors", responses: { 200: { description: "Doctors" } } } },
    "/api/v1/doctors/{id}": { get: { summary: "Doctor details", responses: { 200: { description: "Doctor" } } } },
    "/api/v1/doctors/me": { put: { summary: "Create/update my doctor profile (doctor)", security: [{ bearerAuth: [] }], responses: { 200: { description: "Updated" } } } },
    "/api/v1/doctors/admin/pending": { get: { summary: "List unverified doctors (admin)", security: [{ bearerAuth: [] }], responses: { 200: { description: "Pending" } } } },
    "/api/v1/doctors/{id}/verify": { post: { summary: "Verify a doctor (admin)", security: [{ bearerAuth: [] }], responses: { 200: { description: "Verified" } } } },
    "/api/v1/doctors/{id}/ratings": {
      get: { summary: "List doctor ratings", responses: { 200: { description: "Ratings" } } },
      post: { summary: "Rate a doctor (patient)", security: [{ bearerAuth: [] }], responses: { 201: { description: "Rated" } } },
    },
    "/health": { get: { summary: "Liveness", responses: { 200: { description: "OK" } } } },
    "/ready": { get: { summary: "Readiness", responses: { 200: { description: "Ready" } } } },
  },
};
