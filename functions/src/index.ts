import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { CloudTasksClient } from "@google-cloud/tasks";
import { onDocumentWritten, onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as apn from "apn";
import * as crypto from "crypto";

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

interface SentinelStatsResponse {
  totalUsers: number;
  authUserCount: number;
  dau: number;
  wau: number;
  mau: number;
  onboardingCompleted: number;
  usersWithActiveSchoolYear: number;
  adminAccessActive: number;
  usersWithTokens: number;
  avgTokensPerUser: number;
  schoolYearDocCount: number;
  avgSchoolYearsPerUser: number;
  registrationPlatforms: Record<string, number>;
  lastPlatforms: Record<string, number>;
  purchaseTypes: Record<string, number>;
  subscriptionTiers: Record<string, number>;
  registeredInVersions: Record<string, number>;
}

const incrementBucket = (target: Record<string, number>, key: string) => {
  const normalized = key?.toString().trim() || "unknown";
  target[normalized] = (target[normalized] || 0) + 1;
};

const assertAdmin = async (uid: string) => {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  const data = doc.data();
  if (!doc.exists || data?.isAdmin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
};

/**
 * Answers a support ticket and notifies the user via push.
 */
export const answerSupportTicket = onCall<AnswerSupportTicketRequest>(
  { cors: true, region: "europe-west3" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const { ticketId, userId, message, adminEmail } = request.data;
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
      return { success: true, warned: "User not found" };
    }

    const userData = userDoc.data();
    if (userData?.supportNotificationUpdates === false) {
      return { success: true, warned: "Support notifications disabled" };
    }

    const tokenEntries = await fetchUserTokenEntries(db, userId);
    const tokens = tokenEntries.map((entry) => entry.token);

    console.log(`Found ${tokens.length} tokens for user ${userId}`);

    if (tokens.length > 0) {
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
          const invalidIndices: number[] = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error(`Token ${idx} error:`, resp.error);
            }
            if (!resp.success && (
              resp.error?.code === "messaging/invalid-registration-token" ||
              resp.error?.code === "messaging/registration-token-not-registered"
            )) {
              invalidIndices.push(idx);
            }
          });
          if (invalidIndices.length > 0) {
            await cleanupInvalidTokenEntries(db, tokenEntries, invalidIndices);
          }
        }
      } catch (pushError) {
        console.error("Critical FCM error:", pushError);
      }
    }
    return { success: true };
  }
);

/**
 * Returns aggregated Sentinel statistics for admin dashboards.
 */
export const getSentinelStats = onCall<unknown, Promise<SentinelStatsResponse>>(
  { cors: true, region: "europe-west3" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    await assertAdmin(request.auth.uid);

    const db = admin.firestore();
    const now = Date.now();
    const dayAgo = now - 24 * 60 * 60 * 1000;
    const weekAgo = now - 7 * 24 * 60 * 60 * 1000;
    const monthAgo = now - 30 * 24 * 60 * 60 * 1000;

    let authUserCount = 0;
    let dau = 0;
    let wau = 0;
    let mau = 0;
    let pageToken: string | undefined;
    do {
      const page = await admin.auth().listUsers(1000, pageToken);
      for (const user of page.users) {
        authUserCount += 1;
        const lastSignIn = user.metadata?.lastSignInTime ?
          Date.parse(user.metadata.lastSignInTime) :
          0;
        if (lastSignIn >= dayAgo) dau += 1;
        if (lastSignIn >= weekAgo) wau += 1;
        if (lastSignIn >= monthAgo) mau += 1;
      }
      pageToken = page.pageToken;
    } while (pageToken);

    const usersSnap = await db.collection("users").get();
    const registrationPlatforms: Record<string, number> = {};
    const lastPlatforms: Record<string, number> = {};
    const purchaseTypes: Record<string, number> = {};
    const subscriptionTiers: Record<string, number> = {};
    const registeredInVersions: Record<string, number> = {};

    let onboardingCompleted = 0;
    let usersWithActiveSchoolYear = 0;
    let adminAccessActive = 0;
    let usersWithTokens = 0;
    let totalTokens = 0;

    usersSnap.forEach((doc) => {
      const data = doc.data() || {};
      if (data.onboardingCompleted === true) onboardingCompleted += 1;
      if (typeof data.activeSchoolYearId === "string" && data.activeSchoolYearId.trim()) {
        usersWithActiveSchoolYear += 1;
      }
      if (data.adminAccessGranted === true) {
        const expires = data.adminAccessExpiresAt?.toDate?.();
        if (!expires || expires.getTime() > now) {
          adminAccessActive += 1;
        }
      }

      // Legacy token array is handled below for fallback counts

      if (data.registrationPlatform) {
        incrementBucket(registrationPlatforms, data.registrationPlatform);
      }
      if (data.lastPlatform) {
        incrementBucket(lastPlatforms, data.lastPlatform);
      }
      if (data.purchaseType) {
        incrementBucket(purchaseTypes, data.purchaseType);
      }
      if (data.subscriptionTier) {
        incrementBucket(subscriptionTiers, data.subscriptionTier);
      }
      if (data.registeredInVersion) {
        incrementBucket(registeredInVersions, data.registeredInVersion);
      }
    });

    const tokenUsers = new Set<string>();
    try {
      const tokenSnap = await db.collectionGroup("fcmTokens").get();
      totalTokens += tokenSnap.size;
      tokenSnap.forEach((doc) => {
        const userId = doc.ref.parent.parent?.id;
        if (userId) tokenUsers.add(userId);
      });
    } catch (error) {
      console.warn("Failed to read fcmTokens subcollection:", error);
    }

    if (tokenUsers.size > 0) {
      usersWithTokens = tokenUsers.size;
    } else {
      usersSnap.forEach((doc) => {
        const data = doc.data() || {};
        const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
        if (tokens.length > 0) {
          usersWithTokens += 1;
          totalTokens += tokens.length;
        }
      });
    }

    let schoolYearDocCount = 0;
    try {
      const schoolYearsSnap = await db.collectionGroup("schoolYears").get();
      schoolYearDocCount = schoolYearsSnap.size;
    } catch (error) {
      console.warn("School year aggregation failed", error);
    }

    const totalUsers = usersSnap.size;
    const avgTokensPerUser = totalUsers ? totalTokens / totalUsers : 0;
    const avgSchoolYearsPerUser = totalUsers ? schoolYearDocCount / totalUsers : 0;

    return {
      totalUsers,
      authUserCount,
      dau,
      wau,
      mau,
      onboardingCompleted,
      usersWithActiveSchoolYear,
      adminAccessActive,
      usersWithTokens,
      avgTokensPerUser,
      schoolYearDocCount,
      avgSchoolYearsPerUser,
      registrationPlatforms,
      lastPlatforms,
      purchaseTypes,
      subscriptionTiers,
      registeredInVersions,
    };
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
            contents: [{ parts: [{ text: prompt }] }],
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

type TokenEntry = {
  token: string;
  userId?: string;
  ref?: any;
  legacyUserId?: string;
};

const normalizeToken = (value: any): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const fetchUserTokenEntries = async (
  db: admin.firestore.Firestore,
  userId: string
): Promise<TokenEntry[]> => {
  const entries: TokenEntry[] = [];
  const seen = new Set<string>();

  const tokenSnap = await db.collection("users").doc(userId).collection("fcmTokens").get();
  tokenSnap.forEach((doc) => {
    const token = normalizeToken(doc.data()?.token);
    if (!token || seen.has(token)) return;
    seen.add(token);
    entries.push({ token, ref: doc.ref, userId });
  });

  const userDoc = await db.collection("users").doc(userId).get();
  const legacyTokens = Array.isArray(userDoc.data()?.fcmTokens) ? userDoc.data()?.fcmTokens : [];
  legacyTokens.forEach((token: any) => {
    const normalized = normalizeToken(token);
    if (!normalized || seen.has(normalized)) return;
    seen.add(normalized);
    entries.push({ token: normalized, legacyUserId: userId, userId });
  });

  return entries;
};

const cleanupInvalidTokenEntries = async (
  db: admin.firestore.Firestore,
  entries: TokenEntry[],
  invalidIndices: number[]
) => {
  const refsToDelete: any[] = [];
  const legacyMap: Record<string, Set<string>> = {};

  invalidIndices.forEach((idx) => {
    const entry = entries[idx];
    if (!entry) return;
    if (entry.ref) {
      refsToDelete.push(entry.ref);
    } else if (entry.legacyUserId) {
      if (!legacyMap[entry.legacyUserId]) {
        legacyMap[entry.legacyUserId] = new Set();
      }
      legacyMap[entry.legacyUserId].add(entry.token);
    }
  });

  await Promise.all(refsToDelete.map((ref) => ref.delete().catch(() => undefined)));
  const legacyUpdates = Object.entries(legacyMap).map(([userId, tokens]) => {
    return db.collection("users").doc(userId).update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...Array.from(tokens))
    }).catch(() => undefined);
  });
  await Promise.all(legacyUpdates);
};

