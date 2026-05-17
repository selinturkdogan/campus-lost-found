const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");

initializeApp();

// ── Helpers ───────────────────────────────────────────────────────────────────
function generateTempPassword(length = 12) {
  // Avoid easily-confused chars (0/O, 1/l/I)
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  let out = "";
  for (let i = 0; i < length; i++) {
    out += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return out;
}

function buildTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: process.env.GMAIL_USER,
      pass: (process.env.GMAIL_APP_PASSWORD || "").replace(/\s+/g, ""),
    },
  });
}

function buildResetEmailHtml(resetLink) {
  return `
  <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;background:#f7f7fb;border-radius:12px;">
    <div style="background:linear-gradient(135deg,#7C3AED,#A78BFA);color:#fff;padding:24px;border-radius:10px;text-align:center;">
      <h1 style="margin:0;font-size:22px;">Campus Lost &amp; Found</h1>
      <p style="margin:6px 0 0;opacity:.9;">Password reset request</p>
    </div>
    <div style="background:#fff;padding:28px;border-radius:10px;margin-top:16px;">
      <p style="font-size:15px;color:#333;margin:0 0 12px;">Hello,</p>
      <p style="font-size:14px;color:#444;line-height:1.55;margin:0 0 20px;">
        We received a request to reset the password for your Campus Lost &amp; Found account.
        Click the button below to choose a new password.
      </p>
      <div style="text-align:center;margin:24px 0;">
        <a href="${resetLink}"
           style="background:linear-gradient(135deg,#7C3AED,#A78BFA);color:#fff;text-decoration:none;
                  padding:14px 28px;border-radius:10px;font-weight:600;display:inline-block;font-size:15px;">
          Reset my password
        </a>
      </div>
      <p style="font-size:12px;color:#888;margin:20px 0 6px;">
        If the button does not work, copy and paste this link into your browser:
      </p>
      <p style="font-size:11px;color:#7C3AED;word-break:break-all;margin:0 0 18px;">${resetLink}</p>
      <p style="font-size:12px;color:#888;margin:20px 0 0;line-height:1.5;">
        If you did not request a password reset, you can safely ignore this email —
        your account remains protected. This link will expire in 1 hour.
      </p>
    </div>
    <p style="text-align:center;color:#aaa;font-size:11px;margin-top:16px;">
      © Campus Lost &amp; Found
    </p>
  </div>`;
}

function buildEmailHtml(tempPassword) {
  return `
  <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;background:#f7f7fb;border-radius:12px;">
    <div style="background:linear-gradient(135deg,#7C3AED,#A78BFA);color:#fff;padding:24px;border-radius:10px;text-align:center;">
      <h1 style="margin:0;font-size:22px;">Campus Lost &amp; Found</h1>
      <p style="margin:6px 0 0;opacity:.9;">Your temporary password is ready</p>
    </div>
    <div style="background:#fff;padding:28px;border-radius:10px;margin-top:16px;">
      <p style="font-size:15px;color:#333;margin:0 0 12px;">Hello,</p>
      <p style="font-size:14px;color:#444;line-height:1.55;margin:0 0 18px;">
        Use the <b>temporary password</b> below to sign in to Campus Lost &amp; Found for the first time.
        After signing in, you will be asked to set a new password of your own.
      </p>
      <div style="background:#f3f0ff;border:1px dashed #7C3AED;color:#4c1d95;padding:14px 18px;border-radius:10px;text-align:center;font-size:20px;font-weight:700;letter-spacing:2px;">
        ${tempPassword}
      </div>
      <p style="font-size:12px;color:#888;margin:20px 0 0;line-height:1.5;">
        If you did not request this password, you can safely ignore this email —
        your account remains protected. The temporary password can only be used once,
        and you will choose your own password after signing in.
      </p>
    </div>
    <p style="text-align:center;color:#aaa;font-size:11px;margin-top:16px;">
      © Campus Lost &amp; Found
    </p>
  </div>`;
}

