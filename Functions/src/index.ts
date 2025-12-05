import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import dayjs from 'dayjs';

// Initialize Firebase Admin
admin.initializeApp();

// Define TypeScript interfaces
interface ScheduleNotificationRequest {
  token: string;
  title: string;
  body: string;
  triggerTime: string; // ISO 8601 format
  payload?: Record<string, any>;
}

interface ScheduledNotificationDoc {
  token: string;
  title: string;
  body: string;
  triggerTime: admin.firestore.Timestamp;
  status: 'pending' | 'sent' | 'failed';
  createdAt: admin.firestore.FieldValue;
  payload?: Record<string, any> | null;
  userId: string;
  error?: string;
  sentAt?: admin.firestore.FieldValue;
}

// 1️⃣ Client calls this function to schedule a notification
export const scheduleFcmNotification = functions.https.onCall(
  async (
    data: ScheduleNotificationRequest,
    context: functions.https.CallableContext
  ) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const { token, title, body, triggerTime, payload } = data;
    if (!token || !title || !body || !triggerTime) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    const trigger = dayjs(triggerTime);
    const now = dayjs();
    if (!trigger.isValid() || trigger.isBefore(now)) {
      throw new functions.https.HttpsError('invalid-argument', 'Trigger time must be a valid future timestamp');
    }

    const docRef = await admin.firestore().collection('scheduledNotifications').add({
      token,
      title,
      body,
      triggerTime: admin.firestore.Timestamp.fromDate(trigger.toDate()),
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      payload: payload || null,
      userId: context.auth.uid,
    } as ScheduledNotificationDoc);

    return { success: true, notificationId: docRef.id };
  }
);

// 2️⃣ Cron job runs every minute to send due notifications
export const processScheduledNotifications = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await admin.firestore()
      .collection('scheduledNotifications')
      .where('status', '==', 'pending')
      .where('triggerTime', '<=', now)
      .get();

    for (const doc of snapshot.docs) {
      const data = doc.data() as ScheduledNotificationDoc;
      try {
        await sendFcmNotification({
          token: data.token,
          title: data.title,
          body: data.body,
          payload: data.payload || {},
        });

        await doc.ref.update({
          status: 'sent',
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err: any) {
        console.error('❌ Failed to send scheduled notification:', err);
        await doc.ref.update({
          status: 'failed',
          error: err.message,
        });
      }
    }

    return null;
  });

// 3️⃣ Send FCM notification (helper)
async function sendFcmNotification(params: {
  token: string;
  title: string;
  body: string;
  payload?: Record<string, any>;
}) {
  const dataPayload: Record<string, string> = {};
  if (params.payload) {
    for (const [k, v] of Object.entries(params.payload)) {
      dataPayload[k] = String(v);
    }
  }

  const message: admin.messaging.Message = {
    token: params.token,
    notification: {
      title: params.title,
      body: params.body,
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channelId: 'daily_planner_channel',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          contentAvailable: true,
          badge: 1,
        },
      },
    },
    data: {
      ...dataPayload,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      type: 'scheduled_notification',
    },
  };

  await admin.messaging().send(message);
}

// 4️⃣ Clean up old notifications (optional)
export const cleanupNotifications = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const cutoff = dayjs().subtract(7, 'days').toDate();
    const snapshot = await admin.firestore()
      .collection('scheduledNotifications')
      .where('triggerTime', '<', cutoff)
      .get();

    const batch = admin.firestore().batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();

    console.log(`🧹 Cleaned up ${snapshot.size} old notifications`);
  });
