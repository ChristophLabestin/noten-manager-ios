import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
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

interface ExplainErrorRequest {
  errorType: string;
  errorDescription: string;
  source?: {
    file: string;
    function: string;
    line: number;
  };
  context?: Record<string, string>;
  callStack?: string[];
}

interface AnswerSupportTicketRequest {
  ticketId: string;
  userId: string;
  message: string;
  adminEmail: string;
}

/**
 * Answers a support ticket and notifies the user via push.
 */
export const answerSupportTicket = onCall<AnswerSupportTicketRequest>(
  {cors: true, region: "europe-west3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const {ticketId, userId, message, adminEmail} = request.data;
    const db = admin.firestore();

    console.log(`Answering ticket ${ticketId} for user ${userId}`);

    const reply = {
      message,
      adminEmail,
      adminId: request.auth.uid,
      createdAt: admin.firestore.Timestamp.now(),
    };

    // 1. Update the ticket
    await db.collection("supportTickets").doc(ticketId).update({
      replies: admin.firestore.FieldValue.arrayUnion(reply),
    });

    // 2. Try to notify the user via Push
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.warn(`User ${userId} not found in Firestore.`);
      return {success: true, warned: "User not found"};
    }

    const userData = userDoc.data();
    const tokens = userData?.fcmTokens as string[] | undefined;

    console.log(`Found ${tokens?.length || 0} tokens for user ${userId}`);

    if (tokens && tokens.length > 0) {
      const pushMessage: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
          title: "Support Antwort",
          body: "Du hast eine neue Antwort auf dein Ticket erhalten.",
        },
        data: {
          action: "openSupportTicket",
          ticketId,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        const response = await admin.messaging()
          .sendEachForMulticast(pushMessage);
        console.log(`Push result: ${response.successCount} success, ` +
                `${response.failureCount} failure`);
        if (response.failureCount > 0) {
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error(`Token ${idx} error:`, resp.error);
            }
          });
        }
      } catch (pushError) {
        console.error("Critical FCM error:", pushError);
      }
    }
    return {success: true};
  }
);

/**
 * Explains an error log using Gemini AI.
 */
export const explainErrorLog = onCall<ExplainErrorRequest>(
  {
    cors: true,
    region: "europe-west3",
  },
  async (request) => {
    console.log("explainErrorLog [DEPLOY_FINAL_CHECK]: Request received");
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not set.");
      throw new HttpsError("failed-precondition", "AI config missing.");
    }

    try {
      const {
        errorType,
        errorDescription,
        source,
        context,
        callStack,
      } = request.data;

      const prompt = `
        You are an expert iOS and Swift developer.
        Analyze the following error log from an iOS app:

        **Error Type:** ${errorType}
        **Description:** ${errorDescription}
        ${source ?
    `**Source:** ${source.file} in ${source.function} line ${source.line}` :
    ""}
        ${context ? `**Context:** ${JSON.stringify(context, null, 2)}` : ""}
        
        ${callStack && callStack.length > 0 ?
    `**Stack Trace:**\n${callStack.slice(0, 10).join("\n")}...` : ""}

        Please provide your response in JSON format with two keys:
        1. "explanation": A concise explanation of the error.
        2. "fixPrompt": A detailed prompt for an AI coding assistant.

        Ensure the JSON is valid and correctly escaped.
      `;

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=${apiKey}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            contents: [{parts: [{text: prompt}]}],
            generationConfig: {
              responseMimeType: "application/json",
            },
          }),
        }
      );

      if (!response.ok) {
        const errorBody = await response.text();
        console.error("Gemini REST Error:", errorBody);
        throw new Error(`Gemini API returned ${response.status}: ${errorBody}`);
      }

      const result = await response.json();
      const text = result.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!text) {
        throw new Error("Empty response from Gemini API");
      }

      // Robust JSON extraction
      try {
        const cleanedText = text.replace(/```json|```/g, "").trim();
        const jsonResponse = JSON.parse(cleanedText);
        return {
          explanation: jsonResponse.explanation,
          fixPrompt: jsonResponse.fixPrompt,
        };
      } catch (parseError) {
        console.warn("AI didn't return valid JSON, returning raw text", text);
        return {
          explanation: text,
          fixPrompt: "Could not generate structured fix prompt.",
        };
      }
    } catch (error: unknown) {
      console.error("AI Analysis Execution Error:", error);
      const message = error instanceof Error ? error.message : "Unknown error";
      throw new HttpsError(
        "internal",
        `AI Analysis failed: ${message}`
      );
    }
  }
);

type BroadcastPlatform = "all" | "ios" | "android";

