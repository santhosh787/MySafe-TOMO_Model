import { createHash, randomBytes } from 'node:crypto';
import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import twilio from 'twilio';

admin.initializeApp();
const db = admin.firestore();
const smsAccountSid = defineSecret('TWILIO_ACCOUNT_SID');
const smsAuthToken = defineSecret('TWILIO_AUTH_TOKEN');
const smsFromNumber = defineSecret('TWILIO_FROM_NUMBER');

function requireAuth(request: { auth?: { uid: string } | null }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  return uid;
}

function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

export const createGuardianInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = randomBytes(24).toString('base64url');
  const codeHash = hashCode(code);
  const profile = await db.collection('users').doc(uid).get();
  const data = profile.data() ?? {};

  await db.collection('guardianInvites').doc(codeHash).create({
    ownerUid: uid,
    ownerName: typeof data.displayName === 'string' ? data.displayName : '',
    ownerEmail: typeof data.email === 'string' ? data.email : '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
    used: false,
  });
  return { code, expiresInSeconds: 900 };
});

export const acceptGuardianInvite = onCall(async (request) => {
  const guardianUid = requireAuth(request);
  const code = request.data?.code;
  if (typeof code !== 'string' || code.length < 20 || code.length > 100) {
    throw new HttpsError('invalid-argument', 'Invitation code is invalid.');
  }

  // Phone Auth adds phone_number to the Firebase ID token only after verification.
  const guardianPhone = request.auth?.token.phone_number;
  if (typeof guardianPhone !== 'string' || !guardianPhone.startsWith('+')) {
    throw new HttpsError('failed-precondition', 'Verify your phone number with Firebase Phone Authentication before accepting a guardian invitation.');
  }

  const inviteRef = db.collection('guardianInvites').doc(hashCode(code));
  await db.runTransaction(async (transaction) => {
    const inviteSnap = await transaction.get(inviteRef);
    if (!inviteSnap.exists) throw new HttpsError('not-found', 'Invitation not found or expired.');
    const invite = inviteSnap.data()!;
    if (invite.used === true) throw new HttpsError('already-exists', 'This invitation has already been used.');
    if (!(invite.expiresAt instanceof admin.firestore.Timestamp) || invite.expiresAt.toMillis() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'This invitation has expired. Ask the user to create a new QR code.');
    }
    const ownerUid = String(invite.ownerUid ?? '');
    if (!ownerUid || ownerUid === guardianUid) {
      throw new HttpsError('failed-precondition', 'You cannot pair an account with itself.');
    }

    const guardianProfile = await transaction.get(db.collection('users').doc(guardianUid));
    const guardianName = guardianProfile.data()?.displayName ?? request.auth?.token.name ?? '';
    const linkId = `${ownerUid}_${guardianUid}`;
    const linkRef = db.collection('guardianLinks').doc(linkId);
    transaction.set(linkRef, {
      userUid: ownerUid,
      guardianUid,
      ownerName: invite.ownerName ?? '',
      ownerEmail: invite.ownerEmail ?? '',
      guardianName: typeof guardianName === 'string' ? guardianName : '',
      guardianPhone,
      status: 'active',
      linkedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.update(inviteRef, {
      used: true,
      usedBy: guardianUid,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { paired: true };
});

export const dispatchNewSos = onDocumentCreated(
  {
    document: 'users/{uid}/incidents/{incidentId}',
    secrets: [smsAccountSid, smsAuthToken, smsFromNumber],
  },
  async (event) => {
    const incident = event.data?.data();
    const uid = event.params.uid;
    const incidentId = event.params.incidentId;
    if (!incident || incident.type !== 'sos') return;

    const links = await db.collection('guardianLinks').where('userUid', '==', uid).get();
    const owner = await db.collection('users').doc(uid).get();
    const ownerName = owner.data()?.displayName || 'A My Safe Tomo user';
    const location = incident.location as { latitude?: number; longitude?: number } | null;
    const mapUrl = location && typeof location.latitude === 'number' && typeof location.longitude === 'number'
      ? `https://maps.google.com/?q=${location.latitude},${location.longitude}`
      : '';

    for (const linkDoc of links.docs) {
      const link = linkDoc.data();
      if (link.status !== 'active' || typeof link.guardianUid !== 'string') continue;
      const guardianUid = link.guardianUid;
      const deviceSnap = await db.collection('users').doc(guardianUid).collection('devices').get();
      const devices = deviceSnap.docs
        .map((doc) => ({ ref: doc.ref, token: doc.data().token }))
        .filter((device): device is { ref: admin.firestore.DocumentReference; token: string } =>
          typeof device.token === 'string' && device.token.length > 0);
      const tokens = devices.map((device) => device.token);

      let pushDelivered = false;
      if (tokens.length > 0) {
        const response = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: 'My Safe Tomo emergency alert',
            body: `${ownerName} requested help. Open the app to view the incident.`,
          },
          data: {
            type: 'sos',
            userUid: uid,
            incidentId,
            mapUrl,
          },
          android: { priority: 'high' },
        });
        pushDelivered = response.successCount > 0;
        if (response.failureCount > 0) {
          const invalidCodes = new Set(['messaging/invalid-registration-token', 'messaging/registration-token-not-registered']);
          const cleanup = response.responses
            .map((result, index) => ({ result, ref: devices[index]?.ref }))
            .filter(({ result }) => !result.success && result.error && invalidCodes.has(result.error.code));
          await Promise.all(cleanup.map(({ ref }) => ref?.delete()));
        }
      }

      let smsStatus = 'not_needed';
      // SMS fallback is used when the guardian has no registered app device token.
      if (!pushDelivered && typeof link.guardianPhone === 'string' && link.guardianPhone.startsWith('+')) {
        const sid = smsAccountSid.value();
        const auth = smsAuthToken.value();
        const from = smsFromNumber.value();
        if (sid && auth && from) {
          try {
            const client = twilio(sid, auth);
            const body = `${ownerName} sent a My Safe Tomo SOS alert. Please contact them now.${mapUrl ? ` Last location: ${mapUrl}` : ' Location is unavailable.'}`;
            await client.messages.create({ to: link.guardianPhone, from, body });
            smsStatus = 'sent';
          } catch (error) {
            console.error('Twilio SMS delivery failed', error);
            smsStatus = 'failed';
          }
        } else {
          smsStatus = 'not_configured';
        }
      }

      await db.collection('dispatchLogs').add({
        userUid: uid,
        guardianUid,
        incidentId,
        pushDelivered,
        smsStatus,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  },
);
