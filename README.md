# SafeRoute

SafeRoute is a Flutter safety app with SOS activation, real-time rescue coordination, in-app Android SMS alerts, unsafe-zone reporting, journey safety guidance, rescue invite links, and per-user history persistence.

## What This Setup Includes

- Flutter mobile app
- Firebase Auth + Firestore SOS session flow
- Direct in-app Android SMS sending through `MethodChannel`
- Rescue invite links and per-user history persistence
- Journey guard with danger-zone-aware routing

## Flutter App Setup

1. Install Flutter and Android Studio.
2. Add your Firebase Android/iOS config files as usual.
3. Fetch packages:

```bash
flutter pub get
```

4. Run the app:

```bash
flutter run
```

## Optional Backend Setup

The backend lives in [`backend/`](backend). Voice/calling APIs are currently disabled, so the backend is optional and only exposes a health endpoint.

1. Install Node.js 18+.
2. Copy the environment template:

```bash
cd backend
copy .env.example .env
```

3. Fill in the environment variables:

```env
PORT=8080
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"your-project-id"}
```

4. Install backend dependencies and start the server:

```bash
npm install
npm start
```

## Backend Endpoints

- `GET /health`

## Runtime Behavior

When SOS is triggered:

1. SOS session activation completes first.
2. Existing enriched Android SMS sending starts in the background and remains non-blocking.
3. Rescue and map/session coordination continue normally.
4. The app stays on the SOS Active experience until the user marks safe.

## Safety / Compliance Notes

- Android SMS uses the existing in-app direct SMS `MethodChannel`.
- The current app does not include any backend-driven voice/calling feature.
- Rescue invite links remain available for trusted helpers.

## Tests

Flutter test:

```bash
flutter test test/journey_safety_service_test.dart
```

Backend tests:

```bash
cd backend
npm test
```