const fetchBroadcastTokenEntries = async (
  db: admin.firestore.Firestore,
  platforms: BroadcastPlatform
): Promise<TokenEntry[]> => {
  const entries: TokenEntry[] = [];
  const seen = new Set<string>();

  let tokenQuery: admin.firestore.Query = db.collectionGroup("fcmTokens");
  if (platforms !== "all") {
    tokenQuery = tokenQuery.where("platform", "==", platforms);
  }
  const tokenSnap = await tokenQuery.get();
  tokenSnap.forEach((doc) => {
    const token = normalizeToken(doc.data()?.token);
    if (!token || seen.has(token)) return;
    seen.add(token);
    const userId = doc.ref.parent.parent?.id;
    entries.push({ token, ref: doc.ref, userId });
  });

  let userQuery: admin.firestore.Query = db.collection("users");
  if (platforms !== "all") {
    userQuery = userQuery.where("lastPlatform", "==", platforms);
  }
  const userSnap = await userQuery.get();
  userSnap.forEach((doc) => {
    const legacyTokens = Array.isArray(doc.data().fcmTokens) ? doc.data().fcmTokens : [];
    legacyTokens.forEach((token: any) => {
      const normalized = normalizeToken(token);
      if (!normalized || seen.has(normalized)) return;
      seen.add(normalized);
      entries.push({ token: normalized, legacyUserId: doc.id, userId: doc.id });
    });
  });

  return entries;
};

const fetchUserSettingsMap = async (
  db: admin.firestore.Firestore,
  userIds: string[]
): Promise<Record<string, any>> => {
  const map: Record<string, any> = {};
  const batchSize = 10;
  for (let i = 0; i < userIds.length; i += batchSize) {
    const batch = userIds.slice(i, i + batchSize);
    try {
      const snap = await db.collection("users")
        .where(admin.firestore.FieldPath.documentId(), "in", batch)
        .get();
      snap.forEach((doc) => {
        map[doc.id] = doc.data();
      });
    } catch (error) {
      console.error("[fetchUserSettingsMap] Failed to fetch user batch:", error);
    }
  }
  return map;
};

const sendBroadcastPush = async (
  data: BroadcastNotificationRequest
): Promise<{ sentCount: number; message?: string }> => {
  const { title, body, platforms } = data;
  const db = admin.firestore();

  // 1. Fetch tokens (subcollection + legacy fallback)
  const tokenEntries = await fetchBroadcastTokenEntries(db, platforms);
  if (tokenEntries.length === 0) {
    return { sentCount: 0, message: "No tokens found." };
  }

  const userIds = Array.from(new Set(tokenEntries.map((entry) => entry.userId).filter(Boolean))) as string[];
  const settingsMap = await fetchUserSettingsMap(db, userIds);
  const filteredEntries = tokenEntries.filter((entry) => {
    const userId = entry.userId;
    if (!userId) return true;
    return settingsMap[userId]?.broadcastNotificationsEnabled !== false;
  });

  if (filteredEntries.length === 0) {
    return { sentCount: 0, message: "Broadcast notifications disabled." };
  }

  // 2. Send in batches of 500 (FCM limit for multicast)
  const batches = [];
  for (let i = 0; i < filteredEntries.length; i += 500) {
    batches.push(filteredEntries.slice(i, i + 500));
  }

  let totalSent = 0;
  for (const entryBatch of batches) {
    const tokenBatch = entryBatch.map((entry) => entry.token);
    const message: admin.messaging.MulticastMessage = {
      tokens: tokenBatch,
      notification: { title, body },
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
      if (response.failureCount > 0) {
        const invalidIndices: number[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success && (
            resp.error?.code === "messaging/invalid-registration-token" ||
            resp.error?.code === "messaging/registration-token-not-registered"
          )) {
            invalidIndices.push(idx);
          }
        });
        if (invalidIndices.length > 0) {
          await cleanupInvalidTokenEntries(db, entryBatch, invalidIndices);
        }
      }
    } catch (error) {
      console.error("Batch send error:", error);
    }
  }

  return { sentCount: totalSent };
};

/**
 * Sends a broadcast push notification to all users matching the platform.
 */
export const sendBroadcastNotification = onCall<BroadcastNotificationRequest>(
  { region: "europe-west3", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const { title, body, platforms } = request.data;
    if (!title || !body || !platforms) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }

    const result = await sendBroadcastPush({ title, body, platforms });
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
  { region: "europe-west3", schedule: "every 1 minutes" },
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
  { region: "europe-west3" },
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
    if (userData?.customNotificationsEnabled === false) {
      return { success: false, message: "Custom notifications disabled" };
    }

    const tokenEntries = await fetchUserTokenEntries(db, userId);
    const tokens = tokenEntries.map((entry) => entry.token);

    if (tokens.length === 0) {
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
        const invalidIndices: number[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success && (
            resp.error?.code === "messaging/invalid-registration-token" ||
            resp.error?.code === "messaging/registration-token-not-registered"
          )) {
            invalidIndices.push(idx);
          }
        });
        if (invalidIndices.length > 0) {
          await cleanupInvalidTokenEntries(db, tokenEntries, invalidIndices);
          console.log(`Removed ${invalidIndices.length} invalid tokens.`);
        }
      }

      return { success: true, sentCount: response.successCount };
    } catch (error) {
      console.error("Error sending notification:", error);
      throw new Error("Failed to send notification");
    }
  }
);

