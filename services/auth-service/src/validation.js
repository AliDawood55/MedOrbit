const PASSWORD_RE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ROLES = new Set(["admin", "doctor", "patient"]);
const LANGUAGES = new Set(["en", "ar"]);

export function validateRegistration(body) {
  const errors = [];
  if (!body.email || !EMAIL_RE.test(body.email)) errors.push("invalid email");
  if (!body.password || !PASSWORD_RE.test(body.password)) {
    errors.push(
      "password must be at least 8 characters with uppercase, lowercase, digit, and special character"
    );
  }
  if (!body.fullName || body.fullName.trim().length < 2) errors.push("fullName is required");
  if (!body.role || !ROLES.has(body.role)) errors.push("role must be admin, doctor, or patient");
  if (body.preferredLanguage && !LANGUAGES.has(body.preferredLanguage)) {
    errors.push("preferredLanguage must be en or ar");
  }
  return errors;
}
