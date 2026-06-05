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

/// Load the list of allowed email domains from Firestore.
/// Returns an array like ["final.edu.tr", "stu.final.edu.tr"].
/// If the doc is missing or the list is empty, returns [] — callers must
/// treat that as "no one is allowed".
async function loadAllowedDomains(db) {
  try {
    const snap = await db.collection("config").doc("allowed_domains").get();
    if (!snap.exists) return [];
    const list = snap.data().domains;
    if (!Array.isArray(list)) return [];
    return list
      .map((d) => String(d).toLowerCase().trim())
      .filter((d) => d.length > 0);
  } catch (e) {
    console.error("Failed to load allowed domains:", e);
    return [];
  }
}

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

    // 2) Domain check — load whitelist from Firestore (admin-managed)
    const db = getFirestore();
    const allowedDomains = await loadAllowedDomains(db);
    if (allowedDomains.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Registration is currently closed. Please contact the administrator."
      );
    }
    const matchesDomain = allowedDomains.some((d) => email.endsWith("@" + d));
    if (!matchesDomain) {
      throw new HttpsError(
        "permission-denied",
        `Only emails from these domains are allowed: ${allowedDomains
          .map((d) => "@" + d)
          .join(", ")}`
      );
    }

    const auth = getAuth();

    // 3) If this user has already completed first-time setup, DON'T send
    //    a new temp password. Instead return early with a flag so the
    //    client knows the Google session is already a valid sign-in and
    //    it can simply navigate to the home screen. This lets returning
    //    users skip the email/password step entirely when they tap
    //    "Continue with Google".
    const usersRef = db.collection("users").doc(request.auth.uid);
    const userSnap = await usersRef.get();
    if (userSnap.exists && userSnap.data().mustChangePassword === false) {
      return { success: true, alreadyRegistered: true, email };
    }

    // 4) Rate limit: 1 request per 60 seconds per email
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

    const db = getFirestore();
    const allowedDomains = await loadAllowedDomains(db);
    if (allowedDomains.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Password reset is currently disabled. Please contact the administrator."
      );
    }
    const matchesDomain = allowedDomains.some((d) => email.endsWith("@" + d));
    if (!matchesDomain) {
      throw new HttpsError(
        "permission-denied",
        `Only emails from these domains are allowed: ${allowedDomains
          .map((d) => "@" + d)
          .join(", ")}`
      );
    }

    const auth = getAuth();

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

// ── Comment created: bump count + notify owner & mentioned users ─────────────
exports.onCommentCreated = onDocumentCreated(
  "listings/{listingId}/comments/{commentId}",
  async (event) => {
    const comment = event.data.data();
    const { listingId } = event.params;
    const db = getFirestore();

    // 1) Increment commentCount on the listing doc.
    try {
      await db.collection("listings").doc(listingId).set(
        { commentCount: FieldValue.increment(1) },
        { merge: true }
      );
    } catch (e) {
      console.error("Failed to bump commentCount:", e);
    }

    const senderId = comment.authorId;
    const authorName = comment.authorName || "Someone";
    const previewText = (comment.text || "").slice(0, 120);

    // Fetch the listing once — we need both the owner and the title.
    let listingTitle = "a listing";
    let ownerId = null;
    try {
      const listingDoc = await db.collection("listings").doc(listingId).get();
      if (listingDoc.exists) {
        const ldata = listingDoc.data();
        listingTitle = ldata.title || listingTitle;
        ownerId = ldata.ownerId || null;
      }
    } catch (_) {}

    // Collect everyone who should be notified, deduped, excluding the
    // comment author themself.
    const recipients = new Set();

    // 2a) Listing owner gets a "new comment on your post" notification
    //     (but skip if they're the one commenting).
    if (ownerId && ownerId !== senderId) {
      recipients.add(ownerId);
    }

    // 2b) Anyone @-mentioned in the comment.
    const mentions = Array.isArray(comment.mentions) ? comment.mentions : [];
    for (const m of mentions) {
      if (m && m !== senderId) recipients.add(m);
    }

    // 3) Fan out notifications.
    for (const uid of recipients) {
      const isOwner = uid === ownerId;
      const isMention = mentions.includes(uid);
      // A mention takes priority in the title since it's more personal.
      const title = isMention
        ? `${authorName} mentioned you`
        : `${authorName} commented on your listing`;
      const body = isMention
        ? `On "${listingTitle}": ${previewText}`
        : `"${listingTitle}": ${previewText}`;
      const type = isMention ? "mention" : "comment";

      // In-app notification doc (powers the bell badge).
      try {
        await db
          .collection("users")
          .doc(uid)
          .collection("notifications")
          .add({
            title,
            body,
            type,
            listingId,
            senderId,
            read: false,
            createdAt: FieldValue.serverTimestamp(),
          });
      } catch (e) {
        console.error("Failed to write comment notification:", e);
      }

      // Push notification.
      try {
        const userDoc = await db.collection("users").doc(uid).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
        if (fcmToken) {
          await getMessaging().send({
            token: fcmToken,
            notification: { title, body: previewText },
            data: { listingId, type },
          });
        }
      } catch (e) {
        console.error("Failed to send comment push:", e);
      }
    }
  }
);

