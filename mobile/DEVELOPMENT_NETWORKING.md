# MedOrbit mobile — development networking

How the Flutter app finds the backend and the AI service, and what has to change
before a production build.

## Two separate services

| Service | Port | Base path | Auth |
|---|---|---|---|
| Node backend | 3001 | **`/api`** | JWT bearer + refresh |
| Python AI service | 8001 | **none** (routes at root) | none today |

They are separate processes. `AppConfig.aiBaseFrom()` derives the AI origin from
whichever backend host resolved, so both stay on the same machine, and it never
carries the `/api` prefix.

## Host resolution

`ApiHostResolver` probes `GET <candidate>/health` at startup and keeps the first
host that answers. Without a build-time override the candidates are, in order:

1. `http://192.168.0.105:3001/api` — the dev laptop's Wi-Fi LAN IP. **The only
   candidate a physical device can reach.**
2. `http://10.0.2.2:3001/api` — the Android emulator's alias for the host loopback.
3. `http://localhost:3001/api` — desktop/web debug builds on the host itself.

The last two always fail from a real phone (they resolve to the phone), so they
exist to let one build work across all three targets — not as a recovery path.

The resolver repoints both the main Dio and the auth refresh client, so a
fallback host does not leave `/auth/refresh` aimed at the primary.

## Pointing a build somewhere else

No source edit needed. Both origins are `--dart-define` overrides:

```powershell
flutter run -d <device> `
  --dart-define=MEDORBIT_API_URL=https://api.example `
  --dart-define=MEDORBIT_AI_URL=https://ai.example
```

- `MEDORBIT_API_URL` is normalised to end in exactly one `/api`, so passing it
  with or without the suffix both work.
- `MEDORBIT_AI_URL` has any trailing `/api` stripped.
- When `MEDORBIT_API_URL` is set, the emulator and localhost candidates are
  **dropped** — a configured host is the only host that build will talk to.

## Cleartext traffic

`android:usesCleartextTraffic="true"` used to apply to every build type,
including release. It is replaced by
`android/app/src/main/res/xml/network_security_config.xml`, which is TLS-only by
default and allowlists cleartext for the three development hosts above.

Effect: `flutter run` and `flutter run --release` both still work against the LAN
backend, and no other origin can be reached over plain HTTP.

If your LAN IP is not `192.168.0.105`, update **both** `AppConfig.devLanBaseUrl`
and the `domain-config` block in that XML, or use the `--dart-define` override
with an HTTPS origin instead.

## AI service reachability (port 8001)

The AI service being unreachable while the backend is fine is the common failure,
because they are different ports and Windows firewall treats them separately.
Symptom before this was fixed: Virtual Doctor failed with a connection timeout
~15s into `/virtual-doctor/start`, *after* prompting for the microphone.

The app now preflights `GET /health` on the AI service before starting a
consultation, so an unreachable service produces an immediate, non-technical
"AI service is currently unavailable" message and never asks for the microphone.

To check reachability by hand:

```powershell
curl.exe http://192.168.0.105:3001/api/health     # backend
curl.exe http://192.168.0.105:8001/health          # AI service

# From the phone itself:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <device> shell "toybox nc -z -w 3 192.168.0.105 8001"
$LASTEXITCODE   # 0 = reachable
```

If the backend answers but the AI service does not, check that the Windows
firewall rule for port 8001 allows the **Private** network profile.

## Before a production build

- Serve both services over HTTPS behind a reverse proxy and pass those origins
  via the two defines. The plain-HTTP defaults will not work once the dev hosts
  are removed from the network security config, and iOS ATS blocks cleartext
  regardless.
- The AI service currently has no authentication and wildcard CORS. It must sit
  behind an authenticated gateway before it is reachable beyond the dev LAN.
- Android `applicationId`/`namespace` and the iOS bundle identifier are still the
  `com.example.*` placeholder, and the release build type is signed with the
  debug keystore. Both must be resolved before distribution.
