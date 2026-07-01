export const openapi = {
  openapi: "3.0.3",
  info: {
    title: "MedOrbit Authentication Service",
    version: "0.1.0",
    description: "Registration, OTP verification, login, JWT issuance, refresh tokens, password reset.",
  },
  paths: {
    "/api/v1/auth/register": {
      post: {
        summary: "Register a new user",
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: {
                type: "object",
                required: ["email", "password", "fullName", "role"],
                properties: {
                  email: { type: "string", format: "email" },
                  password: { type: "string" },
                  phone: { type: "string" },
                  fullName: { type: "string" },
                  role: { type: "string", enum: ["admin", "doctor", "patient"] },
                  preferredLanguage: { type: "string", enum: ["en", "ar"] },
                },
              },
            },
          },
        },
        responses: { 201: { description: "Registered" }, 400: { description: "Validation error" }, 409: { description: "Email exists" } },
      },
    },
    "/api/v1/auth/verify-otp": {
      post: { summary: "Verify email with OTP", responses: { 200: { description: "Verified" } } },
    },
    "/api/v1/auth/login": {
      post: { summary: "Login and receive JWT + refresh token", responses: { 200: { description: "Tokens" }, 401: { description: "Invalid credentials" }, 423: { description: "Account locked" } } },
    },
    "/api/v1/auth/refresh": {
      post: { summary: "Rotate refresh token and get new access token", responses: { 200: { description: "New tokens" } } },
    },
    "/api/v1/auth/logout": {
      post: { summary: "Invalidate refresh token", responses: { 200: { description: "Logged out" } } },
    },
    "/api/v1/auth/forgot-password": {
      post: { summary: "Request password reset code", responses: { 200: { description: "Sent if exists" } } },
    },
    "/api/v1/auth/reset-password": {
      post: { summary: "Reset password with code", responses: { 200: { description: "Reset" } } },
    },
    "/health": { get: { summary: "Liveness", responses: { 200: { description: "OK" } } } },
    "/ready": { get: { summary: "Readiness", responses: { 200: { description: "Ready" } } } },
  },
};