interface BroadcastNotificationRequest {
  title: string;
  body: string;
  platforms: BroadcastPlatform;
}

const sendBroadcastPush = async (
  data: BroadcastNotificationRequest
): Promise<{sentCount: number; message?: string}> => {
  const {title, body, platforms} = data;
  const db = admin.firestore();

  // 1. Fetch tokens in batches to avoid memory issues
  let userQuery: admin.firestore.Query = db.collection("users");
  if (platforms !== "all") {
    userQuery = userQuery.where("lastPlatform", "==", platforms);
  }

  const userSnap = await userQuery.get();
  const allTokens: string[] = [];
  userSnap.forEach((doc) => {
    const tokens = doc.data().fcmTokens as string[] | undefined;
    if (tokens) {
      allTokens.push(...tokens);
    }
  });

  if (allTokens.length === 0) {
    return {sentCount: 0, message: "No tokens found."};
  }

  // 2. Send in batches of 500 (FCM limit for multicast)
  const batches = [];
  for (let i = 0; i < allTokens.length; i += 500) {
    batches.push(allTokens.slice(i, i + 500));
  }

  let totalSent = 0;
  for (const tokenBatch of batches) {
    const message: admin.messaging.MulticastMessage = {
      tokens: tokenBatch,
      notification: {title, body},
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      totalSent += response.successCount;
    } catch (error) {
      console.error("Batch send error:", error);
    }
  }

  return {sentCount: totalSent};
};

/**
 * Sends a broadcast push notification to all users matching the platform.
 */
export const sendBroadcastNotification = onCall<BroadcastNotificationRequest>(
  {region: "europe-west3", cors: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const {title, body, platforms} = request.data;
    if (!title || !body || !platforms) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }

    const result = await sendBroadcastPush({title, body, platforms});
    return {
      success: true,
      sentCount: result.sentCount,
      message: result.message,
    };
  }
);

/**
 * Picks up scheduled broadcasts and sends them when due.
 */
export const processScheduledBroadcasts = onSchedule(
  {region: "europe-west3", schedule: "every 1 minutes"},
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const snapshot = await db.collection("broadcastNotifications")
      .where("scheduledFor", "<=", now)
      .get();

    if (snapshot.empty) {
      return;
    }

    for (const docSnap of snapshot.docs) {
      const docRef = docSnap.ref;
      let payload: BroadcastNotificationRequest | null = null;

      await db.runTransaction(async (tx) => {
        const current = await tx.get(docRef);
        if (!current.exists) return;

        const data = current.data();
        if (data?.status !== "scheduled") return;

        const scheduledFor = data?.scheduledFor as
          admin.firestore.Timestamp
          | undefined;
        if (!scheduledFor || scheduledFor.toMillis() > now.toMillis()) return;

        if (typeof data?.title !== "string" || typeof data?.body !== "string") {
          return;
        }

        payload = {
          title: data.title,
          body: data.body,
          platforms: (data.platforms as BroadcastPlatform) || "all",
        };

        tx.update(docRef, {
          status: "sending",
          sendingAt: now,
        });
      });

      if (!payload) continue;

      try {
        const result = await sendBroadcastPush(payload);
        await docRef.update({
          status: "sent",
          sentAt: admin.firestore.Timestamp.now(),
          isActive: true,
          sentCount: result.sentCount,
          sendMessage: result.message ?? null,
        });
      } catch (error: unknown) {
        console.error("Scheduled broadcast send error:", error);
        await docRef.update({
          status: "failed",
          sendError: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }
  }
);

/**
 * Sends a custom push notification to a specific user using stored FCM tokens.
 */
export const sendCustomNotification = onCall<SendNotificationRequest>(
  {region: "europe-west3"},
  async (request) => {
    // 1. Verify Authentication (Optional but recommended for production)
    // if (!request.auth) {
    //   throw new HttpsError("unauthenticated", "User must be logged in.");
    // }

    const dataPayload = request.data;
    const {userId, title, body, action, sheetType, payloadId} = dataPayload;

    if (!userId || !title || !body) {
      throw new Error("Missing required fields: userId, title, body");
    }

    // 2. Fetch User's Tokens
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`User ${userId} not found.`);
      return {success: false, message: "User not found"};
    }

    const userData = userDoc.data();
    const tokens = userData?.fcmTokens as string[] | undefined;

    if (!tokens || tokens.length === 0) {
      console.log(`No tokens found for user ${userId}.`);
      return {success: false, message: "No device tokens found"};
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

      return {success: true, sentCount: response.successCount};
    } catch (error) {
      console.error("Error sending notification:", error);
      throw new Error("Failed to send notification");
    }
  }
);
