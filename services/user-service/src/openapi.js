export const openapi = {
  openapi: "3.0.3",
  info: {
    title: "MedOrbit User Service",
    version: "0.1.0",
    description: "User profiles, patient medical info, preferences, admin user management.",
  },
  components: {
    securitySchemes: { bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" } },
  },
  security: [{ bearerAuth: [] }],
  paths: {
    "/api/v1/users/me": {
      get: { summary: "Get my profile", responses: { 200: { description: "Profile" } } },
      put: { summary: "Create/update my profile", responses: { 200: { description: "Updated" } } },
      delete: { summary: "Soft-delete my account", responses: { 200: { description: "Deleted" } } },
    },
    "/api/v1/users/me/medical-info": {
      get: { summary: "Get my medical info (patient)", responses: { 200: { description: "Medical info" } } },
      put: { summary: "Update my medical info (patient)", responses: { 200: { description: "Updated" } } },
    },
    "/api/v1/users": {
      get: { summary: "List/search users (admin)", responses: { 200: { description: "Users" } } },
    },
    "/api/v1/users/{id}/suspend": {
      post: { summary: "Suspend a user (admin)", responses: { 200: { description: "Suspended" } } },
    },
    "/api/v1/users/{id}/unsuspend": {
      post: { summary: "Unsuspend a user (admin)", responses: { 200: { description: "Unsuspended" } } },
    },
    "/api/v1/users/{id}": {
      delete: { summary: "Soft-delete a user (admin)", responses: { 200: { description: "Deleted" } } },
    },
    "/health": { get: { summary: "Liveness", responses: { 200: { description: "OK" } } } },
    "/ready": { get: { summary: "Readiness", responses: { 200: { description: "Ready" } } } },
  },
};
