"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendCustomNotification = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
/**
 * Sends a custom push notification to a specific user using stored FCM tokens.
 */
exports.sendCustomNotification = (0, https_1.onCall)(async (request) => {
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
    const tokens = userData === null || userData === void 0 ? void 0 : userData.fcmTokens;
    if (!tokens || tokens.length === 0) {
        console.log(`No tokens found for user ${userId}.`);
        return { success: false, message: "No device tokens found" };
    }
    // 3. Construct Payload
    const notificationData = {};
    if (action)
        notificationData.action = action;
    if (sheetType)
        notificationData.sheetType = sheetType;
    if (payloadId)
        notificationData.id = payloadId;
    const message = {
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
        console.log(`Sent ${response.successCount} messages, ` +
            `failed ${response.failureCount}`);
        // Optional: Cleanup invalid tokens
        if (response.failureCount > 0) {
            const invalidTokens = [];
            response.responses.forEach((resp, idx) => {
                var _a, _b;
                if (!resp.success && (((_a = resp.error) === null || _a === void 0 ? void 0 : _a.code) === "messaging/invalid-registration-token" ||
                    ((_b = resp.error) === null || _b === void 0 ? void 0 : _b.code) === "messaging/registration-token-not-registered")) {
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
    }
    catch (error) {
        console.error("Error sending notification:", error);
        throw new Error("Failed to send notification");
    }
});
//# sourceMappingURL=index.js.map