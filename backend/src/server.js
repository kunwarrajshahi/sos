import cors from 'cors';
import express from 'express';

import { config } from './config.js';

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'saferoute-backend',
    callingEnabled: false,
  });
});

app.listen(config.port, () => {
  console.log(`[SafeRoute Backend] Listening on port ${config.port}.`);
});
