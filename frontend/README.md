# MedOrbit Frontend

The web client for MedOrbit, providing patient, doctor, and admin interfaces
for authentication, appointments, messaging, healthcare discovery, and
AI-assisted healthcare features.

## Tech

- Plain **HTML5 + CSS3 + vanilla JavaScript** — no framework and no build step.
- **Leaflet** for the map (OpenStreetMap tiles), served as static files by nginx
  in Docker (`frontend/Dockerfile`).
- Bilingual UI (Arabic / English).

## Layout

- `public/` — one HTML file per page (auth, dashboard, appointments, records,
  billing, admin screens, AI tools, …).
- `src/css/` — page and component stylesheets. See
  [`src/css/README.md`](src/css/README.md) for the CSS load-order contract and
  architecture guardrails.
- `src/js/` — per-page scripts and shared helpers (API client, i18n, map).
- `tests/` — Node-based UI tests, run from the repo root (see root
  `package.json`, e.g. `npm run test:user-content-ui`).

## Running

From the repository root:

- `npm run dev` — runs ai-service, backend, and frontend together on the host
  (frontend is served on <http://localhost:8080>).
- `npm run dev:frontend` — serves only this directory on port 8080.

The frontend expects the backend API and ai-service to be reachable; see the
root [`README.md`](../README.md) and [`DOCKER.md`](../DOCKER.md) for the full
stack.