// --- 0. Core Notification Delivery ---
const LIVE_ACTIVITY_ENABLED = false;

/**
 * HTTP Function triggered by Cloud Tasks to send a scheduled notification.
 */
export const sendScheduledNotification = onRequest(
  { region: "europe-west3" },
  async (req, res) => {
    const { userId, title, body, action, sheetType, payloadId, summaryDate } = req.body;

    if (!userId || !title || !body) {
      console.error("Missing required fields in sendScheduledNotification:", req.body);
      res.status(400).send("Missing required fields");
      return;
    }

    try {
      const db = admin.firestore();
      const userDoc = await db.collection("users").doc(userId).get();

      if (!userDoc.exists) {
        console.warn(`User ${userId} not found. Stopping retry.`);
        res.status(200).send("User not found");
        return;
      }

      const userData = userDoc.data();
      if (userData?.standardRemindersEnabled === false) {
        res.status(200).send("Reminders disabled");
        return;
      }

      if (sheetType === "daily_summary" && typeof summaryDate === "string" && summaryDate.trim()) {
        const counts = await fetchCountsForDate(userId, summaryDate.trim(), userData);
        const total = counts.exams + counts.homeworks;
        if (total === 0) {
          res.status(200).send("No items for date");
          return;
        }
        req.body.body = formatDailySummaryBody(counts.exams, counts.homeworks);
        req.body.title = "Morgen anstehend";
      }

      const tokenEntries = await fetchUserTokenEntries(db, userId);
      const tokens = tokenEntries.map((entry) => entry.token);

      if (tokens.length === 0) {
        console.log(`No tokens found for user ${userId}.`);
        res.status(200).send("No tokens");
        return;
      }

      const notificationData: { [key: string]: string } = {};
      if (action) notificationData.action = action;
      if (sheetType) notificationData.sheetType = sheetType;
      if (summaryDate) notificationData.summaryDate = summaryDate;
      if (payloadId) notificationData.id = payloadId;

      const finalTitle = req.body.title || title;
      const finalBody = req.body.body || body;

      const message: admin.messaging.MulticastMessage = {
        tokens,
        notification: { title: finalTitle, body: finalBody },
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

      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`Scheduled notification sent to ${userId}: ${response.successCount} success`);

      // Cleanup invalid tokens
      if (response.failureCount > 0) {
        const invalidIndices: number[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success && (
            resp.error?.code === "messaging/invalid-registration-token" ||
            resp.error?.code === "messaging/registration-token-not-registered"
          )) {
            invalidIndices.push(idx);
          }
        });
        if (invalidIndices.length > 0) {
          await cleanupInvalidTokenEntries(db, tokenEntries, invalidIndices);
        }
      }

      res.status(200).send("Success");
    } catch (error) {
      console.error("Error in sendScheduledNotification:", error);
      res.status(500).send("Internal Error");
    }
  }
);

/**
 * HTTP Function triggered by Cloud Tasks to send the Push-to-Start notification.
 */
export const sendLiveActivityPush = onRequest(
  { region: "europe-west3" },
  async (req, res) => {
    if (!LIVE_ACTIVITY_ENABLED) {
      res.status(200).send("Live activities disabled");
      return;
    }
    const { userId, examId, notificationPayload } = req.body;
    console.log(`Sending Native Live Activity Push for Exam ${examId} to User ${userId}`);

    try {
      const db = admin.firestore();

      // 1. Get Push-to-Start Token (Hex string from iOS)
      // Path: users/{uid}/liveActivityTokens/examCountdown
      const tokenDoc = await db.collection("users").doc(userId).collection("liveActivityTokens").doc("examCountdown").get();

      if (!tokenDoc.exists) {
        console.warn(`No Push-to-Start token for user ${userId}. Skipping.`);
        // We return 200 so Cloud Tasks doesn't retry indefinitely
        res.status(200).send("No token found");
        return;
      }

      const pushToken = tokenDoc.data()?.token;
      if (!pushToken) {
        console.warn("Empty token field.");
        res.status(200).send("Empty token");
        return;
      }

      // 2. Configure APNs Provider
      // Storing keys in code is not best practice but requested for this immediate fix.
      const options: apn.ProviderOptions = {
        token: {
          key: `-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg+gBrd5x+qGd4vvci
rZeIPF007rTTHraxS+LEJplErT6gCgYIKoZIzj0DAQehRANCAATNVgz8dE/GaO4B
5tQaYcuB2BnU2GJNp1i4BQwc9flhMnetJQcB+0ef7sJ1jqUgOxakZ8c+pkiKh4fq
QOS6kpaQ
-----END PRIVATE KEY-----`,
          keyId: "C9QQ69JH9X",
          teamId: "48BM67TY9G",
        },
        production: false // Set to true for TestFlight/App Store builds
      };

      const apnProvider = new apn.Provider(options);

      // 3. Construct Notification
      const notification = new apn.Notification();

      // Override startDate with current time (at delivery) to ensure countdown works
      const deliveryNowSeconds = Math.floor(Date.now() / 1000);

      // Get examDate from the content-state (Unix timestamp in seconds)
      const examDateSeconds = notificationPayload.aps["content-state"]?.examDate;
      const dismissalDateSeconds = examDateSeconds ? examDateSeconds + (4 * 3600) : deliveryNowSeconds;

      // CRITICAL: attributes-type and attributes must be at the ROOT level, not inside aps.
      const updatedPayload = {
        "attributes-type": notificationPayload.aps["attributes-type"],
        "attributes": notificationPayload.aps["attributes"],
        aps: {
          "event": "start",
          "timestamp": deliveryNowSeconds,
          "stale-date": examDateSeconds, // Unix timestamp in seconds
          "dismissal-date": dismissalDateSeconds, // Unix timestamp in seconds
          "relevance-score": 100,
          "content-state": {
            ...notificationPayload.aps["content-state"],
            "startDate": deliveryNowSeconds, // Override to current delivery time in seconds
          },
          "alert": notificationPayload.aps["alert"]
        }
      };

      console.log(`[sendLiveActivityPush] Full Payload (JSON): ${JSON.stringify(updatedPayload)}`);

      // Set the full payload - rawPayload must include the "aps" key wrapper
      notification.rawPayload = updatedPayload;
      notification.priority = 10; // Immediate delivery

      // Topic must be {BundleID}.push-type.liveactivity
      notification.topic = "de.christophlabestin.noten-manager-ios.push-type.liveactivity";
      // Override headers to include apns-push-type (required for Live Activity)
      // We must wrap the function because provider.js calls notification.headers()
      const originalHeaders = (notification as any).headers.bind(notification);
      (notification as any).headers = () => {
        const headers = originalHeaders();
        // Mandatory for Live Activities
        headers["apns-push-type"] = "liveactivity";
        headers["apns-priority"] = "10";
        return headers;
      };

      // 4. Send
      // Note: check if pushToken is legit hex. apn expects hex string or Buffer.
      const result = await apnProvider.send(notification, pushToken);

      // Log results
      if (result.failed.length > 0) {
        console.error("APNs Send Failed:", JSON.stringify(result.failed));
        // Check for 'BadDeviceToken' to cleanup?
      } else {
        console.log("APNs Send Success:", result.sent.length);
      }

      apnProvider.shutdown();

      if (result.sent.length > 0) {
        res.status(200).send("Sent via APNs");
      } else {
        // 500 triggers retry. If it's a structural error (BadToken), we should return 200/400 to stop retry.
        // For now, let's return 200 if it failed to avoid spamming logs if the token is just old.
        res.status(200).send("APNs Failed (Stopped Retry)");
      }
    } catch (error) {
      console.error("Error in sendLiveActivityPush:", error);
      res.status(500).send("Internal Error");
    }
  }
);

