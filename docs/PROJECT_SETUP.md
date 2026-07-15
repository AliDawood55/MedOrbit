# MedOrbit Setup Guide

> **MedOrbit – Smart Healthcare AI Platform**
>
> A graduation project by:
> - **Ali Ghassan**
> - **Omar Abumazen**

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Requirements](#requirements)
3. [Clone Project](#clone-project)
4. [Backend Setup](#backend-setup)
5. [AI Service Setup](#ai-service-setup)
6. [Ollama Setup](#ollama-setup)
7. [PostgreSQL Setup](#postgresql-setup)
8. [Frontend Setup](#frontend-setup)
9. [Startup Order](#startup-order)
10. [Ports](#ports)
11. [Common Problems](#common-problems)
12. [Project Verification](#project-verification)
13. [Development Notes](#development-notes)

---

## Project Structure

```
MedOrbit/
│
├── backend/              # Node.js + Express API server
│   ├── src/              # Application source code (routes, controllers, services, middleware)
│   ├── server.js         # Entry point — starts the Express server
│   ├── .env.example      # Environment variable template (copy to .env)
│   ├── package.json      # Node dependencies and scripts
│   └── storage/          # File uploads (gitignored)
│
├── ai-service/           # Python FastAPI AI microservice
│   ├── chatbot/          # Main chatbot module (intent classifier, entity extractor, NLU pipeline)
│   ├── llm/              # LLM service — connects to Ollama for response generation
│   ├── rag/              # Retrieval-Augmented Generation (context retrieval)
│   ├── data/             # Data files for the AI service
│   ├── requirements.txt  # Python dependencies
│   └── tests/            # Test suite
│
├── frontend/             # Static HTML/CSS/JS frontend (no framework)
│   ├── public/           # index.html entry point
│   ├── src/              # CSS, JS, components, utilities
│   └── README.md         # Frontend-specific setup docs
│
├── database/             # PostgreSQL database artifacts
│   ├── schema/           # SQL schema files (tables, indexes, triggers, seed data)
│   ├── migrations/       # Incremental migration scripts
│   └── seed/             # Seed data dump (clinics, doctors, patients, etc.)
│
├── docs/                 # Project documentation
│   ├── PROJECT_SETUP.md  # This file
│   ├── Auth.md           # Authentication documentation
│   ├── readme.md         # Legacy docs
│   └── gitTracking-omar.md
│
├── tempData/             # Temporary data (images, etc.)
├── .gitignore            # Git exclusion rules
└── README.md             # Project overview
```

---

## Requirements

Ensure the following are installed **before** proceeding:

| Component      | Minimum Version | Required For            |
|----------------|-----------------|-------------------------|
| Node.js        | v18.x or higher | Backend API server      |
| npm            | v9.x or higher  | Installing Node packages |
| Python         | 3.10 or higher  | AI microservice         |
| pip            | latest          | Installing Python packages |
| PostgreSQL     | 15.x or higher  | Database                |
| Git            | v2.x or higher  | Cloning the repository  |
| Ollama         | v0.3.x or higher| Local LLM inference     |

Verify each installation:

```powershell
node --version
npm --version
python --version
pip --version
psql --version
git --version
ollama --version
```

---

## Clone Project

```powershell
git clone https://github.com/AliDawood55/MedOrbit.git
cd MedOrbit
```

---

## Backend Setup

### 1. Navigate to backend directory

```powershell
cd backend
```

### 2. Install dependencies

```powershell
npm install
```

This installs the following key packages:

- `express` — web framework
- `pg` — PostgreSQL client
- `dotenv` — environment variable loader
- `bcryptjs` / `bcrypt` — password hashing
- `jsonwebtoken` — JWT authentication
- `cors` — cross-origin requests
- `helmet` — security headers
- `morgan` / `pino` — request logging
- `multer` — file uploads
- `nodemailer` — email sending
- `node-cron` — scheduled tasks
- `axios` — HTTP client (calls AI service)
- `express-rate-limit` — rate limiting

### 3. Create environment file

Copy `.env.example` to `.env`:

```powershell
copy .env.example .env
```

### 4. Configure environment variables

Open `backend/.env` in any editor and adjust the values:

```ini
# Application
PORT=3001
NODE_ENV=development

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=medorbit
DB_USER=postgres
DB_PASSWORD=your_password_here           # ← Change this to your PostgreSQL password

# JWT
JWT_SECRET=your-super-secret-key-min-32-chars-change-this   # ← Change this
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# Bcrypt
BCRYPT_ROUNDS=12

# CORS
CORS_ORIGIN=http://localhost:8080         # Frontend URL (adjust if different)

# Chatbot AI Service
AI_SERVICE_URL=http://localhost:8001      # Must match AI service port
AI_SERVICE_TIMEOUT_MS=8000
```

> **⚠️ Important:** The `AI_SERVICE_URL` must point to the port the AI service is actually running on (default is `8001`). The example file shows `8000` — update it to `8001` if needed.

### 5. Start the backend

**Development mode** (with auto-restart on file changes via Nodemon):

```powershell
npm run dev
```

**Production mode:**

```powershell
npm start
```

### 6. Expected output

```
========================================
MedOrbit API Server
Running on port 3001
Environment: development
========================================
```

---

## AI Service Setup

### 1. Navigate to AI service directory

```powershell
cd ai-service
```

### 2. Create a Python virtual environment

```powershell
python -m venv venv
```

### 3. Activate the virtual environment

```powershell
.\venv\Scripts\Activate.ps1
```

You should see `(venv)` appear in your terminal prompt.

### 4. Install dependencies

```powershell
pip install -r requirements.txt
```

The `requirements.txt` contains:

- `fastapi==0.116.1` — web framework for the AI API
- `uvicorn[standard]==0.35.0` — ASGI server
- `pydantic==2.11.7` — data validation

### 5. Install the `requests` module (if missing)

If you encounter a `ModuleNotFoundError: No module named 'requests'` error:

```powershell
pip install requests
```

### 6. Start the AI service

```powershell
uvicorn chatbot.main:app --reload --host 127.0.0.1 --port 8001
```

### 7. Expected output

```
INFO:     Uvicorn running on http://127.0.0.1:8001
INFO:     Application startup complete.
```

---

## Ollama Setup

MedOrbit uses **Ollama** to run a local large language model (LLM) for generating conversational responses. The AI service connects to Ollama's API at `http://localhost:11434`.

### 1. Verify installation

```powershell
ollama --version
```

If not installed, download from [ollama.com](https://ollama.com) and install.

### 2. Check that the Ollama service is running

```powershell
ollama ps
```

If the service is running, this shows any currently loaded models. If it returns nothing or an error, start Ollama manually (the Ollama service runs in the background once launched from the Start menu or terminal).

### 3. List available models

```powershell
ollama list
```

### 4. Pull the required model

The AI service's default model is `qwen2:7b` (configurable via the `OLLAMA_MODEL` environment variable in `ai-service/llm/llm_service.py`). Pull it with:

```powershell
ollama pull qwen2:7b
```

If you prefer to use the **qwen2.5-coder:7b** model instead (recommended for better code-aware responses), set the environment variable before starting the AI service, or modify the default in `ai-service/llm/llm_service.py`:

```powershell
$env:OLLAMA_MODEL="qwen2.5-coder:7b"
ollama pull qwen2.5-coder:7b
```

### 5. Verify the model is ready

```powershell
ollama ps
```

You should see the model listed and its status.

### 6. Common Ollama port

Ollama runs by default on port **11434**. The AI service expects it there. Verify connectivity:

```powershell
curl http://localhost:11434/api/tags
```

You should receive a JSON response listing available models.

---

## PostgreSQL Setup

### 1. Verify PostgreSQL is running

```powershell
psql -U postgres -c "SELECT version();"
```

Enter your PostgreSQL password when prompted.

### 2. Create the database

```powershell
psql -U postgres -c "CREATE DATABASE medorbit;"
```

### 3. Create the schema (run all schema files in order)

Run the main schema file first:

```powershell
psql -U postgres -d medorbit -f database/schema/001_medorbit_schema.sql
```

Then apply additional schema files:

```powershell
psql -U postgres -d medorbit -f database/schema/002_auth_tokens.sql
psql -U postgres -d medorbit -f database/schema/002_chatbot_context.sql
psql -U postgres -d medorbit -f database/schema/003_update_user_sessions.sql
psql -U postgres -d medorbit -f database/schema/004_password_reset.sql
psql -U postgres -d medorbit -f database/schema/005_email_verification.sql
psql -U postgres -d medorbit -f database/schema/006_update_password_reset_tokens.sql
psql -U postgres -d medorbit -f database/schema/007_user_profile.sql
```

### 4. Apply migrations (if any)

```powershell
psql -U postgres -d medorbit -f database/migrations/001_fix_clinics_type_column.sql
psql -U postgres -d medorbit -f database/migrations/002_conversation_management.sql
psql -U postgres -d medorbit -f database/migrations/003_medical_search_indexes.sql
```

### 5. Load seed data

```powershell
psql -U postgres -d medorbit -f database/seed/002_seed_data.sql
```

This populates the database with:

- **25 medical specialties** (translated in Arabic and English)
- **8 Nablus regions** with boundary GeoJSON data
- **4 clinics** and **3 hospitals/centers**
- **3 doctors** with professional profiles
- **3 patients** with medical history
- **Sample appointments, prescriptions, medical records**
- **Medication database** (10 common drugs)
- **System settings** (app name, version, support email, etc.)
- **Sample notifications** and **reviews**

### 6. Verify the connection

The backend will automatically verify the connection on startup. You should see:

```
✅ Connected to PostgreSQL (medorbit)
```

If you see this message, the database is properly configured.

### 7. Verify data was loaded

```powershell
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM clinics;"
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM doctors;"
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM specialties;"
```

---

## Frontend Setup

The frontend is a **static** HTML/CSS/JavaScript application with no build tools. It uses:

- **Leaflet.js** for interactive maps (OpenStreetMap tiles)
- **Font Awesome** for icons
- **Google Fonts** (Cairo for Arabic, Inter for English)
- **Vanilla JavaScript** (no React, Vue, or Angular)

### 1. Serve the frontend

Because the frontend uses `fetch` and module-style imports, it **must** be served via HTTP, not opened as a `file://` path.

**Option A — Using Python (recommended):**

```powershell
cd frontend
python -m http.server 8080
```

**Option B — Using npx (requires Node.js):**

```powershell
cd frontend
npx serve -p 8080
```

**Option C — VS Code Live Server:**
Install the "Live Server" extension, right-click `frontend/public/index.html`, and select "Open with Live Server".

### 2. Open the application

```
http://localhost:8080/public/
```

### 3. Verify the backend connection

The frontend is pre-configured to call the backend at `http://127.0.0.1:3001/api` (set in `frontend/src/js/api.js`). If your backend runs on a different host or port, update the `BASE_URL` constant in that file:

```javascript
const BASE_URL = 'http://127.0.0.1:3001/api';
```

### 4. What to expect

- A split-panel interface with a **chat panel** (left) and an **interactive map** (right)
- The chatbot responds to natural language queries in **Arabic** and **English**
- You can search for nearby clinics, pharmacies, hospitals, and doctors
- The map shows results with markers and supports route drawing
- The interface supports **dark/light theme** toggling and **language switching**

---

## Startup Order

The components must be started in the correct order because each depends on the previous one.

```
┌──────────────────────────────────────────────────┐
│                    ORDER                          │
├──────────────────────────────────────────────────┤
│  1. PostgreSQL         │ Database must be ready   │
│  2. Ollama             │ LLM must be available    │
│  3. AI Service         │ Depends on Ollama        │
│  4. Backend            │ Depends on DB + AI       │
│  5. Frontend           │ Depends on Backend       │
└──────────────────────────────────────────────────┘
```

### Step-by-step:

#### Step 1: Start PostgreSQL

```powershell
# On Windows, PostgreSQL usually runs as a service.
# Verify it's running:
psql -U postgres -c "SELECT 1;"
```

#### Step 2: Start Ollama

Ensure the Ollama service is running. Pull the model if not already done:

```powershell
ollama pull qwen2:7b
```

#### Step 3: Start AI Service

Open a **new PowerShell terminal** (as admin if needed):

```powershell
cd ai-service
.\venv\Scripts\Activate.ps1
uvicorn chatbot.main:app --reload --host 127.0.0.1 --port 8001
```

#### Step 4: Start Backend

Open another **new PowerShell terminal**:

```powershell
cd backend
npm run dev
```

#### Step 5: Start Frontend

Open another **new PowerShell terminal**:

```powershell
cd frontend
python -m http.server 8080
```

Open `http://localhost:8080/public/` in your browser.

---

## Ports

| Service       | Port  | URL                             | Notes                          |
|---------------|-------|---------------------------------|--------------------------------|
| **Backend**   | 3001  | `http://localhost:3001`         | Express API server             |
| **AI Service**| 8001  | `http://localhost:8001`         | FastAPI microservice           |
| **Ollama**    | 11434 | `http://localhost:11434`        | Local LLM inference            |
| **Frontend**  | 8080  | `http://localhost:8080/public/` | Static file server (Python)    |

> **Note on AI Service Port:** The backend `.env.example` has `AI_SERVICE_URL=http://localhost:8000`, but the AI service is configured to run on **port 8001**. Make sure to update the backend's `.env` file to use port `8001` to match the actual AI service port.

---

## Common Problems

### ❌ `ModuleNotFoundError: No module named 'requests'`

**Problem:** The AI service requires the `requests` module but it's not installed.

**Solution:**

```powershell
cd ai-service
.\venv\Scripts\Activate.ps1
pip install requests
```

### ❌ `Port already in use`

**Problem:** One of the required ports (3001, 8001, 8080, or 11434) is already occupied by another process.

**Solution:** Find which process is using the port and stop it:

```powershell
# Find process on port 3001
netstat -ano | findstr :3001
taskkill /PID <PID> /F
```

Or change the port in the respective configuration file.

### ❌ `Backend cannot connect to AI Service`

**Problem:** The backend cannot reach the AI service at the configured URL.

**Solution:**

1. Ensure the AI service is running: check the terminal for `Application startup complete.`
2. Verify the port in `backend/.env`:
   ```ini
   AI_SERVICE_URL=http://localhost:8001
   ```
3. Test manually with curl:
   ```powershell
   curl http://localhost:8001/health
   ```
   Expected response: `{"status":"healthy","service":"medorbit-ai","version":"2.0.0"}`

### ❌ `AI cannot connect to Ollama`

**Problem:** The AI service (LLM module) cannot reach the Ollama API.

**Solution:**

1. Ensure Ollama is running:
   ```powershell
   ollama ps
   ```
2. Verify the Ollama URL in `ai-service/llm/llm_service.py`:
   ```python
   OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
   ```
3. Test connectivity:
   ```powershell
   curl http://localhost:11434/api/tags
   ```
4. Check the model is pulled:
   ```powershell
   ollama list
   ```
5. If the model is missing, pull it:
   ```powershell
   ollama pull qwen2:7b
   ```

### ❌ `Database connection failed`

**Problem:** The backend cannot connect to PostgreSQL.

**Solution:**

1. Verify PostgreSQL is running.
2. Check credentials in `backend/.env`:
   ```ini
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=medorbit
   DB_USER=postgres
   DB_PASSWORD=your_password
   ```
3. Test the connection manually:
   ```powershell
   psql -U postgres -d medorbit -c "SELECT 1;"
   ```
4. Ensure the database `medorbit` exists:
   ```powershell
   psql -U postgres -c "CREATE DATABASE medorbit;"
   ```

### ❌ `email_queue relation missing`

**Problem:** The backend references the `email_queue` table but it wasn't created.

**Solution:** The `email_queue` table is part of the main schema. Re-run the schema creation:

```powershell
psql -U postgres -d medorbit -f database/schema/001_medorbit_schema.sql
```

If the table still doesn't appear, check the schema file includes it (it is defined as Table 14 in the SQL).

### ❌ `Node modules missing`

**Problem:** The backend cannot start because `node_modules` is missing.

**Solution:**

```powershell
cd backend
npm install
```

### ❌ `Virtual environment missing`

**Problem:** The Python virtual environment for the AI service is missing.

**Solution:**

```powershell
cd ai-service
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### ❌ `Git ignored files missing`

**Problem:** Certain files are not tracked by Git (e.g., `.env`, `node_modules/`, `venv/`, uploads).

**Solution:** These files are intentionally gitignored per security and best practices. Refer to `.gitignore` at the project root. Create them manually:

- `backend/.env` — copy from `backend/.env.example`
- `backend/node_modules/` — run `npm install`
- `ai-service/venv/` — run `python -m venv venv` then `pip install -r requirements.txt`

---

## Project Verification

Once all components are running, verify the system end-to-end.

### 1. Backend health check

Open a browser or use `curl`:

```powershell
curl http://localhost:3001/api/health
```

**Expected response:**
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "version": "2.0.0",
    "timestamp": "2026-07-15T...Z"
  }
}
```

**Backend logs should show:**
```
✅ Connected to PostgreSQL (medorbit)
========================================
MedOrbit API Server
Running on port 3001
Environment: development
========================================
```

### 2. AI Service health check

```powershell
curl http://localhost:8001/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "service": "medorbit-ai",
  "version": "2.0.0"
}
```

**AI Service logs should show:**
```
INFO:     Application startup complete.
```

### 3. Ollama verification

```powershell
ollama ps
```

**Expected output:** Shows the loaded model (e.g., `qwen2:7b`).

### 4. Frontend verification

Open `http://localhost:8080/public/` in a browser. You should see:

- The **MedOrbit** branded header with language and theme toggle buttons
- A **chat panel** on the left with a welcome message
- An **interactive map** on the right centered on Nablus
- A category filter bar (All, Clinics, Pharmacies, Hospitals, Doctors)

### 5. Chat endpoint verification

Send a test message to the backend:

```powershell
curl -X POST http://localhost:3001/api/chat/message `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"أقرب صيدلية\", \"latitude\": 32.2211, \"longitude\": 35.2544}'
```

**Expected response:**
```json
{
  "success": true,
  "data": {
    "conversationId": "...",
    "reply": "📍 ...",
    "intent": "find_nearest",
    "confidence": 1,
    "places": [...]
  }
}
```

### 6. Full flow test

1. Open the frontend in your browser.
2. Type "أقرب صيدلية" (or "nearest pharmacy") in the chat input.
3. The chatbot should respond with nearby pharmacies.
4. Results should appear as markers on the map.
5. Clicking a marker should show details (name, address, phone).
6. Toggle between Arabic and English using the language button.
7. Toggle dark mode using the theme button.

---

## Development Notes

### Files that must NOT be committed to Git

The project's `.gitignore` already excludes these, but be aware:

| Pattern                      | Reason                                  |
|------------------------------|-----------------------------------------|
| `**/node_modules/`           | Node package dependencies (generated)   |
| `**/venv/`, `**/.venv/`      | Python virtual environment (generated)  |
| `**/__pycache__/`            | Python bytecode cache (generated)       |
| `**/.env`, `**/.env.*.local` | Sensitive credentials (secrets)         |
| `**/logs/`                   | Application log files                   |
| `backend/storage/chatbot-logs/` | Chatbot conversation logs            |
| `**/uploads/`                | User-uploaded files                     |
| `**/temp/`, `**/tmp/`        | Temporary files                         |
| `*.log`                      | Log files (all extensions)              |
| `.vscode/`                   | IDE-specific settings                   |
| `*.sql.bak`, `*.dump`        | Database backups                        |
| `**/dist/`, `**/build/`      | Build outputs                           |

### `.gitignore` summary

The root `.gitignore` file covers:

- **Dependencies:** `node_modules/`, `yarn.lock`
- **Python:** `venv/`, `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `*.pyc`, `*.pyo`, `*.pyd`
- **Environment:** `.env`, `.env.local`, `.env.*.local` (keeps `.env.example`)
- **Logs:** `logs/`, `*.log`, `npm-debug.log*`
- **OS files:** `.DS_Store`, `Thumbs.db`
- **IDE:** `.vscode/`, `.idea/`
- **Uploads/Temp:** `uploads/`, `temp/`, `tmp/`
- **Database:** `*.sql.bak`, `*.dump`
- **Build:** `dist/`, `build/`, `.next/`, `out/`
- **Coverage:** `coverage/`
- **AI/Assistant:** `.aider*`, `.clinerules`
- **Misc:** `*.swp`, `*.swo`, `*.bak`

### When cloning fresh

After cloning the repository, always run:

```powershell
# Backend
cd backend
copy .env.example .env        # Create .env and edit credentials
npm install

# AI Service
cd ../ai-service
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Database
cd ../database
# Run schema SQL files against PostgreSQL

# Frontend
cd ../frontend
# No build step needed — just serve the static files
```

### Environment variables reference

#### Backend (`backend/.env`)

| Variable                | Default            | Description                                  |
|-------------------------|--------------------|----------------------------------------------|
| `PORT`                  | `3001`             | Backend API server port                      |
| `NODE_ENV`              | `development`      | Environment mode                             |
| `DB_HOST`               | `localhost`        | PostgreSQL host                              |
| `DB_PORT`               | `5432`             | PostgreSQL port                              |
| `DB_NAME`               | `medorbit`         | PostgreSQL database name                     |
| `DB_USER`               | `postgres`         | PostgreSQL user                              |
| `DB_PASSWORD`           | `your_password`    | PostgreSQL password                          |
| `JWT_SECRET`            | (random)           | JWT signing key (min 32 chars)               |
| `JWT_ACCESS_EXPIRES_IN` | `15m`              | Access token expiry                          |
| `JWT_REFRESH_EXPIRES_IN`| `7d`               | Refresh token expiry                         |
| `BCRYPT_ROUNDS`         | `12`               | Password hash rounds                         |
| `CORS_ORIGIN`           | `http://localhost:8080` | Allowed CORS origin for frontend        |
| `AI_SERVICE_URL`        | `http://localhost:8001` | URL of the AI microservice              |
| `AI_SERVICE_TIMEOUT_MS` | `8000`             | AI service request timeout (ms)              |

#### AI Service (environment variables or `ai-service/llm/llm_service.py` defaults)

| Variable       | Default                              | Description                    |
|----------------|--------------------------------------|--------------------------------|
| `OLLAMA_URL`   | `http://localhost:11434/api/generate`| Ollama API endpoint            |
| `OLLAMA_MODEL` | `qwen2:7b`                          | LLM model name for generation  |

---

## Architecture Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│   Backend   │────▶│  AI Service  │
│  (Frontend) │     │  (Express)  │     │  (FastAPI)   │
│ :8080/public│◀────│  :3001      │◀────│  :8001       │
└─────────────┘     └──────┬──────┘     └──────┬──────┘
                           │                   │
                           ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐
                    │ PostgreSQL  │     │   Ollama    │
                    │  :5432      │     │  :11434     │
                    └─────────────┘     └─────────────┘
```

**Data flow:**

1. User sends a message in the frontend chat interface.
2. Frontend sends a POST request to the Backend (`/api/chat/message`).
3. Backend queries conversation history from **PostgreSQL**.
4. Backend forwards the message to the **AI Service** for intent classification, entity extraction, and response generation.
5. AI Service queries **Ollama** (running `qwen2:7b`) for LLM-based responses.
6. AI Service returns structured data (intent, reply, entities) to the Backend.
7. Backend enriches the response with data from **PostgreSQL** (nearby clinics, doctors, etc.) based on the intent.
8. Backend returns the final response to the Frontend.
9. Frontend displays the reply in the chat and renders results on the map.

---

*End of MedOrbit Setup Guide*