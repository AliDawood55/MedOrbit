const API_BASE = window.MEDORBIT_API_BASE || "http://localhost:8080";

async function request(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...options.headers };
  const token = localStorage.getItem("medorbit.accessToken");
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(body.error || "request failed"), { status: res.status, body });
  return body;
}

export const api = {
  register: (data) => request("/api/v1/auth/register", { method: "POST", body: JSON.stringify(data) }),
  login: (data) => request("/api/v1/auth/login", { method: "POST", body: JSON.stringify(data) }),
  verifyOtp: (data) => request("/api/v1/auth/verify-otp", { method: "POST", body: JSON.stringify(data) }),
  listDoctors: (params = {}) => request(`/api/v1/doctors?${new URLSearchParams(params)}`),
  listSpecialties: () => request("/api/v1/specialties"),
};