/**
 * Updates the Cloud Task when an exam is created/updated/deleted.
 * Triggers:
 * - Personal: users/{userId}/schoolYears/{yearId}/exams/{examId}
 * - Group: groups/{groupId}/exams/{examId}
 * - Class: classes/{classId}/exams/{examId}
 * - Class Course: classes/{classId}/courses/{courseId}/exams/{examId} (Handled by class fetch)
 * - WPF: wahlpflichtfachGroups/{groupId}/exams/{examId}
 */

// --- 1. Helper: Manage Task for a List of Users ---


// --- 1. Helper: Manage Task for a List of Users ---

/**
 * Computes a deterministic configuration for the task based on exam data.
 * Returns null if the task should not exist (completed, invalid date, etc.).
 */
/**
 * Computes a deterministic configuration for the task based on exam data.
 * @param {string} userId - The ID of the user.
 * @param {string} examId - The ID of the exam.
 * @param {admin.firestore.DocumentData | undefined} examData - The Firestore data of the exam.
 * @return {object | null} The task configuration object or null.
 */
const getTaskConfig = (
  userId: string,
  examId: string,
  examData: admin.firestore.DocumentData | undefined
) => {
  if (!examData) return null;

  const examDate = examData.date as admin.firestore.Timestamp | undefined;
  const isCompleted = examData.isCompleted === true;

  // 1. Validation & Timing
  if (!examDate || isCompleted) return null;

  const examMillis = examDate.toMillis();
  const triggerMillis = examMillis - (90 * 60 * 1000);
  const nowMillis = Date.now();

  // If trigger time is in the past (allowing 5 min buffer), we skip creating it.
  // Note: For existing tasks, if they become "past", we might want to delete them?
  // But here we return null, meaning "No Task".
  if (triggerMillis < nowMillis - (5 * 60 * 1000)) {
    return null;
  }

  const scheduleTime = { seconds: Math.floor(triggerMillis / 1000) };

  // 2. Construct Payload (Deterministic for Hashing)
  const examDateSeconds = Math.floor(examMillis / 1000);
  const startDateSeconds = Math.floor(triggerMillis / 1000);

  // We exclude non-deterministic fields like 'timestamp' from the hash calculation
  const apsPayload = {
    "event": "start",
    "content-state": {
      "examDate": examDateSeconds,
      "title": examData.title || "Klausur",
      "subject": examData.subjectName || "",
      "startDate": startDateSeconds,
      "duration": 90 * 60,
    },
    "attributes-type": "ExamCountdownAttributes",
    "attributes": {
      "examId": examId,
      "title": examData.title || "Klausur",
      "subject": examData.subjectName || "",
      "accent": "blue", // Hardcoded per current logic
    },
    "alert": {
      "title": "Klausur in 90 Minuten",
      "body": `${examData.title || "Prüfung"} ${examData.subjectName ? "in " + examData.subjectName : ""}`,
      "sound": "default",
    },
  };

  // 3. Compute Hash
  const hashInput = JSON.stringify({ userId, examId, apsPayload });
  const hash = crypto.createHash("sha256").update(hashInput).digest("hex").substring(0, 16);

  // 4. Construct Final Task ID
  const taskId = `start-${userId}-${examId}-${hash}`;

  // 5. Construct Final Notification Payload
  const notificationPayload = {
    aps: {
      ...apsPayload,
    }
  };

  return { taskId, scheduleTime, notificationPayload };
};


// --- 1. Helper: Manage Scheduled Reminder Task ---

interface DailySummaryConfig {
  dateKey: string;
  scheduleTime: { seconds: number };
}

const getUserTimeZoneOffsetMinutes = (userSettings: any): number | null => {
  const raw = userSettings?.timeZoneOffsetMinutes;
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.trunc(raw);
  }
  return null;
};

const getUserTimeZoneId = (userSettings: any): string | null => {
  const raw = userSettings?.timeZoneId;
  if (typeof raw === "string" && raw.trim()) {
    return raw.trim();
  }
  return null;
};

const getOffsetMinutesForTimeZone = (dateUtc: Date, timeZoneId: string): number | null => {
  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timeZoneId,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false
    });
    const parts = formatter.formatToParts(dateUtc);
    const map: Record<string, string> = {};
    for (const part of parts) {
      if (part.type !== "literal") {
        map[part.type] = part.value;
      }
    }
    const asUtc = Date.UTC(
      Number(map.year),
      Number(map.month) - 1,
      Number(map.day),
      Number(map.hour),
      Number(map.minute),
      Number(map.second)
    );
    return Math.round((asUtc - dateUtc.getTime()) / 60000);
  } catch (error) {
    console.warn(`[getOffsetMinutesForTimeZone] Failed for ${timeZoneId}:`, error);
    return null;
  }
};

const resolveReminderSettings = (data: any) => ({
  standardRemindersEnabled: data?.standardRemindersEnabled !== false,
  homeworkReminderHour: typeof data?.homeworkReminderHour === "number" ? data.homeworkReminderHour : 19,
  homeworkReminderMinute: typeof data?.homeworkReminderMinute === "number" ? data.homeworkReminderMinute : 0,
  timeZoneOffsetMinutes: getUserTimeZoneOffsetMinutes(data),
  timeZoneId: getUserTimeZoneId(data)
});

const pad2 = (value: number) => value.toString().padStart(2, "0");

const formatDateKeyForUser = (dateUtc: Date, settings: ReturnType<typeof resolveReminderSettings>): string | null => {
  if (settings.timeZoneId) {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: settings.timeZoneId,
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    });
    const formatted = formatter.format(dateUtc);
    return formatted.replace(/-/g, "");
  }
  const offset = settings.timeZoneOffsetMinutes ?? 0;
  const local = new Date(dateUtc.getTime() + offset * 60_000);
  const year = local.getUTCFullYear();
  const month = local.getUTCMonth() + 1;
  const day = local.getUTCDate();
  return `${year}${pad2(month)}${pad2(day)}`;
};

const parseDateKey = (dateKey: string): { year: number; month: number; day: number } | null => {
  if (!/^\d{8}$/.test(dateKey)) return null;
  const year = Number(dateKey.slice(0, 4));
  const month = Number(dateKey.slice(4, 6));
  const day = Number(dateKey.slice(6, 8));
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) return null;
  return { year, month, day };
};

