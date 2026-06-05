import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/message_crypto.dart';
import '../../services/notification_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/user_avatar.dart';
import '../profile/user_profile_view_screen.dart';

class ChatScreen extends StatefulWidget {
  final String listingId;
  final String listingTitle;
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.listingId,
    required this.listingTitle,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _didMarkRead = false;

  // Preview state
  File? _pendingImage;
  double? _pendingLat;
  double? _pendingLng;

  String _getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Reset this user's unread counter on the chat doc AND stamp the
  /// `lastReadAt.{myUid}` field used to drive read receipts on the
  /// sender's side.
  Future<void> _markChatAsRead(String chatId, String myUid) async {
    if (_didMarkRead) return;
    _didMarkRead = true;
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('chats')
          .doc(chatId)
          .update({
        'unreadCounts.$myUid': 0,
        'lastReadAt.$myUid': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Chat doc may not exist yet, or user isn't a participant. Either
      // way, nothing to mark.
    }
  }

  Future<void> _sendMessage({
    String? text,
    String? imageUrl,
    double? lat,
    double? lng,
  }) async {
    final auth = context.read<AuthProvider>();

    // Refuse to send if I have blocked them.
    if (auth.isBlocked(widget.otherUserId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have blocked this user. Unblock to send messages.')),
      );
      return;
    }

    final chatId = _getChatId(auth.user!.uid, widget.otherUserId);
    final msgText = text ?? _messageCtrl.text.trim();

    if (msgText.isEmpty && imageUrl == null && lat == null) return;

    setState(() => _sending = true);
    if (text == null) _messageCtrl.clear();

    try {
      final Map<String, dynamic> msgData = {
        'senderId': auth.user!.uid,
        'senderName': auth.displayName,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Encrypt text. Image bytes are already public in Storage, so the
      // URL stays in clear. Coordinates are also clear.
      if (imageUrl != null) {
        msgData['imageUrl'] = imageUrl;
        msgData['type'] = 'image';
        msgData['encrypted'] = false;
      } else if (lat != null && lng != null) {
        msgData['lat'] = lat;
        msgData['lng'] = lng;
        msgData['type'] = 'location';
        msgData['text'] = MessageCrypto.encryptText('Shared a location');
        msgData['encrypted'] = true;
      } else {
        msgData['text'] = MessageCrypto.encryptText(msgText);
        msgData['type'] = 'text';
        msgData['encrypted'] = true;
      }

      final lastMsg = imageUrl != null
          ? '📷 Photo'
          : lat != null
              ? '📍 Location'
              : MessageCrypto.encryptText(msgText);
      final lastMsgEncrypted = imageUrl == null && lat == null;

      final chatRef = FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('chats')
          .doc(chatId);

      await chatRef.set({
        'participants': [auth.user!.uid, widget.otherUserId],
        'participantNames': {
          auth.user!.uid: auth.displayName,
          widget.otherUserId: widget.otherUserName,
        },
        'lastMessage': lastMsg,
        'lastMessageEncrypted': lastMsgEncrypted,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'listingTitle': widget.listingTitle,
        'deletedFor': <String>[],
        // Bump my own lastReadAt — I obviously read my own message.
        'lastReadAt.${auth.user!.uid}': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add(msgData);

      // ignore: discarded_futures
      NotificationService.sendContactNotification(
        posterUid: widget.otherUserId,
        senderName: auth.displayName,
        listingTitle: widget.listingTitle,
      ).catchError((_) {});

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message.')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) return;
    final compressed = await ImageUtils.compress(File(picked.path));
    setState(() {
      _pendingImage = compressed;
      _pendingLat = null;
      _pendingLng = null;
    });
  }

  Future<void> _confirmSendImage() async {
    if (_pendingImage == null) return;
    setState(() => _sending = true);
    try {
      final auth = context.read<AuthProvider>();
      final ref = FirebaseStorage.instance
          .ref('chat_images/${auth.user!.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(_pendingImage!);
      final url = await ref.getDownloadURL();
      setState(() => _pendingImage = null);
      await _sendMessage(imageUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send image.')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  /// Picks up the device's *current* GPS coordinates with high accuracy.
  /// We force a fresh read (no last-known position) so the receiver gets
  /// a truly live location, and we show a brief loading indicator in the
  /// pending bar while the GPS warms up.
  Future<void> _getLocation() async {
    try {
      // Quick service check — if Location is OFF on the device, no point
      // asking for permission.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please turn on Location services.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enable location permission from settings.')),
          );
        }
        return;
      }

      // Show "Getting current location…" indicator
      setState(() {
        _pendingLat = null;
        _pendingLng = null;
        _pendingImage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting current location…'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        // Best accuracy → short TTL → fresh fix, not a cached one.
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: false,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _pendingLat = pos.latitude;
        _pendingLng = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get location. Try again.')),
        );
      }
    }
  }

  void _cancelPending() {
    setState(() {
      _pendingImage = null;
      _pendingLat = null;
      _pendingLng = null;
    });
  }

  void _showAttachmentOptions() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: scheme.primary, size: 20),
                ),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library_rounded, color: scheme.primary, size: 20),
                ),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.my_location_rounded, color: Colors.green, size: 20),
                ),
                title: const Text('Share current location'),
                subtitle: const Text('Sends your live GPS coordinates'),
                onTap: () {
                  Navigator.pop(context);
                  _getLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleBlock(BuildContext context, bool currentlyBlocked) async {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(currentlyBlocked ? 'Unblock user?' : 'Block this user?'),
        content: Text(
          currentlyBlocked
              ? 'They will be able to send you messages again.'
              : 'They will no longer appear in your messages list and you will '
                'not see new messages from them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: currentlyBlocked ? null : scheme.error,
            ),
            child: Text(currentlyBlocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = currentlyBlocked
        ? await auth.unblockUser(widget.otherUserId)
        : await auth.blockUser(widget.otherUserId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (currentlyBlocked ? 'User unblocked.' : 'User blocked.')
              : 'Action failed. Please try again.',
        ),
      ),
    );
  }

