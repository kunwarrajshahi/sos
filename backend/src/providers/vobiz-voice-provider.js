import { config } from '../config.js';
import { VoiceProvider } from './voice-provider.js';

const CALL_ENDPOINT = '/voice/calls';

function normalizeStatus(rawStatus) {
  const status = (rawStatus ?? '').toString().trim().toLowerCase();
  switch (status) {
    case 'ringing':
    case 'initiated':
      return 'ringing';
    case 'answered':
    case 'connected':
    case 'in-progress':
    case 'in_progress':
      return 'connected';
    case 'busy':
    case 'no-answer':
    case 'no_answer':
    case 'failed':
    case 'rejected':
      return 'failed';
    case 'completed':
    case 'canceled':
    case 'cancelled':
    case 'ended':
      return 'completed';
    default:
      return status || 'unknown';
  }
}

export class VobizVoiceProvider extends VoiceProvider {
  constructor(fetchImpl = fetch) {
    super('vobiz');
    this._fetch = fetchImpl;
  }

  get isConfigured() {
    return Boolean(
      config.vobiz.apiKey &&
          config.vobiz.apiSecret &&
          config.vobiz.baseUrl &&
          config.vobiz.callerId &&
          config.vobiz.webhookUrl,
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
      throw new Error('Vobiz voice provider is not configured.');
    }

    const body = {
      from: config.vobiz.callerId,
      to: contactNumber,
      webhookUrl: config.vobiz.webhookUrl,
      metadata: {
        sessionId,
        victimName,
        victimPhone,
        ...metadata,
      },
    };

    // TODO: Confirm the official Vobiz outbound-calling endpoint path and
    // request/response contract. `CALL_ENDPOINT` is an adaptable placeholder.
    const response = await this._fetch(
      `${config.vobiz.baseUrl.replace(/\/$/, '')}${CALL_ENDPOINT}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.vobiz.apiKey,
          'x-api-secret': config.vobiz.apiSecret,
        },
        body: JSON.stringify(body),
      },
    );

    if (!response.ok) {
      throw new Error(`Vobiz start call failed with status ${response.status}`);
    }

    const payload = await response.json();
    return {
      providerCallId:
          payload.callId?.toString() ??
          payload.id?.toString() ??
          payload.data?.callId?.toString() ??
          '',
      raw: payload,
    };
  }

  async getCallStatus({ providerCallId }) {
    if (!this.isConfigured) {
      throw new Error('Vobiz voice provider is not configured.');
    }

    // TODO: Confirm the official Vobiz status endpoint path.
    const response = await this._fetch(
      `${config.vobiz.baseUrl.replace(/\/$/, '')}${CALL_ENDPOINT}/${providerCallId}`,
      {
        method: 'GET',
        headers: {
          'x-api-key': config.vobiz.apiKey,
          'x-api-secret': config.vobiz.apiSecret,
        },
      },
    );

    if (!response.ok) {
      throw new Error(`Vobiz getCallStatus failed with status ${response.status}`);
    }

    const payload = await response.json();
    return {
      status: normalizeStatus(payload.status ?? payload.callStatus),
      raw: payload,
    };
  }

  async endCall({ providerCallId }) {
    if (!this.isConfigured) {
      throw new Error('Vobiz voice provider is not configured.');
    }

    // TODO: Confirm the official Vobiz hangup endpoint path.
    const response = await this._fetch(
      `${config.vobiz.baseUrl.replace(/\/$/, '')}${CALL_ENDPOINT}/${providerCallId}/end`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.vobiz.apiKey,
          'x-api-secret': config.vobiz.apiSecret,
        },
      },
    );

    if (!response.ok) {
      throw new Error(`Vobiz endCall failed with status ${response.status}`);
    }

    return {
      providerCallId,
      raw: await response.json().catch(() => ({})),
    };
  }

  async handleWebhook(payload) {
    const providerCallId =
        payload.callId?.toString() ??
        payload.id?.toString() ??
        payload.call?.id?.toString() ??
        '';
    const sessionId =
        payload.sessionId?.toString() ??
        payload.metadata?.sessionId?.toString() ??
        payload.customData?.sessionId?.toString() ??
        '';
    const currentContact =
        payload.to?.toString() ??
        payload.call?.to?.toString() ??
        payload.destination?.toString() ??
        '';

    return {
      providerCallId,
      sessionId,
      currentContact,
      status: normalizeStatus(
        payload.event ?? payload.status ?? payload.callStatus,
      ),
      raw: payload,
    };
  }
}

export { normalizeStatus as normalizeVobizStatus };
