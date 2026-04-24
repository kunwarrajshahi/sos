export class VoiceProvider {
  constructor(name) {
    this.name = name;
  }

  async startEmergencyCall() {
    throw new Error('startEmergencyCall() must be implemented by the provider.');
  }

  async getCallStatus() {
    throw new Error('getCallStatus() must be implemented by the provider.');
  }

  async endCall() {
    throw new Error('endCall() must be implemented by the provider.');
  }

  async handleWebhook() {
    throw new Error('handleWebhook() must be implemented by the provider.');
  }
}
