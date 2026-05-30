const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

/**
 * عند إنشاء مكالمة جديدة -> إرسال إشعار للمستلم
 */
exports.onCallCreated = functions.firestore
  .document('calls/{callId}')
  .onCreate(async (snap, context) => {
    const call = snap.data();
    const calleeId = call.calleeId;
    const callerId = call.callerId;

    // جلب توكنات جهاز المستلم
    const userDoc = await admin.firestore().collection('users').doc(calleeId).get();
    if (!userDoc.exists) return null;

    const data = userDoc.data();
    const tokens = (data && Array.isArray(data.fcmTokens)) ? data.fcmTokens : [];
    if (!Array.isArray(tokens) || tokens.length === 0) return null;

    const payload = {
      notification: {
        title: '📞 مكالمة واردة',
        body: call.isVideo ? 'مكالمة فيديو جديدة' : 'مكالمة صوتية جديدة',
      },
      data: {
        type: 'incoming_call',
        callId: context.params.callId,
        callerId: String((callerId !== undefined && callerId !== null) ? callerId : ''),
        isVideo: String(!!call.isVideo),
      },
    };

    const response = await admin.messaging().sendToDevice(tokens, payload);
    console.log('📢 FCM response:', response);
    return null;
  });

/**
 * عند إرسال رسالة جديدة -> إشعار للمستلم
 */
exports.onMessageCreated = functions.firestore
  .document('messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const receiverId = message.receiverId;
    const senderId = message.senderId;

    // جلب توكنات جهاز المستلم
    const userDoc = await admin.firestore().collection('users').doc(receiverId).get();
    if (!userDoc.exists) return null;

    const msgUserData = userDoc.data();
    const tokens = (msgUserData && Array.isArray(msgUserData.fcmTokens)) ? msgUserData.fcmTokens : [];
    if (!Array.isArray(tokens) || tokens.length === 0) return null;

    const payload = {
      notification: {
        title: '💬 رسالة جديدة',
        body: message.text || 'لديك رسالة جديدة',
      },
      data: {
        type: 'chat_message',
        messageId: context.params.messageId,
        senderId: String((senderId !== undefined && senderId !== null) ? senderId : ''),
      },
    };

    const response = await admin.messaging().sendToDevice(tokens, payload);
    console.log('📢 Message FCM response:', response);
    return null;
  });

/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
