const DEFAULT_MAX_RETRIES_PER_CONTACT = 2;

function nowIso() {
  return new Date().toISOString();
}

function toNonEmptyStrings(values = []) {
  return values
    .map((value) => value?.toString().trim() ?? '')
    .filter((value) => value.length > 0);
}

function buildStatusText(status, currentContact) {
  switch (status) {
    case 'initializing':
      return 'Initializing call...';
    case 'calling':
      return currentContact
        ? `Calling emergency contact ${currentContact}...`
        : 'Calling emergency contacts...';
    case 'ringing':
      return 'Call ringing...';
    case 'connected':
      return 'Call connected';
    case 'retrying':
      return 'Call failed, retrying...';
    case 'safe':
      return 'SOS marked safe. Call controls unlocked.';
    case 'ended':
      return 'Emergency call ended';
    case 'resolved':
      return 'Emergency SOS resolved';
    case 'failed':
      return 'Emergency calling failed';
    default:
      return 'Calling emergency contacts...';
  }
}

export class SosCallService {
  constructor({ firestore, voiceProvider, logger = console }) {
    this.firestore = firestore;
    this.voiceProvider = voiceProvider;
    this.logger = logger;
  }

  async triggerSos({
    sessionId,
    userId,
    victimName,
    victimPhone,
    emergencyContacts,
    location,
  }) {
    const docRef = this._doc(sessionId);
    await docRef.set(
      {
        sessionId,
        uid: userId,
        active: true,
        status: 'active',
        victim: {
          lat: location?.lat ?? null,
          lng: location?.lng ?? null,
          lastUpdated: nowIso(),
        },
      },
      { merge: true },
    );

    return this.startCall({
      sessionId,
      userId,
      victimName,
      victimPhone,
      emergencyContacts,
      location,
    });
  }

  async startCall({
    sessionId,
    userId,
    victimName,
    victimPhone,
    emergencyContacts,
    location,
  }) {
    const docRef = this._doc(sessionId);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new Error(`SOS session ${sessionId} does not exist.`);
    }

    const data = snapshot.data() ?? {};
    if (data.active != true || data.status === 'completed') {
      throw new Error(`SOS session ${sessionId} is not active.`);
    }

    const contacts = toNonEmptyStrings(emergencyContacts);
    if (contacts.length == 0) {
      throw new Error('No emergency contacts available for calling.');
    }

    const existingWorkflow = this._workflowFrom(data);
    if (
      existingWorkflow.isCallActive === true &&
      ['calling', 'ringing', 'connected', 'retrying'].includes(
        existingWorkflow.status,
      )
    ) {
      this.logger.info(
        `[Voice] Reusing active call workflow for session ${sessionId}.`,
      );
      return this._buildStatusPayload(snapshot);
    }

    const initialWorkflow = {
      ...existingWorkflow,
      provider: this.voiceProvider.name,
      emergencyContacts: contacts,
      currentContactIndex: existingWorkflow.currentContactIndex ?? 0,
      retryCount: existingWorkflow.retryCount ?? 0,
      maxRetriesPerContact:
          existingWorkflow.maxRetriesPerContact ?? DEFAULT_MAX_RETRIES_PER_CONTACT,
      isSafe: existingWorkflow.isSafe === true,
      canShowPostSafeActions:
          existingWorkflow.canShowPostSafeActions === true,
      lastKnownLocation: location ?? existingWorkflow.lastKnownLocation ?? null,
      startedAt: existingWorkflow.startedAt ?? nowIso(),
      updatedAt: nowIso(),
      status: 'initializing',
      statusText: buildStatusText(
        'initializing',
        contacts[existingWorkflow.currentContactIndex ?? 0],
      ),
      isCallActive: true,
    };