// ── Send temporary password (called after Google OAuth verification) ─────────
exports.sendTempPassword = onCall(
  { region: "us-central1" },
  async (request) => {
    // 1) Must be authenticated (via Google sign-in on the client)
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Google verification is required."
      );
    }

    const email = (request.auth.token.email || "").toLowerCase().trim();
    const emailVerified = request.auth.token.email_verified === true;

    if (!email) {
      throw new HttpsError("invalid-argument", "No email found on your account.");
    }
    if (!emailVerified) {
      throw new HttpsError(
        "failed-precondition",
        "Your email address is not verified by Google."
      );
    }

    // 2) Domain check
    const allowedDomain = (
      process.env.ALLOWED_EMAIL_DOMAIN || "final.edu.tr"
    ).toLowerCase();
    if (!email.endsWith("@" + allowedDomain)) {
      throw new HttpsError(
        "permission-denied",
        `Only @${allowedDomain} email addresses are allowed.`
      );
    }

    const db = getFirestore();
    const auth = getAuth();

    // 3) Rate limit: 1 request per 60 seconds per email
    const usersRef = db.collection("users").doc(request.auth.uid);
    const userSnap = await usersRef.get();
    if (userSnap.exists) {
      const last = userSnap.data().lastTempPasswordSentAt;
      if (last && last.toDate) {
        const diffMs = Date.now() - last.toDate().getTime();
        if (diffMs < 60_000) {
          const wait = Math.ceil((60_000 - diffMs) / 1000);
          throw new HttpsError(
            "resource-exhausted",
            `Please try again in ${wait} seconds.`
          );
        }
      }
    }

    // 4) Generate temp password and update Auth user
    const tempPassword = generateTempPassword(12);
    try {
      await auth.updateUser(request.auth.uid, {
        password: tempPassword,
        emailVerified: true,
      });
    } catch (e) {
      console.error("Failed to update auth user:", e);
      throw new HttpsError("internal", "Failed to generate password.");
    }

    // 5) Mark mustChangePassword + store metadata in Firestore
    const displayName =
      request.auth.token.name ||
      (email.split("@")[0] || "Student").replace(/\./g, " ");
    await usersRef.set(
      {
        uid: request.auth.uid,
        email,
        displayName: userSnap.exists
          ? userSnap.data().displayName || displayName
          : displayName,
        mustChangePassword: true,
        lastTempPasswordSentAt: FieldValue.serverTimestamp(),
        createdAt: userSnap.exists
          ? userSnap.data().createdAt || FieldValue.serverTimestamp()
          : FieldValue.serverTimestamp(),
        isAdmin: userSnap.exists ? userSnap.data().isAdmin === true : false,
      },
      { merge: true }
    );

    // 6) Send the email via Gmail SMTP
    try {
      const transporter = buildTransporter();
      await transporter.sendMail({
        from: `"Campus Lost & Found" <${process.env.GMAIL_USER}>`,
        to: email,
        subject: "Your temporary password — Campus Lost & Found",
        html: buildEmailHtml(tempPassword),
        text:
          "Your Campus Lost & Found temporary password: " +
          tempPassword +
          "\n\nAfter signing in, you will be asked to set a new password.",
      });
    } catch (e) {
      console.error("Failed to send email:", e);
      throw new HttpsError(
        "internal",
        "Failed to send email. Please try again."
      );
    }

    return { success: true, email };
  }
);

// ── Send custom password reset email (branded, via Gmail SMTP) ───────────────
exports.sendPasswordResetMail = onCall(
  { region: "us-central1" },
  async (request) => {
    const email = ((request.data && request.data.email) || "")
      .toLowerCase()
      .trim();

    if (!email) {
      throw new HttpsError("invalid-argument", "Email is required.");
    }

    const allowedDomain = (
      process.env.ALLOWED_EMAIL_DOMAIN || "final.edu.tr"
    ).toLowerCase();
    if (!email.endsWith("@" + allowedDomain)) {
      throw new HttpsError(
        "permission-denied",
        `Only @${allowedDomain} email addresses are allowed.`
      );
    }

    const auth = getAuth();
    const db = getFirestore();

    // Verify user exists (silently succeed if not, to avoid email enumeration)
    let userRecord;
    try {
      userRecord = await auth.getUserByEmail(email);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        // Don't reveal that the user doesn't exist
        return { success: true };
      }
      throw new HttpsError("internal", "Failed to verify account.");
    }

    let resetLink;
    try {
      resetLink = await auth.generatePasswordResetLink(email);
    } catch (e) {
      console.error("Failed to generate reset link:", e);
      throw new HttpsError("internal", "Failed to generate reset link.");
    }

    // Clear mustChangePassword flag — the user is choosing their own password
    // via the reset link, so the first-time password requirement is satisfied.
    try {
      await db.collection("users").doc(userRecord.uid).set(
        { mustChangePassword: false },
        { merge: true }
      );
    } catch (e) {
      console.error("Failed to clear mustChangePassword flag:", e);
      // Non-fatal — continue and send the email anyway
    }

    try {
      const transporter = buildTransporter();
      await transporter.sendMail({
        from: `"Campus Lost & Found" <${process.env.GMAIL_USER}>`,
        to: email,
        subject: "Reset your password — Campus Lost & Found",
        html: buildResetEmailHtml(resetLink),
        text:
          "We received a request to reset your Campus Lost & Found password.\n\n" +
          "Open this link to choose a new password:\n" +
          resetLink +
          "\n\nIf you did not request a reset, you can ignore this email.",
      });
    } catch (e) {
      console.error("Failed to send reset email:", e);
      throw new HttpsError(
        "internal",
        "Failed to send email. Please try again."
      );
    }

    return { success: true };
  }
);

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

    const listingTitle = chatData.listingTitle || "a listing";
    const previewBody = message.text || "Sent a photo or location";
    const notificationTitle = `New message from ${message.senderName}`;

    // 1) Increment unread count for the receiver on the chat document.
    try {
      await db
        .collection("listings")
        .doc(listingId)
        .collection("chats")
        .doc(chatId)
        .set(
          {
            unreadCounts: { [receiverId]: FieldValue.increment(1) },
          },
          { merge: true }
        );
    } catch (e) {
      console.error("Failed to increment unread count:", e);
    }

    // 2) Write an in-app notification doc so the bell badge picks it up.
    try {
      await db
        .collection("users")
        .doc(receiverId)
        .collection("notifications")
        .add({
          title: notificationTitle,
          body: `${previewBody} — about "${listingTitle}"`,
          type: "chat",
          listingId,
          chatId,
          senderId,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
    } catch (e) {
      console.error("Failed to write notification doc:", e);
    }

    // 3) Send push notification (existing behaviour).
    const userDoc = await db.collection("users").doc(receiverId).get();
    if (!userDoc.exists) return;

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return;

    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: notificationTitle,
          body: previewBody,
        },
        data: {
          listingId: listingId,
          chatId: chatId,
          type: "chat",
        },
      });
    } catch (e) {
      console.error("Failed to send chat push:", e);
    }
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
