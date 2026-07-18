# MedOrbit Setup Guide

> **MedOrbit – Smart Healthcare AI Platform**
>
> A graduation project by:
> - **Ali Ghassan**
> - **Omar Abumazen**

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Tree](#project-tree)
3. [Required Software](#required-software)
4. [First-Time Setup](#first-time-setup)
5. [Environment Variables](#environment-variables)
6. [Startup Commands](#startup-commands)
7. [Database Setup](#database-setup)
8. [Troubleshooting](#troubleshooting)
9. [Rebuild Instructions](#rebuild-instructions)

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

## Project Tree

```
MedOrbit/                          # Root workspace
│
├── .env                           # Shared environment variables (gitignored)
├── .gitignore                     # Git exclusion rules
├── package.json                   # Root npm scripts (dev, install, db:migrate)
├── requirements.txt               # Root Python dependencies (shared by ai-service)
│
├── backend/                       # Node.js + Express API server
│   ├── server.js                  # Entry point
│   ├── package.json               # Backend Node dependencies
│   ├── .env.example               # Environment variable template
│   └── src/
│       ├── app.js                 # Express app setup
│       ├── config/
│       │   ├── env.js             # Loads root .env automatically
│       │   └── database.js        # PostgreSQL connection pool
│       ├── routes/                # API routes
│       ├── controllers/           # Route handlers
│       ├── services/              # Business logic
│       ├── middleware/            # Auth, error handling
│       └── repositories/         # Data access layer
│
├── ai-service/                    # Python FastAPI AI microservice
│   ├── db.py                     # DB pool (loads root .env)
│   ├── chatbot/
│   │   ├── main.py               # FastAPI app (entry point)
│   │   ├── intent/               # Intent classifier
│   │   ├── entities/             # Entity extractor
│   │   ├── medical/              # Medical modules (symptom engine, drug checker, OCR, summarizer)
│   │   ├── nlu/                  # NLU pipeline
│   │   └── utils/                # Text normalizer
│   ├── llm/                      # LLM service (Ollama integration)
│   ├── rag/                      # Retrieval-Augmented Generation
│   └── data/                     # Data files
│
├── frontend/                      # Static HTML/CSS/JS frontend
│   ├── public/
│   │   └── index.html            # Main entry point
│   └── src/
│       ├── css/                  # Stylesheets
│       ├── js/                   # JavaScript modules
│       └── utils/                # Utility functions
│
├── database/                      # Original SQL files (preserved)
│   ├── schema/                   # Schema files
│   ├── migrations/               # Migration scripts
│   └── seed/                     # Seed data
│
├── db/                            # Consolidated SQL (recommended for fresh installs)
│   ├── 00_extensions.sql         # Extensions (uuid-ossp, pgcrypto, postgis)
│   ├── 01_base_tables.sql        # Base tables (users, specialties, clinics, etc.)
│   ├── 02_dependent_tables.sql   # FK-dependent tables (25 total)
│   ├── 03_indexes.sql            # All indexes
│   ├── 04_triggers_sequences.sql # Triggers, sequences, functions
│   ├── 05_views.sql              # v_doctor_ratings, v_upcoming_appointments, v_patient_summary
│   └── 06_seed_data.sql          # All seed data
│
├── docs/                          # Documentation
│   └── PROJECT_SETUP.md          # This file
│
└── tempData/                      # Temporary data (images, etc.)
```

---

## Required Software

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

## First-Time Setup

### 1. Clone the repository

```powershell
git clone https://github.com/AliDawood55/MedOrbit.git
cd MedOrbit
```

### 2. Create the environment file

```powershell
copy backend\.env.example .env
```

Then edit `.env` to match your local configuration (especially `DB_PASSWORD`).

### 3. Install Node.js dependencies

```powershell
npm install
```

This runs `cd backend && npm install` automatically (installs Express, pg, dotenv, axios, etc.).

### 4. Install Python dependencies

```powershell
npm run install:python
```

Or manually:

```powershell
python -m pip install -r requirements.txt
```

### 5. Set up the database

Create the database:

```powershell
psql -U postgres -c "CREATE DATABASE medorbit;"
```

Run all migrations from the consolidated `db/` folder:

```powershell
npm run db:migrate
```

This executes all 7 SQL files in order (extensions → base tables → dependent tables → indexes → triggers → views → seed data).

### 6. Pull the Ollama model

```powershell
ollama pull qwen2:7b
```

---

## Environment Variables

All environment variables are stored in a single root `.env` file. Both the backend and AI service load from this file automatically.

| Variable                | Default            | Description                                  |
|-------------------------|--------------------|----------------------------------------------|
| `PORT`                  | `3001`             | Backend API server port                      |
| `NODE_ENV`              | `development`      | Environment mode                             |
| `DB_HOST`               | `localhost`        | PostgreSQL host                              |
| `DB_PORT`               | `5432`             | PostgreSQL port                              |
| `DB_NAME`               | `medorbit`         | PostgreSQL database name                     |
| `DB_USER`               | `postgres`         | PostgreSQL user                              |
| `DB_PASSWORD`           | `052963`           | PostgreSQL password                          |
| `JWT_SECRET`            | (set in .env)      | JWT signing key (min 32 chars)               |
| `JWT_ACCESS_EXPIRES_IN` | `15m`              | Access token expiry                          |
| `JWT_REFRESH_EXPIRES_IN`| `7d`               | Refresh token expiry                         |
| `BCRYPT_ROUNDS`         | `12`               | Password hash rounds                         |
| `CORS_ORIGIN`           | `http://localhost:8080` | Allowed CORS origin for frontend        |
| `AI_SERVICE_URL`        | `http://localhost:8001` | URL of the AI microservice              |
| `AI_SERVICE_TIMEOUT_MS` | `90000`            | AI service request timeout (ms)              |
| `OLLAMA_URL`            | `http://localhost:11434/api/generate` | Ollama API endpoint        |
| `OLLAMA_MODEL`          | `qwen2:7b`         | LLM model name for generation                |

---

## Startup Commands

All commands run from the project root (`C:\Projects\MedOrbit`).

### Start all services (AI + Backend + Frontend)

```powershell
npm run dev
```

This uses `concurrently` to run all three services in parallel with color-coded output.

### Start individual services

**Backend only:**

```powershell
npm run dev:backend
```

**AI Service only:**

```powershell
npm run dev:ai
```

**Frontend only:**

```powershell
npm run dev:frontend
```

**Ollama (if not already running):**

```powershell
npm run dev:ollama
```

### Manual startup (without npm)

**Backend:**

```powershell
cd backend
npm run dev
```

**AI Service:**

```powershell
cd ai-service
uvicorn chatbot.main:app --reload --host 127.0.0.1 --port 8001
```

**Frontend:**

```powershell
cd frontend
python -m http.server 8080
```

**Ollama:**

```powershell
ollama serve
```

### Startup order

```
1. PostgreSQL     → Verify with: psql -U postgres -c "SELECT 1;"
2. Ollama         → Verify with: ollama ps
3. AI Service     → Verify with: curl http://localhost:8001/health
4. Backend        → Verify with: curl http://localhost:3001/api/health
5. Frontend       → Open: http://localhost:8080/public/
```

---

## Ports

| Service       | Port  | URL                             | Notes                          |
|---------------|-------|---------------------------------|--------------------------------|
| **Backend**   | 3001  | `http://localhost:3001`         | Express API server             |
| **AI Service**| 8001  | `http://localhost:8001`         | FastAPI microservice           |
| **Ollama**    | 11434 | `http://localhost:11434`        | Local LLM inference            |
| **Frontend**  | 8080  | `http://localhost:8080/public/` | Static file server (Python)    |

---

## Database Setup

### Fresh install (recommended)

```powershell
# Create database
psql -U postgres -c "CREATE DATABASE medorbit;"

# Run consolidated migrations
npm run db:migrate
```

### Run seed data only

```powershell
npm run db:seed
```

### Individual SQL files

If you prefer to run files manually:

```powershell
psql -U postgres -d medorbit -f db/00_extensions.sql
psql -U postgres -d medorbit -f db/01_base_tables.sql
psql -U postgres -d medorbit -f db/02_dependent_tables.sql
psql -U postgres -d medorbit -f db/03_indexes.sql
psql -U postgres -d medorbit -f db/04_triggers_sequences.sql
psql -U postgres -d medorbit -f db/05_views.sql
psql -U postgres -d medorbit -f db/06_seed_data.sql
```

### Verify the database

```powershell
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM clinics;"
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM doctors;"
psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM specialties;"
```

---

## Troubleshooting

### ❌ `ModuleNotFoundError: No module named 'requests'`

**Solution:**

```powershell
python -m pip install requests
```

### ❌ `Port already in use`

**Solution:**

```powershell
netstat -ano | findstr :3001
taskkill /PID <PID> /F
```

### ❌ `Backend cannot connect to AI Service`

**Solution:**

1. Ensure the AI service is running: `curl http://localhost:8001/health`
2. Check `AI_SERVICE_URL` in `.env` is `http://localhost:8001`

### ❌ `AI cannot connect to Ollama`

**Solution:**

1. Ensure Ollama is running: `ollama ps`
2. Check the model is pulled: `ollama list`
3. Pull if missing: `ollama pull qwen2:7b`

### ❌ `Database connection failed`

**Solution:**

1. Verify PostgreSQL is running.
2. Check credentials in `.env` match your local PostgreSQL setup.
3. Test: `psql -U postgres -d medorbit -c "SELECT 1;"`

### ❌ `Node modules missing`

**Solution:**

```powershell
npm install
```

### ❌ `Python virtual environment missing`

**Solution:**

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

---

## Rebuild Instructions

If you need to reset the entire project:

```powershell
# 1. Drop and recreate the database
psql -U postgres -c "DROP DATABASE IF EXISTS medorbit;"
psql -U postgres -c "CREATE DATABASE medorbit;"

# 2. Reinstall Node dependencies
Remove-Item -Path "backend\node_modules" -Recurse -Force -ErrorAction SilentlyContinue
npm install

# 3. Reinstall Python dependencies
Remove-Item -Path ".venv" -Recurse -Force -ErrorAction SilentlyContinue
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt

# 4. Run database migrations
npm run db:migrate

# 5. Pull Ollama model
ollama pull qwen2:7b

# 6. Start all services
npm run dev
```

---

## Project Verification

### Backend health check

```powershell
curl http://localhost:3001/api/health
```

**Expected:**
```json
{"success":true,"data":{"status":"healthy","version":"2.0.0","timestamp":"..."}}
```

### AI Service health check

```powershell
curl http://localhost:8001/health
```

**Expected:**
```json
{"status":"healthy","service":"medorbit-ai","version":"3.0.0"}
```

### Chat endpoint test

```powershell
curl -X POST http://localhost:3001/api/chat/message `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"أقرب صيدلية\", \"latitude\": 32.2211, \"longitude\": 35.2544}'
```

### Frontend

Open `http://localhost:8080/public/` in a browser. You should see the MedOrbit chat interface with an interactive map.

---

*End of MedOrbit Setup Guide*