const localDateTimeToUtc = (
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  settings: ReturnType<typeof resolveReminderSettings>
): Date => {
  const baseUtc = new Date(Date.UTC(year, month - 1, day, hour, minute, 0));
  let offsetMinutes: number | null = null;
  if (settings.timeZoneId) {
    offsetMinutes = getOffsetMinutesForTimeZone(baseUtc, settings.timeZoneId);
  }
  if (offsetMinutes == null) {
    offsetMinutes = settings.timeZoneOffsetMinutes ?? 0;
  }
  return new Date(baseUtc.getTime() - offsetMinutes * 60_000);
};

const buildDailySummaryConfigFromDateKey = (
  dateKey: string,
  settings: ReturnType<typeof resolveReminderSettings>
): DailySummaryConfig | null => {
  if (!settings.standardRemindersEnabled) return null;
  const parts = parseDateKey(dateKey);
  if (!parts) return null;

  const localMidnightUtc = new Date(Date.UTC(parts.year, parts.month - 1, parts.day, 0, 0, 0));
  const previousLocalMidnightUtc = new Date(localMidnightUtc.getTime() - 24 * 60 * 60 * 1000);
  const prevYear = previousLocalMidnightUtc.getUTCFullYear();
  const prevMonth = previousLocalMidnightUtc.getUTCMonth() + 1;
  const prevDay = previousLocalMidnightUtc.getUTCDate();

  const reminderUtc = localDateTimeToUtc(
    prevYear,
    prevMonth,
    prevDay,
    settings.homeworkReminderHour,
    settings.homeworkReminderMinute,
    settings
  );

  if (reminderUtc <= new Date()) return null;
  return {
    dateKey,
    scheduleTime: { seconds: Math.floor(reminderUtc.getTime() / 1000) }
  };
};

const buildDailySummaryConfigFromDate = (
  dateUtc: Date,
  settings: ReturnType<typeof resolveReminderSettings>
): DailySummaryConfig | null => {
  if (!settings.standardRemindersEnabled) return null;
  const dateKey = formatDateKeyForUser(dateUtc, settings);
  if (!dateKey) return null;
  return buildDailySummaryConfigFromDateKey(dateKey, settings);
};

const extractItemDate = (
  itemData: admin.firestore.DocumentData | undefined,
  itemType: "exam" | "homework"
): Date | null => {
  if (!itemData) return null;
  if (itemData.isCompleted === true) return null;
  const dateField = itemType === "exam" ? itemData.date : itemData.dueDate;
  if (!dateField) return null;
  return (dateField as admin.firestore.Timestamp).toDate();
};

const scheduleDailySummaryTask = async (
  userId: string,
  config: DailySummaryConfig,
  tasksClient: CloudTasksClient,
  queuePath: string,
  serviceUrl: string
) => {
  const taskId = `daily-${userId}-${config.dateKey}`;
  const taskName = `${queuePath}/tasks/${taskId}`;

  try {
    await tasksClient.deleteTask({ name: taskName });
  } catch (e) {
    // ignore
  }

  const taskPayload = {
    userId,
    title: "Tagesübersicht",
    body: "Morgen stehen Aufgaben oder Prüfungen an.",
    action: "OPEN_SHEET",
    sheetType: "daily_summary",
    summaryDate: config.dateKey
  };

  const task = {
    httpRequest: {
      httpMethod: "POST" as const,
      url: serviceUrl,
      headers: { "Content-Type": "application/json" },
      body: Buffer.from(JSON.stringify(taskPayload)).toString("base64"),
    },
    scheduleTime: config.scheduleTime,
    name: taskName,
  };

  try {
    await tasksClient.createTask({ parent: queuePath, task });
    console.log(`[dailySummary] Scheduled ${taskId} for ${userId} at ${new Date(config.scheduleTime.seconds * 1000).toISOString()}`);
  } catch (e: any) {
    if (e.code !== 6) console.error("Cloud Task Creation Error:", e);
  }
};

const manageScheduledReminderTasks = async (
  _itemId: string,
  _oldItemData: admin.firestore.DocumentData | undefined,
  newItemData: admin.firestore.DocumentData | undefined,
  audience: string[],
  itemType: "exam" | "homework"
) => {
  if (audience.length === 0) return;
  if (!newItemData) return;
  void _itemId;
  void _oldItemData;

  const db = admin.firestore();
  const tasksClient = new CloudTasksClient();
  const project = process.env.GCLOUD_PROJECT || "";
  const queue = "scheduled-reminders";
  const location = "europe-west3";
  const queuePath = tasksClient.queuePath(project, location, queue);
  const serviceUrl = `https://${location}-${project}.cloudfunctions.net/sendScheduledNotification`;

  // Fetch all user settings in batches of 10 (Firestore "in" limit)
  const userSettingsMap: Record<string, any> = {};
  const batchSize = 10;
  for (let i = 0; i < audience.length; i += batchSize) {
    const batch = audience.slice(i, i + batchSize);
    try {
      const snap = await db.collection("users")
        .where(admin.firestore.FieldPath.documentId(), "in", batch)
        .get();
      snap.forEach((doc) => {
        userSettingsMap[doc.id] = doc.data();
      });
    } catch (error) {
      console.error("[manageScheduledReminderTasks] Failed to fetch user settings batch:", error);
    }
  }

  for (const userId of audience) {
    let settings = userSettingsMap[userId];
    if (!settings) {
      try {
        const doc = await db.collection("users").doc(userId).get();
        settings = doc.data();
      } catch (error) {
        console.warn(`[manageScheduledReminderTasks] Failed to fetch user settings for ${userId}:`, error);
      }
    }
    const dateUtc = extractItemDate(newItemData, itemType);
    if (!dateUtc) continue;
    const config = buildDailySummaryConfigFromDate(dateUtc, settings);
    if (!config) continue;
    await scheduleDailySummaryTask(userId, config, tasksClient, queuePath, serviceUrl);
  }
};

const fetchUpcomingDocs = async (ref: any, dateField: string) => {
  const now = admin.firestore.Timestamp.now();
  try {
    return await ref.where(dateField, ">", now).get();
  } catch (error) {
    console.error(`[fetchUpcomingDocs] Failed to fetch ${ref.path} (${dateField}):`, error);
    return null;
  }
};

const buildDateRangeForDateKey = (
  dateKey: string,
  settings: ReturnType<typeof resolveReminderSettings>
): { start: Date; end: Date } | null => {
  const parts = parseDateKey(dateKey);
  if (!parts) return null;

  const startUtc = localDateTimeToUtc(parts.year, parts.month, parts.day, 0, 0, settings);
  const localMidnightUtc = new Date(Date.UTC(parts.year, parts.month - 1, parts.day, 0, 0, 0));
  const nextLocalMidnightUtc = new Date(localMidnightUtc.getTime() + 24 * 60 * 60 * 1000);
  const nextYear = nextLocalMidnightUtc.getUTCFullYear();
  const nextMonth = nextLocalMidnightUtc.getUTCMonth() + 1;
  const nextDay = nextLocalMidnightUtc.getUTCDate();
  const endUtc = localDateTimeToUtc(nextYear, nextMonth, nextDay, 0, 0, settings);

  return { start: startUtc, end: endUtc };
};

