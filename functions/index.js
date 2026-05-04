const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendChatNotification = onDocumentCreated(
  "listings/{listingId}/chats/{chatId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const { listingId, chatId } = event.params;

    const admin = require("firebase-admin");
    const db = admin.firestore();

    // Get chat metadata
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

    // Find the receiver (the other participant)
    const receiverId = participants.find((id) => id !== senderId);
    if (!receiverId) return;

    // Get receiver's FCM token
    const userDoc = await db.collection("users").doc(receiverId).get();
    if (!userDoc.exists) return;

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return;

    // Send notification
    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: `New message from ${message.senderName}`,
        body: message.text,
      },
      data: {
        listingId: listingId,
        chatId: chatId,
      },
    });
  }
);