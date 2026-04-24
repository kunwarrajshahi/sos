# SafeRoute

SafeRoute is a Flutter safety app with SOS activation, real-time rescue coordination, in-app Android SMS alerts, unsafe-zone reporting, and a provider-switchable emergency voice-calling backend.

## What This Setup Includes

- Flutter mobile app
- Firebase Auth + Firestore SOS session flow
- Direct in-app Android SMS sending through `MethodChannel`
- Parallel backend-driven emergency calling flow
- Twilio voice-provider adapter with webhook handling
- Rescue invite links and per-user history persistence

## Flutter App Setup

1. Install Flutter and Android Studio.
2. Add your Firebase Android/iOS config files as usual.
3. Fetch packages:

```bash
flutter pub get
```

4. Run the app and point it to the voice backend:

```bash
flutter run --dart-define=SOS_BACKEND_BASE_URL=http://10.0.2.2:8080
```

`SOS_BACKEND_BASE_URL` is optional. If omitted, the app keeps the current SOS + SMS flow and safely falls back to the device calling path only after backend retries are exhausted.

## Voice Backend Setup

The backend lives in [`backend/`](backend).

1. Install Node.js 18+.
2. Copy the environment template:

```bash
cd backend
copy .env.example .env
```

3. Fill in the environment variables:

```env
PORT=8080
VOICE_PROVIDER=twilio
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your-twilio-auth-token
TWILIO_PHONE_NUMBER=+15551234567
TWILIO_WEBHOOK_URL=https://your-domain.example.com/voice/webhook
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"your-project-id"}
```

4. Install backend dependencies and start the server:

```bash
npm install
npm start
```

## Backend Endpoints

- `POST /sos/trigger`
- `GET /sos/active`
- `POST /sos/:id/start-call`
- `GET /sos/:id/call-status`
- `POST /sos/:id/safe`
- `POST /sos/:id/end-call`
- `POST /sos/:id/location`
- `POST /voice/webhook`

## Voice Provider Notes

- `TwilioVoiceProvider` is the primary adapter.
- The provider implementation is intentionally switchable so Vobiz, Exotel, or Plivo can be added later without changing SOS logic.
- Twilio uses:
  - `POST /2010-04-01/Accounts/{AccountSid}/Calls.json`
  - status polling on the call SID
  - `POST /voice/webhook` for Twilio status callbacks and TwiML instructions
- Credentials are read only from environment variables. Nothing is hardcoded.
- Twilio trial accounts can call only verified numbers. Add your emergency contacts in the Twilio console before testing.

## Runtime Behavior

When SOS is triggered:

1. SOS session activation completes first.
2. Existing enriched Android SMS sending starts in the background and remains non-blocking.
3. Voice calling starts in parallel through the backend.
4. The app stays on the SOS Active experience.
5. Call state is restored across app restart when the SOS session is still active.

## Safety / Compliance Notes

- The app does not bypass OS-level call UI rules.
- Android SMS still uses the existing in-app direct SMS `MethodChannel`.
- Voice calling is backend-driven and should be integrated with platform-compliant Android/iOS calling surfaces where needed for production deployments.
- Android device-call fallback now prefers `ACTION_CALL` when `CALL_PHONE` permission is granted and falls back to `ACTION_DIAL` otherwise.

## Tests

Flutter test:

```bash
flutter test test/sos_call_backend_service_test.dart
```

Backend tests:

```bash
cd backend
npm test
```