  void _openOtherProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileViewScreen(
          uid: widget.otherUserId,
          fallbackName: widget.otherUserName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final chatId = _getChatId(auth.user!.uid, widget.otherUserId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iBlockedThem = auth.isBlocked(widget.otherUserId);

    // Reset unread counter on first build for this user.
    _markChatAsRead(chatId, auth.user!.uid);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header — entire user-info area is tappable to open profile
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: scheme.surfaceVariant, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded, size: 18, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openOtherProfile,
                      child: Row(
                        children: [
                          UserAvatar(
                            uid: widget.otherUserId,
                            fallbackName: widget.otherUserName,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.otherUserName,
                                        style: textTheme.titleSmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                Text(
                                  widget.listingTitle,
                                  style: textTheme.bodySmall?.copyWith(color: scheme.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: scheme.onSurface),
                    onSelected: (val) {
                      if (val == 'profile') _openOtherProfile();
                      if (val == 'block') _toggleBlock(context, iBlockedThem);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('View profile'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(
                              iBlockedThem
                                  ? Icons.lock_open_rounded
                                  : Icons.block_rounded,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 10),
                            Text(iBlockedThem ? 'Unblock user' : 'Block user'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Block-state banner
            if (iBlockedThem)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: scheme.error.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, size: 16, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You've blocked this user. Unblock to chat again.",
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Messages
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('listings')
                    .doc(widget.listingId)
                    .collection('chats')
                    .doc(chatId)
                    .snapshots(),
                builder: (context, chatDocSnap) {
                  // Other participant's lastReadAt timestamp drives the
                  // ✓✓ read receipt. If we can't read it yet, treat all
                  // outgoing as merely sent (✓).
                  DateTime? otherLastReadAt;
                  if (chatDocSnap.hasData && chatDocSnap.data!.exists) {
                    final data = chatDocSnap.data!.data() as Map<String, dynamic>?;
                    final lastReadMap =
                        Map<String, dynamic>.from(data?['lastReadAt'] ?? {});
                    final ts = lastReadMap[widget.otherUserId] as Timestamp?;
                    otherLastReadAt = ts?.toDate();
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .doc(widget.listingId)
                        .collection('chats')
                        .doc(chatId)
                        .collection('messages')
                        .orderBy('createdAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data!.docs;

                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 48, color: scheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text('No messages yet.', style: textTheme.bodyMedium),
                              const SizedBox(height: 4),
                              Text('Say hello!', style: textTheme.bodySmall),
                            ],
                          ),
                        );
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollCtrl.hasClients) {
                          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                        }
                      });

                      // Build a flat list that may include date-separator
                      // chips between messages from different days.
                      final items = <Widget>[];
                      DateTime? lastDay;
                      for (var i = 0; i < messages.length; i++) {
                        final data = messages[i].data() as Map<String, dynamic>;
                        final isMe = data['senderId'] == auth.user!.uid;
                        final createdAt =
                            (data['createdAt'] as Timestamp?)?.toDate();
                        final type = data['type'] ?? 'text';

                        // Date separator
                        if (createdAt != null) {
                          final day = DateTime(
                              createdAt.year, createdAt.month, createdAt.day);
                          if (lastDay == null || day != lastDay) {
                            items.add(_DateSeparator(day: day, scheme: scheme));
                            lastDay = day;
                          }
                        }

                        final rawText = (data['text'] as String?) ?? '';
                        final isEncrypted = data['encrypted'] == true;
                        final decryptedText = isEncrypted
                            ? MessageCrypto.decryptOrPassthrough(rawText)
                            : rawText;

                        // Read state for outgoing messages only.
                        final readByOther = isMe &&
                            createdAt != null &&
                            otherLastReadAt != null &&
                            !otherLastReadAt.isBefore(createdAt);

                        items.add(_MessageBubble(
                          type: type,
                          text: decryptedText,
                          imageUrl: data['imageUrl'],
                          lat: (data['lat'] as num?)?.toDouble(),
                          lng: (data['lng'] as num?)?.toDouble(),
                          isMe: isMe,
                          senderId: data['senderId'] ?? '',
                          senderName: data['senderName'] ?? '',
                          time: createdAt,
                          scheme: scheme,
                          textTheme: textTheme,
                          isDark: isDark,
                          readByOther: readByOther,
                        ));
                      }

                      return ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        children: items,
                      );
                    },
                  );
                },
              ),
            ),

