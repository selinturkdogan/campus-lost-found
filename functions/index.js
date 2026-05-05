const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

// ── Send push notification when a new chat message is created ────────────────
exports.sendChatNotification = onDocumentCreated(
  "listings/{listingId}/chats/{chatId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const { listingId, chatId } = event.params;
    const db = getFirestore();

    const chatDoc = await db
      .collection("listings")
      .doc(listingId)
      .collection("chats")
      .doc(chatId)
      .get();

    if (!chatDoc.exists) return;

    const chatData = chatDoc.data();
    const participants = chatData.participants || [];
    const senderId = message.senderId;
    const receiverId = participants.find((id) => id !== senderId);
    if (!receiverId) return;

    const userDoc = await db.collection("users").doc(receiverId).get();
    if (!userDoc.exists) return;

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return;

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: `New message from ${message.senderName}`,
        body: message.text || "Sent a photo or location",
      },
      data: {
        listingId: listingId,
        chatId: chatId,
        type: "chat",
      },
    });
  }
);

// ── Check expiring listings every day at 08:00 UTC ───────────────────────────
exports.checkExpiringListings = onSchedule("every day 08:00", async () => {
  const db = getFirestore();
  const now = new Date();
  const in7Days = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

  const snapshot = await db
    .collection("listings")
    .where("isResolved", "==", false)
    .where("expiresAt", "<=", in7Days)
    .where("expiresAt", ">", now)
    .get();

  for (const doc of snapshot.docs) {
    const listing = doc.data();
    const ownerId = listing.ownerId;
    const listingTitle = listing.title;
    const expiresAt = listing.expiresAt.toDate();
    const daysLeft = Math.ceil((expiresAt - now) / (1000 * 60 * 60 * 24));

    const userDoc = await db.collection("users").doc(ownerId).get();
    if (!userDoc.exists) continue;

    const fcmToken = userDoc.data().fcmToken;

    // Save in-app notification
    await db.collection("users").doc(ownerId).collection("notifications").add({
      title: "Listing expiring soon",
      body: `Your listing "${listingTitle}" expires in ${daysLeft} day${daysLeft === 1 ? "" : "s"}. Extend it to keep it active.`,
      listingId: doc.id,
      type: "expiry",
      read: false,
      createdAt: new Date(),
    });

    // Send push notification
    if (fcmToken) {
      try {
        await getMessaging().send({
          token: fcmToken,
          notification: {
            title: "Listing expiring soon ⏰",
            body: `"${listingTitle}" expires in ${daysLeft} day${daysLeft === 1 ? "" : "s"}. Tap to extend.`,
          },
          data: {
            listingId: doc.id,
            type: "expiry",
          },
        });
      } catch (e) {
        console.error("Failed to send expiry notification:", e);
      }
    }
  }
});