    await this._updateWorkflow(docRef, initialWorkflow);
    return this._placeCall({
      docRef,
      sessionId,
      userId,
      victimName,
      victimPhone,
      workflow: initialWorkflow,
    });
  }

  async getActiveCall({ userId }) {
    const snapshot = await this.firestore
      .collection('active_sos')
      .where('uid', '==', userId)
      .where('active', '==', true)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return null;
    }

    return this._buildStatusPayload(snapshot.docs[0]);
  }

  async getCallStatus({ sessionId }) {
    const docRef = this._doc(sessionId);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new Error(`SOS session ${sessionId} does not exist.`);
    }

    const data = snapshot.data() ?? {};
    const workflow = this._workflowFrom(data);

    if (
      workflow.providerCallId &&
      ['initializing', 'calling', 'ringing', 'connected', 'retrying'].includes(
        workflow.status,
      )
    ) {
      try {
        this.logger.info(
          `[Voice] Querying provider status for ${workflow.providerCallId} on session ${sessionId}.`,
        );
        const providerStatus = await this.voiceProvider.getCallStatus({
          providerCallId: workflow.providerCallId,
        });
        this.logger.info(
          `[Voice] Provider status received for ${sessionId}: ${providerStatus.status}.`,
        );

        if (providerStatus.status === 'ringing') {
          await this._updateWorkflow(docRef, {
            ...workflow,
            status: 'ringing',
            statusText: buildStatusText('ringing', workflow.currentContact),
            isCallActive: true,
            updatedAt: nowIso(),
          });
        } else if (providerStatus.status === 'connected') {
          await this._updateWorkflow(docRef, {
            ...workflow,
            status: 'connected',
            statusText: buildStatusText('connected', workflow.currentContact),
            isCallActive: true,
            updatedAt: nowIso(),
          });
        } else if (
          providerStatus.status === 'failed' ||
          providerStatus.status === 'completed'
        ) {
          await this._handleCallFailureOrCompletion({
            docRef,
            workflow,
            reason: providerStatus.status,
          });
        }
      } catch (error) {
        this.logger.warn(
          `[Voice] Provider status sync failed for session ${sessionId}: ${error.message}`,
        );
      }
    }

    return this._buildStatusPayload(await docRef.get());
  }

  async markSafe({ sessionId }) {
    const docRef = this._doc(sessionId);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new Error(`SOS session ${sessionId} does not exist.`);
    }

    const workflow = this._workflowFrom(snapshot.data());
    const nextStatus = workflow.isCallActive ? 'safe' : 'resolved';
    const nextWorkflow = {
      ...workflow,
      isSafe: true,
      canShowPostSafeActions: true,
      stopRetries: true,
      status: nextStatus,
      statusText: buildStatusText(nextStatus, workflow.currentContact),
      updatedAt: nowIso(),
    };

    await this._updateWorkflow(docRef, nextWorkflow);
    this.logger.info(`[Voice] SOS ${sessionId} marked safe.`);
    return this._buildStatusPayload(await docRef.get());
  }

  async endCall({ sessionId }) {
    const docRef = this._doc(sessionId);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new Error(`SOS session ${sessionId} does not exist.`);
    }

    const workflow = this._workflowFrom(snapshot.data());
    if (workflow.providerCallId) {
      try {
        await this.voiceProvider.endCall({
          providerCallId: workflow.providerCallId,
        });
      } catch (error) {
        this.logger.warn(
          `[Voice] Failed to end provider call ${workflow.providerCallId}: ${error.message}`,
        );
      }
    }

    await this._updateWorkflow(docRef, {
      ...workflow,
      isCallActive: false,
      canShowPostSafeActions: false,
      status: workflow.isSafe ? 'resolved' : 'ended',
      statusText: buildStatusText(workflow.isSafe ? 'resolved' : 'ended'),
      updatedAt: nowIso(),
    });

    this.logger.info(`[Voice] SOS ${sessionId} call ended.`);
    return this._buildStatusPayload(await docRef.get());
  }

  async syncLocation({ sessionId, location }) {
    const docRef = this._doc(sessionId);
    await docRef.set(
      {
        callWorkflow: {
          lastKnownLocation: {
            lat: location?.lat ?? null,
            lng: location?.lng ?? null,
            updatedAt: nowIso(),
          },
        },
      },
      { merge: true },
    );
  }

  async handleWebhook(payload, query = {}) {
    if (
      this.voiceProvider.name === 'twilio' &&
      (!payload?.CallStatus || !payload?.CallSid)
    ) {
      const sessionId =
        query.sessionId?.toString() ??
        payload.sessionId?.toString() ??
        '';
      let victimName = 'A SafeRoute user';
      if (sessionId) {
        try {
          const sessionSnapshot = await this._doc(sessionId).get();
          const workflow = this._workflowFrom(sessionSnapshot.data() ?? {});
          victimName = workflow.victimName ?? victimName;
        } catch (error) {
          this.logger.warn(
            `[Voice] Failed to resolve victim name for TwiML webhook ${sessionId}: ${error.message}`,
          );
        }
      }

      return {
        twiml: this.voiceProvider.buildTwimlResponse({
          victimName,
          sessionId,
        }),
      };
    }

    const normalized = await this.voiceProvider.handleWebhook({
      ...payload,
      ...query,
    });
    const sessionSnapshot = normalized.sessionId
      ? await this._doc(normalized.sessionId).get()
      : await this._findByProviderCallId(normalized.providerCallId);

    if (!sessionSnapshot?.exists) {
      throw new Error('Unable to match webhook to an active SOS session.');
    }

    const docRef = sessionSnapshot.ref;
    const workflow = this._workflowFrom(sessionSnapshot.data());
    const mergedWorkflow = {
      ...workflow,
      providerCallId: normalized.providerCallId || workflow.providerCallId,
      currentContact: normalized.currentContact || workflow.currentContact,
      updatedAt: nowIso(),
    };

    this.logger.info(
      `[Voice] Webhook received for ${docRef.id}: ${normalized.status}`,
    );

    switch (normalized.status) {
      case 'ringing':
        await this._updateWorkflow(docRef, {
          ...mergedWorkflow,
          status: 'ringing',
          statusText: buildStatusText('ringing', mergedWorkflow.currentContact),
          isCallActive: true,
        });
        break;
      case 'connected':
        await this._updateWorkflow(docRef, {
          ...mergedWorkflow,
          status: 'connected',
          statusText: buildStatusText(
            'connected',
            mergedWorkflow.currentContact,
          ),
          isCallActive: true,
          canShowPostSafeActions: workflow.isSafe === true,
        });
        break;
      case 'failed':
      case 'completed':
        await this._handleCallFailureOrCompletion({
          docRef,
          workflow: mergedWorkflow,
          reason: normalized.status,
        });
        break;
      default:
        await this._updateWorkflow(docRef, {
          ...mergedWorkflow,
          status: normalized.status,
          statusText: buildStatusText(
            normalized.status,
            mergedWorkflow.currentContact,
          ),
        });
        break;
    }

    return this._buildStatusPayload(await docRef.get());
  }

  async _handleCallFailureOrCompletion({ docRef, workflow, reason }) {
    if (workflow.isSafe === true || workflow.stopRetries === true) {
      await this._updateWorkflow(docRef, {
        ...workflow,
        status: workflow.isSafe ? 'safe' : 'ended',
        statusText: buildStatusText(
          workflow.isSafe ? 'safe' : 'ended',
          workflow.currentContact,
        ),
        isCallActive: false,
        updatedAt: nowIso(),
      });
      return;
    }

    const contacts = workflow.emergencyContacts ?? [];
    const maxRetries =
        workflow.maxRetriesPerContact ?? DEFAULT_MAX_RETRIES_PER_CONTACT;
    let targetIndex = workflow.currentContactIndex ?? 0;
    let retryCount = workflow.retryCount ?? 0;

    if (retryCount + 1 < maxRetries) {
      retryCount += 1;
      this.logger.warn(
        `[Voice] Call failed (${reason}). Retrying contact ${workflow.currentContact} for session ${docRef.id}.`,
      );
    } else {
      targetIndex += 1;
      retryCount = 0;
      if (targetIndex >= contacts.length) {
        await this._updateWorkflow(docRef, {
          ...workflow,
          status: 'failed',
          statusText: buildStatusText('failed'),
          isCallActive: false,
          updatedAt: nowIso(),
        });
        return;
      }
      this.logger.warn(
        `[Voice] Call failed (${reason}). Moving to next contact ${contacts[targetIndex]} for session ${docRef.id}.`,
      );
    }

    const nextWorkflow = {
      ...workflow,
      currentContactIndex: targetIndex,
      currentContact: contacts[targetIndex],
      retryCount,
      status: 'retrying',
      statusText: buildStatusText('retrying', contacts[targetIndex]),
      isCallActive: true,
      updatedAt: nowIso(),
    };

    await this._updateWorkflow(docRef, nextWorkflow);

    await this._placeCall({
      docRef,
      sessionId: docRef.id,
      userId: workflow.userId ?? '',
      victimName: workflow.victimName ?? 'A SafeRoute user',
      victimPhone: workflow.victimPhone ?? null,
      workflow: nextWorkflow,
    });
  }

  async _placeCall({
    docRef,
    sessionId,
    userId,
    victimName,
    victimPhone,
    workflow,
  }) {
    const contacts = workflow.emergencyContacts ?? [];
    const targetIndex = workflow.currentContactIndex ?? 0;
    const currentContact = contacts[targetIndex];
    if (!currentContact) {
      throw new Error('No emergency contact available to call.');
    }

      try {
        this.logger.info(
          `[Voice] Twilio request sent for session ${sessionId} to ${currentContact}.`,
        );
        const result = await this.voiceProvider.startEmergencyCall({
        sessionId,
        userId,
        contactNumber: currentContact,
        victimName,
        victimPhone,
        metadata: {
          currentContactIndex: targetIndex,
          retryCount: workflow.retryCount ?? 0,
        },
      });

      const mergedWorkflow = {
        ...workflow,
        userId,
        victimName,
        victimPhone,
        providerCallId: result.providerCallId,
        currentContact,
        status: 'calling',
        statusText: buildStatusText('calling', currentContact),
        isCallActive: true,
        updatedAt: nowIso(),
      };

      await this._updateWorkflow(docRef, mergedWorkflow);
      this.logger.info(
        `[Voice] Twilio response received for session ${sessionId}: ${result.providerCallId}.`,
      );
      return this._buildStatusPayload(await docRef.get());
    } catch (error) {
      this.logger.error(
        `[Voice] Provider start failed for session ${sessionId}: ${error.message}`,
      );
      await this._handleCallFailureOrCompletion({
        docRef,
        workflow: {
          ...workflow,
          userId,
          victimName,
          victimPhone,
          currentContact,
          isCallActive: false,
        },
        reason: 'failed',
      });
      return this._buildStatusPayload(await docRef.get());
    }
  }

  _workflowFrom(data = {}) {
    return {
      ...(data.callWorkflow ?? {}),
    };
  }

  _doc(sessionId) {
    return this.firestore.collection('active_sos').doc(sessionId);
  }

  async _findByProviderCallId(providerCallId) {
    if (!providerCallId) {
      return null;
    }

    const snapshot = await this.firestore
      .collection('active_sos')
      .where('callWorkflow.providerCallId', '==', providerCallId)
      .limit(1)
      .get();

    return snapshot.empty ? null : snapshot.docs[0];
  }

  async _updateWorkflow(docRef, workflow) {
    await docRef.set(
      {
        callWorkflow: workflow,
      },
      { merge: true },
    );
  }

  _buildStatusPayload(snapshot) {
    const data = snapshot.data() ?? {};
    const workflow = this._workflowFrom(data);
    const status = workflow.status ?? 'idle';
    const currentContact = workflow.currentContact?.toString() ?? '';

    return {
      sessionId: data.sessionId?.toString() ?? snapshot.id,
      status,
      statusText:
          workflow.statusText?.toString() ??
          buildStatusText(status, currentContact),
      isCallActive:
          workflow.isCallActive === true ||
          status === 'calling' ||
          status === 'ringing' ||
          status === 'connected' ||
          status === 'retrying',
      isSafe: workflow.isSafe === true,
      canShowPostSafeActions: workflow.canShowPostSafeActions === true,
      providerCallId: workflow.providerCallId?.toString() ?? '',
      currentContact,
    };
  }
}