const fetchCountsForDate = async (
  userId: string,
  dateKey: string,
  userData: any
): Promise<{ exams: number; homeworks: number }> => {
  const settings = resolveReminderSettings(userData);
  const range = buildDateRangeForDateKey(dateKey, settings);
  if (!range) return { exams: 0, homeworks: 0 };

  const context = await fetchUserContextInfo(userId, userData);
  const { db, userRef, classIds, subscribedCourseIds, groupIds, yearIds, activeSchoolYearId } = context;
  const yearIdsToScan = activeSchoolYearId ? [activeSchoolYearId] : yearIds;

  const queryCount = async (ref: any, field: string): Promise<number> => {
    try {
      const snap = await ref
        .where(field, ">=", range.start)
        .where(field, "<", range.end)
        .get();
      return snap.docs.filter((doc: admin.firestore.QueryDocumentSnapshot) => doc.data()?.isCompleted !== true).length;
    } catch (error) {
      console.error(`[fetchCountsForDate] Query failed for ${ref.path}:`, error);
      return 0;
    }
  };

  let exams = 0;
  let homeworks = 0;

  for (const yearId of yearIdsToScan) {
    const yearRef = userRef.collection("schoolYears").doc(yearId);
    exams += await queryCount(yearRef.collection("exams"), "date");
    homeworks += await queryCount(yearRef.collection("homeworks"), "dueDate");
  }

  for (const classId of classIds) {
    const classRef = db.collection("classes").doc(classId);
    exams += await queryCount(classRef.collection("exams"), "date");
    homeworks += await queryCount(classRef.collection("homeworks"), "dueDate");

    if (subscribedCourseIds.size > 0) {
      const coursesSnap = await classRef.collection("courses").get();
      for (const courseDoc of coursesSnap.docs) {
        if (!subscribedCourseIds.has(courseDoc.id)) continue;
        exams += await queryCount(courseDoc.ref.collection("exams"), "date");
        homeworks += await queryCount(courseDoc.ref.collection("homeworks"), "dueDate");
      }
    }
  }

  for (const groupId of groupIds) {
    const groupRef = db.collection("groups").doc(groupId);
    exams += await queryCount(groupRef.collection("exams"), "date");
    homeworks += await queryCount(groupRef.collection("homeworks"), "dueDate");

    const wpfRef = db.collection("wahlpflichtfachGroups").doc(groupId);
    exams += await queryCount(wpfRef.collection("exams"), "date");
    homeworks += await queryCount(wpfRef.collection("homeworks"), "dueDate");
  }

  return { exams, homeworks };
};

const formatDailySummaryBody = (examCount: number, homeworkCount: number): string => {
  const parts: string[] = [];
  if (examCount > 0) {
    parts.push(`${examCount} Prüfung${examCount === 1 ? "" : "en"}`);
  }
  if (homeworkCount > 0) {
    parts.push(`${homeworkCount} Hausaufgabe${homeworkCount === 1 ? "" : "n"}`);
  }
  if (parts.length === 0) {
    return "Morgen stehen Aufgaben oder Prüfungen an.";
  }
  if (parts.length === 1) {
    return `Morgen steht ${parts[0]} an.`;
  }
  return `Morgen stehen ${parts[0]} und ${parts[1]} an.`;
};


const manageExamTask = async (
  examId: string,
  oldExamData: admin.firestore.DocumentData | undefined,
  newExamData: admin.firestore.DocumentData | undefined,
  audience: string[]
) => {
  if (!LIVE_ACTIVITY_ENABLED) return;
  const tasksClient = new CloudTasksClient();
  const project = process.env.GCLOUD_PROJECT || "";
  const queue = "exam-live-activities";
  const location = "europe-west3";
  const queuePath = tasksClient.queuePath(project, location, queue);
  const serviceUrl = `https://${location}-${project}.cloudfunctions.net/sendLiveActivityPush`;

  for (const userId of audience) {
    // A. Clean up LEGACY task name (start-uid-examid without hash)
    // This is crucial for migration to prevent zombie tasks.
    const legacyTaskId = `start-${userId}-${examId}`;
    const legacyTaskName = `${queuePath}/tasks/${legacyTaskId}`;
    try {
      await tasksClient.deleteTask({ name: legacyTaskName });
    } catch (e: any) {
      // Ignore NOT_FOUND (code 5) or similar
    }

    // B. Calculate Configs
    const oldConfig = getTaskConfig(userId, examId, oldExamData);
    const newConfig = getTaskConfig(userId, examId, newExamData);

    console.log(`[manageExamTask] User ${userId}, Exam ${examId}: oldHash=${oldConfig?.taskId ?? 'null'}, newHash=${newConfig?.taskId ?? 'null'}`);

    // C. Check for Unchanged (Idempotency)
    if (oldConfig?.taskId === newConfig?.taskId) {
      if (newConfig) {
        console.log(`[manageExamTask] Task ${newConfig.taskId} unchanged (idempotent skip).`);
      }
      continue;
    }

    // D. Delete Old Task (if it existed and is different)
    if (oldConfig) {
      const oldTaskName = `${queuePath}/tasks/${oldConfig.taskId}`;
      try {
        await tasksClient.deleteTask({ name: oldTaskName });
        console.log(`Deleted old task ${oldConfig.taskId}`);
      } catch (e: any) {
        // Ignore if already gone
      }
    }

    // E. Create New Task
    if (newConfig) {
      const newTaskName = `${queuePath}/tasks/${newConfig.taskId}`;

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: serviceUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify({
            userId,
            examId,
            notificationPayload: newConfig.notificationPayload
          })).toString("base64"),
        },
        scheduleTime: newConfig.scheduleTime,
        name: newTaskName
      };

      try {
        await tasksClient.createTask({ parent: queuePath, task });
        console.log(`Scheduled task ${newConfig.taskId} at ${new Date(newConfig.scheduleTime.seconds * 1000).toISOString()}`);
      } catch (error: any) {
        // Handle ALREADY_EXISTS (code 6) gracefully - the task is already scheduled
        if (error.code === 6) {
          console.log(`Task ${newConfig.taskId} already exists (expected if unchanged).`);
        } else {
          console.error(`Failed to create task ${newConfig.taskId}:`, error);
        }
      }
    }
  }
};

const haveReminderSettingsChanged = (before: any, after: any): boolean => {
  const b = resolveReminderSettings(before);
  const a = resolveReminderSettings(after);
  return b.standardRemindersEnabled !== a.standardRemindersEnabled ||
    b.homeworkReminderHour !== a.homeworkReminderHour ||
    b.homeworkReminderMinute !== a.homeworkReminderMinute ||
    b.timeZoneOffsetMinutes !== a.timeZoneOffsetMinutes ||
    b.timeZoneId !== a.timeZoneId;
};

