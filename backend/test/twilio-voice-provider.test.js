import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizeTwilioStatus } from '../src/providers/twilio-voice-provider.js';

test('normalizeTwilioStatus maps queued and initiated states to calling', () => {
  assert.equal(normalizeTwilioStatus('queued'), 'calling');
  assert.equal(normalizeTwilioStatus('initiated'), 'calling');
});

test('normalizeTwilioStatus maps connected-like states', () => {
  assert.equal(normalizeTwilioStatus('answered'), 'connected');
  assert.equal(normalizeTwilioStatus('in-progress'), 'connected');
});

test('normalizeTwilioStatus maps terminal failure states', () => {
  assert.equal(normalizeTwilioStatus('busy'), 'failed');
  assert.equal(normalizeTwilioStatus('no-answer'), 'failed');
});

test('normalizeTwilioStatus maps completion states', () => {
  assert.equal(normalizeTwilioStatus('completed'), 'completed');
  assert.equal(normalizeTwilioStatus('cancelled'), 'failed');
});
