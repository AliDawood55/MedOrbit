# MedOrbit Frontend

Chat + Map interface for the MedOrbit Smart Healthcare AI Platform.

## Tech Stack

- **HTML5** + **CSS3** + **Vanilla JavaScript** (no frameworks)
- **Leaflet.js** for interactive maps (OpenStreetMap tiles)
- **Font Awesome** for icons
- **Google Fonts** (Cairo for Arabic, Inter for English)

## File Structure

```
frontend/
├── public/
│   └── index.html              # Main HTML entry
├── src/
│   ├── css/
│   │   ├── main.css            # Layout + theme tokens
│   │   └── chat.css            # Chat panel + map styles
│   └── js/
│       ├── api.js              # API client (POST /api/chat/message)
│       ├── map.js              # Leaflet wrapper (markers, geolocation, coord extraction)
│       ├── chat.js             # Chat UI + message rendering
│       └── app.js              # Entry point + i18n + header wiring
└── README.md
```

## Setup

### 1. Run a local web server

Because we use `fetch` and module-style imports, you need to serve the files via HTTP (not `file://`).

**Option A — Python:**
```bash
cd frontend
python -m http.server 8080
```

**Option B — Node:**
```bash
cd frontend
npx serve -p 8080
```

**Option C — VS Code:** Install the "Live Server" extension and click "Go Live".

### 2. Open the app

```
http://localhost:8080/public/
```

### 3. Configure the backend URL

The frontend expects the backend at `http://localhost:3000/api` by default.

To change it, set `window.MEDORBIT_API_URL` before loading `app.js`:

```html
<script>window.MEDORBIT_API_URL = 'https://api.medorbit.ps/api';</script>
<script src="../src/js/app.js"></script>
```

## API Contract

The frontend calls one endpoint:

```http
POST /api/chat/message
Content-Type: application/json

{
  "message": "أقرب صيدلية",
  "latitude": 32.22,
  "longitude": 35.25
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "reply": "📍 أقرب 5 صيدليات:\n\n1. صيدلية الحياة - 250م - ⭐ 4.5 - 059-1234567 - https://www.google.com/maps?q=32.2211,35.2544\n...",
    "intent": "find_nearest",
    "confidence": 1
  }
}
```

## How It Works

### Flow

1. User types a message in the chat input
2. `chat.js → handleSend()` calls `api.js → sendChatMessage()`
3. `api.js` POSTs to `/api/chat/message` with the message + user GPS (if available)
4. Backend returns `{ reply, intent, confidence }`
5. `chat.js` renders the reply as a message bubble
6. `map.js` parses the reply text:
   - **Structured:** extracts numbered list entries with name/distance/rating/phone/maps URL
   - **Fallback:** uses regex to pull `lat,lng` from any Google Maps link
7. Old clinic markers are cleared, new ones added, map zooms to fit

### Geolocation

- Auto-requested on page load (silently fails if denied)
- Triggered manually with the crosshair button (top-right)
- Optional: clicking the location pin button in chat input

### Marker extraction

The bot's reply may contain Google Maps links. `map.js → extractCoordinatesFromText()` supports:
- `?q=lat,lng`
- `@lat,lng`
- `?ll=lat,lng`

And `extractPlacesFromReply()` parses lines like:
```
1. صيدلية الحياة - 250م - ⭐ 4.5 - 059-1234567 - https://maps.google.com/?q=32.2211,35.2544
```

## Responsive Layout

| Breakpoint | Layout |
|-----------|--------|
| > 900px | Chat (420px) + Map (rest) |
| ≤ 900px | Map (40vh) + Chat (60vh), stacked |
| ≤ 480px | Map (50vh) + Chat (50vh), stacked, mobile-optimized |

## Internationalization

The app supports Arabic (default, RTL) and English (LTR). Toggle via the language button in the header.

## Browser Support

Modern evergreen browsers:
- Chrome 90+
- Firefox 90+
- Safari 14+
- Edge 90+

Geolocation requires HTTPS (or `localhost`).

## Production Build

For production, minify CSS/JS and serve via Nginx:

```nginx
location / {
    root /var/www/medorbit/frontend;
    try_files $uri $uri/ /public/index.html;
}
```

Make sure to set:
- `window.MEDORBIT_API_URL` to the production API URL
- HTTPS enabled (required for Geolocation API)
- Proper CORS headers on the backend