            // Pending preview — image
            if (_pendingImage != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: scheme.surfaceVariant,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_pendingImage!, width: 60, height: 60, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Send this photo?', style: textTheme.bodyMedium),
                    ),
                    IconButton(
                      onPressed: _cancelPending,
                      icon: const Icon(Icons.close_rounded, color: Colors.red),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _confirmSendImage,
                      icon: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded, color: Colors.green),
                    ),
                  ],
                ),
              ),

            // Pending preview — location with a tiny map
            if (_pendingLat != null && _pendingLng != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: scheme.surfaceVariant,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: AbsorbPointer(
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_pendingLat!, _pendingLng!),
                              zoom: 15,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('me'),
                                position:
                                    LatLng(_pendingLat!, _pendingLng!),
                              ),
                            },
                            liteModeEnabled: true,
                            zoomControlsEnabled: false,
                            myLocationButtonEnabled: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Share your current location?',
                              style: textTheme.bodyMedium),
                          Text(
                            '${_pendingLat!.toStringAsFixed(5)}, ${_pendingLng!.toStringAsFixed(5)}',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _cancelPending,
                      icon: const Icon(Icons.close_rounded, color: Colors.red),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () async {
                              final lat = _pendingLat!;
                              final lng = _pendingLng!;
                              setState(() { _pendingLat = null; _pendingLng = null; });
                              await _sendMessage(lat: lat, lng: lng);
                            },
                      icon: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded, color: Colors.green),
                    ),
                  ],
                ),
              ),

            // Input bar — disabled if I've blocked the other user
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: (_sending || iBlockedThem) ? null : _showAttachmentOptions,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: scheme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant, size: 22),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      maxLines: null,
                      enabled: !iBlockedThem,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: iBlockedThem
                            ? 'You blocked this user'
                            : 'Type a message...',
                        filled: true,
                        fillColor: scheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: scheme.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (_sending || iBlockedThem) ? null : () => _sendMessage(),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: (_sending || iBlockedThem) ? scheme.surfaceVariant : scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: iBlockedThem
                                  ? scheme.onSurfaceVariant
                                  : Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime day;
  final ColorScheme scheme;

  const _DateSeparator({required this.day, required this.scheme});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    if (now.difference(day).inDays < 7) {
      return DateFormat('EEEE').format(day); // e.g. Monday
    }
    return DateFormat('MMM d, yyyy').format(day); // e.g. Jan 5, 2026
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String type;
  final String text;
  final String? imageUrl;
  final double? lat;
  final double? lng;
  final bool isMe;
  final String senderId;
  final String senderName;
  final DateTime? time;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool isDark;
  final bool readByOther;

  const _MessageBubble({
    required this.type,
    required this.text,
    this.imageUrl,
    this.lat,
    this.lng,
    required this.isMe,
    required this.senderId,
    required this.senderName,
    required this.time,
    required this.scheme,
    required this.textTheme,
    required this.isDark,
    required this.readByOther,
  });

  Future<void> _openLocation() async {
    if (lat == null || lng == null) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showFullTimestamp(BuildContext context) {
    if (time == null) return;
    final full = DateFormat('EEEE, MMM d, yyyy • HH:mm').format(time!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(full),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openSenderProfile(BuildContext context) {
    if (senderId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileViewScreen(
          uid: senderId,
          fallbackName: senderName,
        ),
      ),
    );
  }

  Widget _readReceiptIcon() {
    if (!isMe) return const SizedBox.shrink();
    // Read by the other side → double check in a slightly brighter tint.
    if (readByOther) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF93C5FD)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(Icons.done_rounded, size: 14, color: Colors.white.withOpacity(0.7)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => _openSenderProfile(context),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showFullTimestamp(context),
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  color: isMe
                      ? scheme.primary
                      : (isDark ? const Color(0xFF1C1C1C) : scheme.surfaceVariant),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: type == 'image' && imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CachedNetworkImage(
                              imageUrl: imageUrl!,
                              width: 220,
                              fit: BoxFit.cover,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                              child: _MetaFooter(
                                time: time,
                                isMe: isMe,
                                scheme: scheme,
                                readReceipt: _readReceiptIcon(),
                              ),
                            ),
                          ],
                        ),
                      )
                    : type == 'location' && lat != null && lng != null
                        ? GestureDetector(
                            onTap: _openLocation,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Live map preview (lite mode)
                                  SizedBox(
                                    width: 220,
                                    height: 130,
                                    child: AbsorbPointer(
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: LatLng(lat!, lng!),
                                          zoom: 15,
                                        ),
                                        markers: {
                                          Marker(
                                            markerId: const MarkerId('shared'),
                                            position: LatLng(lat!, lng!),
                                          ),
                                        },
                                        liteModeEnabled: true,
                                        zoomControlsEnabled: false,
                                        myLocationButtonEnabled: false,
                                        compassEnabled: false,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.location_on_rounded,
                                              color: isMe ? Colors.white : Colors.green,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Shared Location',
                                              style: TextStyle(
                                                color: isMe ? Colors.white : scheme.onSurface,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Tap to open in Maps',
                                          style: TextStyle(
                                            color: isMe ? Colors.white.withOpacity(0.75) : scheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        _MetaFooter(
                                          time: time,
                                          isMe: isMe,
                                          scheme: scheme,
                                          readReceipt: _readReceiptIcon(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : scheme.onSurface,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _MetaFooter(
                                  time: time,
                                  isMe: isMe,
                                  scheme: scheme,
                                  readReceipt: _readReceiptIcon(),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Tiny row that combines the timestamp with the read-receipt icon. Used
/// at the bottom of every message bubble.
class _MetaFooter extends StatelessWidget {
  final DateTime? time;
  final bool isMe;
  final ColorScheme scheme;
  final Widget readReceipt;

  const _MetaFooter({
    required this.time,
    required this.isMe,
    required this.scheme,
    required this.readReceipt,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (time != null)
          Text(
            DateFormat('HH:mm').format(time!),
            style: TextStyle(
              fontSize: 10,
              color: isMe ? Colors.white.withOpacity(0.75) : scheme.onSurfaceVariant,
            ),
          ),
        readReceipt,
      ],
    );
  }
}
