import admin from 'firebase-admin';

import { config } from './config.js';

function resolveCredential() {
  if (config.firebase.serviceAccountJson) {
    return admin.credential.cert(JSON.parse(config.firebase.serviceAccountJson));
  }

  return admin.credential.applicationDefault();
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: resolveCredential(),
  });
}

export const firestore = admin.firestore();
export { admin };