// ── Comment deleted: decrement count ─────────────────────────────────────────
exports.onCommentDeleted = require("firebase-functions/v2/firestore").onDocumentDeleted(
  "listings/{listingId}/comments/{commentId}",
  async (event) => {
    const { listingId } = event.params;
    const db = getFirestore();
    try {
      await db.collection("listings").doc(listingId).set(
        { commentCount: FieldValue.increment(-1) },
        { merge: true }
      );
    } catch (e) {
      console.error("Failed to decrement commentCount:", e);
    }
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
    // Messages are encrypted at rest, so the server can't read the actual
    // text. Show a generic, content-free preview instead. Images and
    // location messages are not encrypted, so use a typed label for them.
    const isEncrypted = message.encrypted === true;
    let previewBody;
    if (message.type === "image") {
      previewBody = "📷 Sent a photo";
    } else if (message.type === "location") {
      previewBody = "📍 Shared a location";
    } else if (isEncrypted) {
      previewBody = "Sent you a message";
    } else {
      previewBody = message.text || "Sent you a message";
    }
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

// ── Listing created: notify owners of potential opposite-type matches ────────
// When a new Lost listing is posted we scan the recent Found listings for
// the same category at the same campus location, and vice-versa. Each
// match writes an in-app notification ("match" type) to BOTH parties so
// the bell badge picks it up. Push notifications are intentionally
// skipped — the user wanted the match signal to live only inside the app.
exports.onListingCreated = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    const listing = event.data.data();
    const { listingId } = event.params;
    const db = getFirestore();

    if (!listing) return;
    const type = listing.type; // 'lost' or 'found'
    const category = listing.category;
    const location = listing.location;
    const ownerId = listing.ownerId;
    const title = listing.title || "(untitled)";
    if (!type || !category || !location || !ownerId) return;

    // Look at the opposite type, same category, same location, within the
    // last 30 days, still active (not resolved).
    const oppositeType = type === "lost" ? "found" : "lost";
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    let candidates;
    try {
      const snap = await db
        .collection("listings")
        .where("type", "==", oppositeType)
        .where("category", "==", category)
        .where("location", "==", location)
        .where("isResolved", "==", false)
        .get();
      // Filter by date and exclude listings posted by the same user — we
      // don't want self-matches. Done client-side because composite
      // indexes for createdAt + 3 equality fields get expensive.
      candidates = snap.docs.filter((d) => {
        const data = d.data();
        if (data.ownerId === ownerId) return false;
        const createdAt = data.createdAt;
        if (!createdAt || !createdAt.toDate) return true; // tolerate missing
        return createdAt.toDate() >= thirtyDaysAgo;
      });
    } catch (e) {
      console.error("Match query failed:", e);
      return;
    }

    if (candidates.length === 0) return;

    // For the new listing's owner — one combined notification telling them
    // there are N matches.
    const newOwnerBody =
      candidates.length === 1
        ? `Someone posted a ${oppositeType} item that matches "${title}".`
        : `${candidates.length} ${oppositeType} items match your "${title}".`;
    try {
      await db
        .collection("users")
        .doc(ownerId)
        .collection("notifications")
        .add({
          title:
            type === "lost"
              ? "Potential match found! 🎯"
              : "This could be someone's lost item 🎯",
          body: newOwnerBody,
          type: "match",
          // Deep-link to the BEST candidate (newest one).
          listingId: candidates[0].id,
          matchSourceId: listingId,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
    } catch (e) {
      console.error("Failed to write match notif for new owner:", e);
    }

    // For each candidate's owner — a notification saying their old listing
    // has a fresh counterpart.
    for (const cand of candidates) {
      const candData = cand.data();
      const candOwnerId = candData.ownerId;
      if (!candOwnerId || candOwnerId === ownerId) continue;
      const candTitle = candData.title || "your listing";
      try {
        await db
          .collection("users")
          .doc(candOwnerId)
          .collection("notifications")
          .add({
            title: "Potential match found! 🎯",
            body:
              type === "lost"
                ? `Someone lost a ${category} (${title}) — could it match "${candTitle}"?`
                : `Someone found a ${category} (${title}) — could it be "${candTitle}"?`,
            type: "match",
            // Deep-link the candidate's owner to the new listing.
            listingId: listingId,
            matchSourceId: cand.id,
            read: false,
            createdAt: FieldValue.serverTimestamp(),
          });
      } catch (e) {
        console.error("Failed to write match notif for candidate owner:", e);
      }
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
