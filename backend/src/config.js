import 'dotenv/config';

function readRequired(name, fallback = '') {
  return (process.env[name] ?? fallback).toString().trim();
}

export const config = {
  port: Number(process.env.PORT ?? 8080),
  voiceProvider: readRequired('VOICE_PROVIDER', 'twilio'),
  twilio: {
    accountSid: readRequired('TWILIO_ACCOUNT_SID'),
    authToken: readRequired('TWILIO_AUTH_TOKEN'),
    phoneNumber: readRequired('TWILIO_PHONE_NUMBER'),
    webhookUrl: readRequired('TWILIO_WEBHOOK_URL'),
  },
  firebase: {
    serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim() ?? '',
  },
};

export function isVoiceConfigured() {
  if (config.voiceProvider !== 'twilio') {
    return false;
  }

  return Boolean(
    config.twilio.accountSid &&
        config.twilio.authToken &&
        config.twilio.phoneNumber &&
        config.twilio.webhookUrl,
  );
}