const fetchUserContextInfo = async (userId: string, userData?: any) => {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(userId);
  const schoolYearsSnap = await userRef.collection("schoolYears").get();

  const classIds: Set<string> = new Set();
  const subscribedCourseIds: Set<string> = new Set();
  const groupIds: Set<string> = new Set();
  const yearIds: string[] = [];

  if (Array.isArray(userData?.groupIds)) {
    userData.groupIds.forEach((id: any) => {
      if (typeof id === "string") groupIds.add(id);
    });
  }

  const activeSchoolYearId: string | null = typeof userData?.activeSchoolYearId === "string" ? userData.activeSchoolYearId : null;

  schoolYearsSnap.forEach((doc) => {
    yearIds.push(doc.id);
    const data = doc.data() || {};
    if (typeof data.activeClassId === "string") classIds.add(data.activeClassId);
    if (Array.isArray(data.classIds)) {
      data.classIds.forEach((id: any) => {
        if (typeof id === "string") classIds.add(id);
      });
    }
    if (Array.isArray(data.groupIds)) {
      data.groupIds.forEach((id: any) => {
        if (typeof id === "string") groupIds.add(id);
      });
    }
    if (Array.isArray(data.subscribedCourseIds)) {
      data.subscribedCourseIds.forEach((id: any) => {
        if (typeof id === "string") subscribedCourseIds.add(id);
      });
    }
  });

  return {
    db,
    userRef,
    schoolYearsSnap,
    classIds,
    subscribedCourseIds,
    groupIds,
    yearIds,
    activeSchoolYearId
  };
};

const rescheduleUserReminders = async (userId: string, before: any, after: any) => {
  const tasksClient = new CloudTasksClient();
  const project = process.env.GCLOUD_PROJECT || "";
  const queue = "scheduled-reminders";
  const location = "europe-west3";
  const queuePath = tasksClient.queuePath(project, location, queue);
  const serviceUrl = `https://${location}-${project}.cloudfunctions.net/sendScheduledNotification`;

  const newSettings = resolveReminderSettings(after);
  if (!newSettings.standardRemindersEnabled) return;

  const context = await fetchUserContextInfo(userId, after);
  const { db, userRef, classIds, subscribedCourseIds, groupIds, yearIds, activeSchoolYearId } = context;

  const dateKeys: Set<string> = new Set();
  const yearIdsToScan = activeSchoolYearId ? [activeSchoolYearId] : yearIds;

  const addDateKeyFromDoc = (data: admin.firestore.DocumentData | undefined, itemType: "exam" | "homework") => {
    const dateUtc = extractItemDate(data, itemType);
    if (!dateUtc) return;
    const key = formatDateKeyForUser(dateUtc, newSettings);
    if (key) dateKeys.add(key);
  };

  for (const yearId of yearIdsToScan) {
    const yearRef = userRef.collection("schoolYears").doc(yearId);
    const examsSnap = await fetchUpcomingDocs(yearRef.collection("exams"), "date");
    examsSnap?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "exam"));
    const hwSnap = await fetchUpcomingDocs(yearRef.collection("homeworks"), "dueDate");
    hwSnap?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "homework"));
  }

  for (const classId of classIds) {
    const classRef = db.collection("classes").doc(classId);
    const classExams = await fetchUpcomingDocs(classRef.collection("exams"), "date");
    classExams?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "exam"));
    const classHomeworks = await fetchUpcomingDocs(classRef.collection("homeworks"), "dueDate");
    classHomeworks?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "homework"));

    if (subscribedCourseIds.size > 0) {
      const coursesSnap = await classRef.collection("courses").get();
      for (const courseDoc of coursesSnap.docs) {
        if (!subscribedCourseIds.has(courseDoc.id)) continue;
        const courseExams = await fetchUpcomingDocs(courseDoc.ref.collection("exams"), "date");
        courseExams?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "exam"));
        const courseHomeworks = await fetchUpcomingDocs(courseDoc.ref.collection("homeworks"), "dueDate");
        courseHomeworks?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "homework"));
      }
    }
  }

  for (const groupId of groupIds) {
    const groupRef = db.collection("groups").doc(groupId);
    const groupExams = await fetchUpcomingDocs(groupRef.collection("exams"), "date");
    groupExams?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "exam"));
    const groupHomeworks = await fetchUpcomingDocs(groupRef.collection("homeworks"), "dueDate");
    groupHomeworks?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "homework"));

    const wpfRef = db.collection("wahlpflichtfachGroups").doc(groupId);
    const wpfExams = await fetchUpcomingDocs(wpfRef.collection("exams"), "date");
    wpfExams?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "exam"));
    const wpfHomeworks = await fetchUpcomingDocs(wpfRef.collection("homeworks"), "dueDate");
    wpfHomeworks?.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => addDateKeyFromDoc(doc.data(), "homework"));
  }

  for (const dateKey of dateKeys) {
    const config = buildDailySummaryConfigFromDateKey(dateKey, newSettings);
    if (!config) continue;
    await scheduleDailySummaryTask(userId, config, tasksClient, queuePath, serviceUrl);
  }
};

// --- 2. Helper: Fetch Members ---

const fetchMembers = async (
  contextType: "group" | "class" | "wpf",
  contextId: string
): Promise<string[]> => {
  const db = admin.firestore();
  const members: Set<string> = new Set();

  try {
    if (contextType === "group") {
      // A. Active Members subcollection
      const membersSnap = await db.collection("groups").doc(contextId).collection("members").get();
      membersSnap.forEach((doc) => members.add(doc.id));

      // B. Legacy Members (users.groupIds)
      const legacySnap = await db.collection("users").where("groupIds", "array-contains", contextId).get();
      legacySnap.forEach((doc) => members.add(doc.id));
    } else if (contextType === "class") {
      // Classes have a 'members' subcollection
      const membersSnap = await db.collection("classes").doc(contextId).collection("members").get();
      membersSnap.forEach((doc) => members.add(doc.id));
    } else if (contextType === "wpf") {
      // WPF Groups also have 'members' subcollection or legacy structure?
      // Assuming subcollection members for consistency with Groups
      const membersSnap = await db.collection("wahlpflichtfachGroups").doc(contextId).collection("members").get();
      membersSnap.forEach((doc) => members.add(doc.id));

      // Check users.groupIds for WPF? Usually WPF IDs are also in groupIds array in legacy.
      const legacySnap = await db.collection("users").where("groupIds", "array-contains", contextId).get();
      legacySnap.forEach((doc) => members.add(doc.id));
    }
  } catch (e) {
    console.error(`Error fetching members for ${contextType} ${contextId}`, e);
  }

  return Array.from(members);
};

// --- 3. Triggers ---

export const rescheduleUserReminderSettings = onDocumentWritten(
  {
    document: "users/{userId}",
    region: "europe-west3",
  },
  async (event) => {
    const { userId } = event.params;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!after) return;
    if (!haveReminderSettingsChanged(before, after)) return;

    console.log(`[rescheduleUserReminderSettings] Settings changed for ${userId}. Rebuilding reminder tasks.`);
    await rescheduleUserReminders(userId, before, after);
  }
);

// Personal Exams
export const scheduleExamStart = onDocumentWritten(
  {
    document: "users/{userId}/schoolYears/{yearId}/exams/{examId}",
    region: "europe-west3",
  },
  async (event) => {
    const { userId, examId } = event.params;
    // 1. Live Activity (Start/Stale management)
    if (LIVE_ACTIVITY_ENABLED) {
      await manageExamTask(
        examId,
        event.data?.before.data(),
        event.data?.after.data(),
        [userId]
      );
    }
    // 2. Scheduled push reminder
    await manageScheduledReminderTasks(
      examId,
      event.data?.before.data(),
      event.data?.after.data(),
      [userId],
      "exam"
    );
  }
);

