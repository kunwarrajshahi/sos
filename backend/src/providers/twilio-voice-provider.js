import { config } from '../config.js';
import { VoiceProvider } from './voice-provider.js';

const TWILIO_CALLS_ENDPOINT = '/2010-04-01/Accounts';

function normalizeStatus(rawStatus) {
  const status = (rawStatus ?? '').toString().trim().toLowerCase();
  switch (status) {
    case 'queued':
    case 'initiated':
      return 'calling';
    case 'ringing':
      return 'ringing';
    case 'in-progress':
    case 'in_progress':
    case 'answered':
      return 'connected';
    case 'busy':
    case 'failed':
    case 'no-answer':
    case 'no_answer':
    case 'canceled':
    case 'cancelled':
      return 'failed';
    case 'completed':
      return 'completed';
    default:
      return status || 'unknown';
  }
}

function toBasicAuthToken(accountSid, authToken) {
  return Buffer.from(`${accountSid}:${authToken}`).toString('base64');
}

function toFormUrlEncoded(payload) {
  const params = new URLSearchParams();
  Object.entries(payload).forEach(([key, value]) => {
    if (value != null && value.toString().trim().length > 0) {
      params.append(key, value.toString());
    }
  });
  return params;
}

export class TwilioVoiceProvider extends VoiceProvider {
  constructor(fetchImpl = fetch) {
    super('twilio');
    this._fetch = fetchImpl;
  }

  get isConfigured() {
    return Boolean(
      config.twilio.accountSid &&
          config.twilio.authToken &&
          config.twilio.phoneNumber &&
          config.twilio.webhookUrl,
    );
  }

  async startEmergencyCall({
    sessionId,
    contactNumber,
    victimName,
    victimPhone,
    metadata = {},
  }) {
    if (!this.isConfigured) {
      throw new Error('Twilio voice provider is not configured.');
    }

    const form = toFormUrlEncoded({
      To: contactNumber,
      From: config.twilio.phoneNumber,
      Url: config.twilio.webhookUrl,
      Method: 'POST',
      StatusCallback: config.twilio.webhookUrl,
      StatusCallbackMethod: 'POST',
      StatusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'].join(
        ' ',
      ),
    });

    if ((sessionId ?? '').toString().trim().length > 0) {
      form.append(
        'StatusCallback',
        `${config.twilio.webhookUrl}?sessionId=${encodeURIComponent(sessionId)}`,
      );
      form.append(
        'Url',
        `${config.twilio.webhookUrl}?sessionId=${encodeURIComponent(sessionId)}`,
      );
    }
    if ((victimName ?? '').toString().trim().length > 0) {
      form.append('MachineDetection', 'Enable');
    }
    Object.entries(metadata).forEach(([key, value]) => {
      if (value != null) {
        form.append(`SipHeader_X-SafeRoute-${key}`, value.toString());
      }
    });
    if ((victimPhone ?? '').toString().trim().length > 0) {
      form.append('SipHeader_X-SafeRoute-VictimPhone', victimPhone.toString());
    }
    if ((victimName ?? '').toString().trim().length > 0) {
      form.append('SipHeader_X-SafeRoute-VictimName', victimName.toString());
    }

    const endpoint =
        `https://api.twilio.com${TWILIO_CALLS_ENDPOINT}/${config.twilio.accountSid}/Calls.json`;

    const response = await this._fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${toBasicAuthToken(
          config.twilio.accountSid,
          config.twilio.authToken,
        )}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form,
    });

    if (!response.ok) {
      throw new Error(`Twilio start call failed with status ${response.status}`);
    }

    const payload = await response.json();
    return {
      providerCallId: payload.sid?.toString() ?? '',
      raw: payload,
    };
  }

  async getCallStatus({ providerCallId }) {
    if (!this.isConfigured) {
      throw new Error('Twilio voice provider is not configured.');
    }

    const endpoint =
        `https://api.twilio.com${TWILIO_CALLS_ENDPOINT}/${config.twilio.accountSid}/Calls/${providerCallId}.json`;

    const response = await this._fetch(endpoint, {
      method: 'GET',
      headers: {
        Authorization: `Basic ${toBasicAuthToken(
          config.twilio.accountSid,
          config.twilio.authToken,
        )}`,
      },
    });

    if (!response.ok) {
      throw new Error(`Twilio getCallStatus failed with status ${response.status}`);
    }

    const payload = await response.json();
    return {
      status: normalizeStatus(payload.status),
      raw: payload,
    };
  }

  async endCall({ providerCallId }) {
    if (!this.isConfigured) {
      throw new Error('Twilio voice provider is not configured.');
    }

    const endpoint =
        `https://api.twilio.com${TWILIO_CALLS_ENDPOINT}/${config.twilio.accountSid}/Calls/${providerCallId}.json`;

    const response = await this._fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${toBasicAuthToken(
          config.twilio.accountSid,
          config.twilio.authToken,
        )}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({'Status': 'completed'}),
    });

    if (!response.ok) {
      throw new Error(`Twilio endCall failed with status ${response.status}`);
    }

    return {
      providerCallId,
      raw: await response.json().catch(() => ({})),
    };
  }

  async handleWebhook(payload) {
    const providerCallId =
        payload.CallSid?.toString() ??
        payload.CallSid?.toString() ??
        payload.callSid?.toString() ??
        '';
    const sessionId =
        payload.sessionId?.toString() ??
        payload.SessionId?.toString() ??
        payload.CustomParameters?.sessionId?.toString() ??
        '';
    const currentContact =
        payload.To?.toString() ??
        payload.to?.toString() ??
        payload.Called?.toString() ??
        '';

    return {
      providerCallId,
      sessionId,
      currentContact,
      status: normalizeStatus(payload.CallStatus ?? payload.callStatus),
      raw: payload,
    };
  }

  buildTwimlResponse({ victimName, sessionId }) {
    const safeName =
        (victimName ?? '').toString().trim().length > 0
          ? victimName.toString().trim()
          : 'A SafeRoute user';
    const sessionMessage = sessionId ? ` Session ${sessionId}.` : '';
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say voice="alice">This is SafeRoute emergency calling. ${safeName} needs help.${sessionMessage} Please stay on the line while we connect the emergency response flow.</Say>
  <Pause length="60"/>
</Response>`;
  }
}

export { normalizeStatus as normalizeTwilioStatus };
