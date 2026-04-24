import { config } from '../config.js';
import { TwilioVoiceProvider } from './twilio-voice-provider.js';

export function createVoiceProvider() {
  switch (config.voiceProvider) {
    case 'twilio':
      return new TwilioVoiceProvider();
    default:
      throw new Error(`Unsupported voice provider: ${config.voiceProvider}`);
  }
}
