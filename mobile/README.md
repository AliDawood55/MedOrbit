# MedOrbit Mobile

The Flutter mobile client for MedOrbit, designed to provide mobile access to
the platform's healthcare services through the MedOrbit backend API.

## Tech

- **Flutter** (Dart). See [`pubspec.yaml`](pubspec.yaml) for the project's SDK
  and dependency constraints.
- Talks to the MedOrbit Express API; it does not call the AI service directly.

## Running

```
flutter pub get
flutter run
```

The app needs a reachable backend. For pointing an emulator or a physical
device at a local or staging backend, see
[`DEVELOPMENT_NETWORKING.md`](DEVELOPMENT_NETWORKING.md).

## Layout

- `lib/` — application code (features, core services, storage).
- `test/` — widget and unit tests (`flutter test`).
- Platform runners: `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`.
