import cors from 'cors';
import express from 'express';

import { config } from './config.js';
import { firestore } from './firebase.js';
import { createVoiceProvider } from './providers/provider-factory.js';
import { SosCallService } from './services/sos-call-service.js';

const app = express();
const voiceProvider = createVoiceProvider();
const sosCallService = new SosCallService({
  firestore,
  voiceProvider,
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    provider: voiceProvider.name,
  });
});

app.post('/sos/trigger', async (req, res) => {
  try {
    const payload = await sosCallService.triggerSos({
      sessionId: req.body.sessionId,
      userId: req.body.userId,
      victimName: req.body.victimName,
      victimPhone: req.body.victimPhone,
      emergencyContacts: req.body.emergencyContacts ?? [],
      location: req.body.location,
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get('/sos/active', async (req, res) => {
  try {
    const payload = await sosCallService.getActiveCall({
      userId: req.query.userId?.toString() ?? '',
    });
    if (!payload) {
      res.status(404).json({ error: 'No active SOS call session found.' });
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.post('/sos/:id/start-call', async (req, res) => {
  try {
    const payload = await sosCallService.startCall({
      sessionId: req.params.id,
      userId: req.body.userId,
      victimName: req.body.victimName,
      victimPhone: req.body.victimPhone,
      emergencyContacts: req.body.emergencyContacts ?? [],
      location: req.body.location,
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get('/sos/:id/call-status', async (req, res) => {
  try {
    const payload = await sosCallService.getCallStatus({
      sessionId: req.params.id,
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(404).json({ error: error.message });
  }
});

app.post('/sos/:id/safe', async (req, res) => {
  try {
    const payload = await sosCallService.markSafe({
      sessionId: req.params.id,
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.post('/sos/:id/end-call', async (req, res) => {
  try {
    const payload = await sosCallService.endCall({
      sessionId: req.params.id,
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.post('/sos/:id/location', async (req, res) => {
  try {
    await sosCallService.syncLocation({
      sessionId: req.params.id,
      location: req.body.location,
    });
    res.status(204).send();
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.post('/voice/webhook', async (req, res) => {
  try {
    const payload = await sosCallService.handleWebhook(req.body ?? {}, req.query ?? {});
    if (payload?.twiml) {
      res.status(200).type('text/xml').send(payload.twiml);
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.listen(config.port, () => {
  console.log(
    `[SafeRoute Voice Backend] Listening on port ${config.port} using ${voiceProvider.name}.`,
  );
});
