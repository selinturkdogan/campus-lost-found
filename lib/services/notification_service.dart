import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized in main.dart
  // Just handle the message silently — local notification shown automatically
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'campus_lf_channel';
  static const _channelName = 'Campus Lost & Found';
  static const _channelDesc = 'Notifications for lost and found items';

  /// Call once in main.dart after Firebase.initializeApp()
  Future<void> init() async {
    // 1. Request permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Setup local notifications (for foreground)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // 3. Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 4. Save FCM token to Firestore
    await _saveToken();

    // 5. Listen for token refresh
    _messaging.onTokenRefresh.listen(_updateToken);

    // 6. Foreground message handler
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 7. Background handler (registered at top level)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> _saveToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _messaging.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Future<void> _updateToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Call this when user sends a contact message to the poster
  /// [posterUid] — the listing owner's Firebase UID
  /// [senderName] — display name of the person sending the message
  /// [listingTitle] — title of the listing
  static Future<void> sendContactNotification({
    required String posterUid,
    required String senderName,
    required String listingTitle,
  }) async {
    // Get poster's FCM token from Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(posterUid)
        .get();

    final token = doc.data()?['fcmToken'] as String?;
    if (token == null) return;

    // Save notification to Firestore — Cloud Function or local trigger reads this
    await FirebaseFirestore.instance.collection('notifications').add({
      'token': token,
      'title': 'Someone is interested in your listing!',
      'body': '$senderName sent a message about "$listingTitle"',
      'posterUid': posterUid,
      'createdAt': FieldValue.serverTimestamp(),
      'sent': false,
    });
  }

  /// Call when a new listing is created — notifies all users
  static Future<void> sendNewListingNotification({
    required String type, // 'lost' or 'found'
    required String itemTitle,
    required String location,
  }) async {
    final typeLabel = type == 'lost' ? 'Lost Item Reported' : 'Found Item Reported';
    await FirebaseFirestore.instance.collection('notifications').add({
      'topic': 'all_users',
      'title': typeLabel,
      'body': '"$itemTitle" at $location',
      'createdAt': FieldValue.serverTimestamp(),
      'sent': false,
    });
  }
}