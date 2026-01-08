import { onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

admin.initializeApp();

interface SendNotificationRequest {
  userId: string;
  title: string;
  body: string;
  action?: string;
  sheetType?: string;
  payloadId?: string;
}

/**
 * Sends a custom push notification to a specific user using stored FCM tokens.
 */
export const sendCustomNotification = onCall<SendNotificationRequest>(
  async (request) => {
    // 1. Verify Authentication (Optional but recommended for production)
    // if (!request.auth) {
    //   throw new HttpsError("unauthenticated", "User must be logged in.");
    // }

    const dataPayload = request.data;
    const { userId, title, body, action, sheetType, payloadId } = dataPayload;

    if (!userId || !title || !body) {
      throw new Error("Missing required fields: userId, title, body");
    }

    // 2. Fetch User's Tokens
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`User ${userId} not found.`);
      return { success: false, message: "User not found" };
    }

    const userData = userDoc.data();
    const tokens = userData?.fcmTokens as string[] | undefined;

    if (!tokens || tokens.length === 0) {
      console.log(`No tokens found for user ${userId}.`);
      return { success: false, message: "No device tokens found" };
    }

    // 3. Construct Payload
    const notificationData: { [key: string]: string } = {};
    if (action) notificationData.action = action;
    if (sheetType) notificationData.sheetType = sheetType;
    if (payloadId) notificationData.id = payloadId;

    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      data: notificationData,
      apns: {
        payload: {
          aps: {
            sound: "default",
            contentAvailable: true,
          },
        },
      },
    };

    // 4. Send Message
    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `Sent ${response.successCount} messages, ` +
        `failed ${response.failureCount}`
      );

      // Optional: Cleanup invalid tokens
      if (response.failureCount > 0) {
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success && (
            resp.error?.code === "messaging/invalid-registration-token" ||
            resp.error?.code === "messaging/registration-token-not-registered"
          )) {
            invalidTokens.push(tokens[idx]);
          }
        });
        if (invalidTokens.length > 0) {
          await db.collection("users").doc(userId).update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
          });
          console.log(`Removed ${invalidTokens.length} invalid tokens.`);
        }
      }

      return { success: true, sentCount: response.successCount };
    } catch (error) {
      console.error("Error sending notification:", error);
      throw new Error("Failed to send notification");
    }
  }
);