// Group Exams
export const scheduleGroupExam = onDocumentWritten(
  {
    document: "groups/{groupId}/exams/{examId}",
    region: "europe-west3",
  },
  async (event) => {
    const { groupId, examId } = event.params;
    const members = await fetchMembers("group", groupId);
    // Live Activity
    if (LIVE_ACTIVITY_ENABLED) {
      await manageExamTask(
        examId,
        event.data?.before.data(),
        event.data?.after.data(),
        members
      );
    }
    // Scheduled push reminder
    await manageScheduledReminderTasks(
      examId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "exam"
    );
  }
);

// Class Triggers (Class-Level Exams)
export const scheduleClassExam = onDocumentWritten(
  {
    document: "classes/{classId}/exams/{examId}",
    region: "europe-west3",
  },
  async (event) => {
    const { classId, examId } = event.params;
    const members = await fetchMembers("class", classId);
    // Live Activity
    if (LIVE_ACTIVITY_ENABLED) {
      await manageExamTask(
        examId,
        event.data?.before.data(),
        event.data?.after.data(),
        members
      );
    }
    // Scheduled push reminder
    await manageScheduledReminderTasks(
      examId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "exam"
    );
  }
);

// Class Course Exams (Course-Level Exams)
export const scheduleClassCourseExam = onDocumentWritten(
  {
    document: "classes/{classId}/courses/{courseId}/exams/{examId}",
    region: "europe-west3",
  },
  async (event) => {
    const { classId, examId } = event.params;
    const members = await fetchMembers("class", classId);
    // Live Activity
    if (LIVE_ACTIVITY_ENABLED) {
      await manageExamTask(
        examId,
        event.data?.before.data(),
        event.data?.after.data(),
        members
      );
    }
    // Scheduled push reminder
    await manageScheduledReminderTasks(
      examId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "exam"
    );
  }
);


// WPF Exams
export const scheduleWpfExam = onDocumentWritten(
  {
    document: "wahlpflichtfachGroups/{groupId}/exams/{examId}",
    region: "europe-west3",
  },
  async (event) => {
    const { groupId, examId } = event.params;
    const members = await fetchMembers("wpf", groupId);
    // Live Activity
    if (LIVE_ACTIVITY_ENABLED) {
      await manageExamTask(
        examId,
        event.data?.before.data(),
        event.data?.after.data(),
        members
      );
    }
    // Scheduled push reminder
    await manageScheduledReminderTasks(
      examId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "exam"
    );
  }
);

// --- Homework Triggers ---

// Personal Homework
export const scheduleHomeworkReminder = onDocumentWritten(
  {
    document: "users/{userId}/schoolYears/{yearId}/homeworks/{homeworkId}",
    region: "europe-west3",
  },
  async (event) => {
    const { userId, homeworkId } = event.params;
    await manageScheduledReminderTasks(
      homeworkId,
      event.data?.before.data(),
      event.data?.after.data(),
      [userId],
      "homework"
    );
  }
);

// Group Homework
export const scheduleGroupHomework = onDocumentWritten(
  {
    document: "groups/{groupId}/homeworks/{homeworkId}",
    region: "europe-west3",
  },
  async (event) => {
    const { groupId, homeworkId } = event.params;
    const members = await fetchMembers("group", groupId);
    await manageScheduledReminderTasks(
      homeworkId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "homework"
    );
  }
);

// Class Homework
export const scheduleClassHomework = onDocumentWritten(
  {
    document: "classes/{classId}/homeworks/{homeworkId}",
    region: "europe-west3",
  },
  async (event) => {
    const { classId, homeworkId } = event.params;
    const members = await fetchMembers("class", classId);
    await manageScheduledReminderTasks(
      homeworkId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "homework"
    );
  }
);

// Class Course Homework
export const scheduleClassCourseHomework = onDocumentWritten(
  {
    document: "classes/{classId}/courses/{courseId}/homeworks/{homeworkId}",
    region: "europe-west3",
  },
  async (event) => {
    const { classId, homeworkId } = event.params;
    const members = await fetchMembers("class", classId);
    await manageScheduledReminderTasks(
      homeworkId,
      event.data?.before.data(),
      event.data?.after.data(),
      members,
      "homework"
    );
  }
);

// --- Join Trigger ---

/**
 * When a user joins a class, schedule reminders for all upcoming items.
 */
export const scheduleMemberJoinNotifications = onDocumentCreated(
  {
    document: "classes/{classId}/members/{userId}",
    region: "europe-west3",
  },
  async (event) => {
    const { classId, userId } = event.params;
    const db = admin.firestore();

    // 0. Fetch user's subscribed courses for their active school year
    // We try to find the active school year document
    const userRef = db.collection("users").doc(userId);
    // const userDoc = await userRef.get();

    // We need to find the school year where this class is active
    const schoolYearsSnap = await userRef.collection("schoolYears").get();
    let subscribedCourseIds: string[] = [];

    for (const yearDoc of schoolYearsSnap.docs) {
      const yearData = yearDoc.data();
      const classIds = yearData.classIds || [];
      const activeClassId = yearData.activeClassId;

      if (activeClassId === classId || classIds.includes(classId)) {
        subscribedCourseIds = yearData.subscribedCourseIds || [];
        break;
      }
    }

    // 1. Fetch upcoming exams for the class
    const classExamsSnap = await db.collection("classes").doc(classId).collection("exams")
      .where("date", ">", admin.firestore.Timestamp.now())
      .get();

    for (const doc of classExamsSnap.docs) {
      await manageScheduledReminderTasks(doc.id, undefined, doc.data(), [userId], "exam");
    }

    // 2. Fetch upcoming exams and homework in courses
    const coursesSnap = await db.collection("classes").doc(classId).collection("courses").get();
    for (const courseDoc of coursesSnap.docs) {
      // Only process if user is in this course
      if (subscribedCourseIds.length > 0 && !subscribedCourseIds.includes(courseDoc.id)) {
        continue;
      }

      const courseExamsSnap = await courseDoc.ref.collection("exams")
        .where("date", ">", admin.firestore.Timestamp.now())
        .get();
      for (const doc of courseExamsSnap.docs) {
        await manageScheduledReminderTasks(doc.id, undefined, doc.data(), [userId], "exam");
      }

      const courseHwSnap = await courseDoc.ref.collection("homeworks")
        .where("dueDate", ">", admin.firestore.Timestamp.now())
        .get();
      for (const doc of courseHwSnap.docs) {
        await manageScheduledReminderTasks(doc.id, undefined, doc.data(), [userId], "homework");
      }
    }

    // 3. Class-level homework (if any)
    const classHwSnap = await db.collection("classes").doc(classId).collection("homeworks")
      .where("dueDate", ">", admin.firestore.Timestamp.now())
      .get();
    for (const doc of classHwSnap.docs) {
      await manageScheduledReminderTasks(doc.id, undefined, doc.data(), [userId], "homework");
    }
  }
);
