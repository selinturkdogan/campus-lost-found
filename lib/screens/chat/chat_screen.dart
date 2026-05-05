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
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';

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

  // Preview state
  File? _pendingImage;
  double? _pendingLat;
  double? _pendingLng;

  String _getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> _sendMessage({
    String? text,
    String? imageUrl,
    double? lat,
    double? lng,
  }) async {
    final auth = context.read<AuthProvider>();
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

      if (imageUrl != null) {
        msgData['imageUrl'] = imageUrl;
        msgData['type'] = 'image';
      } else if (lat != null && lng != null) {
        msgData['lat'] = lat;
        msgData['lng'] = lng;
        msgData['type'] = 'location';
        msgData['text'] = 'Shared a location';
      } else {
        msgData['text'] = msgText;
        msgData['type'] = 'text';
      }

      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(msgData);

      final lastMsg = imageUrl != null
          ? '📷 Photo'
          : lat != null
              ? '📍 Location'
              : msgText;

      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('chats')
          .doc(chatId)
          .set({
        'participants': [auth.user!.uid, widget.otherUserId],
        'participantNames': {
          auth.user!.uid: auth.displayName,
          widget.otherUserId: widget.otherUserName,
        },
        'lastMessage': lastMsg,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'listingTitle': widget.listingTitle,
      }, SetOptions(merge: true));

      await NotificationService.sendContactNotification(
        posterUid: widget.otherUserId,
        senderName: auth.displayName,
        listingTitle: widget.listingTitle,
      );

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
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;
    setState(() {
      _pendingImage = File(picked.path);
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

  Future<void> _getLocation() async {
    try {
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

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _pendingLat = pos.latitude;
        _pendingLng = pos.longitude;
        _pendingImage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get location.')),
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
                  child: const Icon(Icons.location_on_rounded, color: Colors.green, size: 20),
                ),
                title: const Text('Share location'),
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.otherUserName[0].toUpperCase(),
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.otherUserName, style: textTheme.titleSmall),
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

            // Messages
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
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
                          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: scheme.onSurfaceVariant),
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

                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final data = messages[i].data() as Map<String, dynamic>;
                      final isMe = data['senderId'] == auth.user!.uid;
                      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                      final type = data['type'] ?? 'text';

                      return _MessageBubble(
                        type: type,
                        text: data['text'] ?? '',
                        imageUrl: data['imageUrl'],
                        lat: data['lat']?.toDouble(),
                        lng: data['lng']?.toDouble(),
                        isMe: isMe,
                        senderName: data['senderName'] ?? '',
                        time: createdAt,
                        scheme: scheme,
                        textTheme: textTheme,
                        isDark: isDark,
                      );
                    },
                  );
                },
              ),
            ),

            // Pending preview
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

            if (_pendingLat != null && _pendingLng != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: scheme.surfaceVariant,
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Share your location?', style: textTheme.bodyMedium),
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

            // Input bar
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _sending ? null : _showAttachmentOptions,
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
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
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
                    onTap: _sending ? null : () => _sendMessage(text: _messageCtrl.text.trim()),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: _sending ? scheme.surfaceVariant : scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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

class _MessageBubble extends StatelessWidget {
  final String type;
  final String text;
  final String? imageUrl;
  final double? lat;
  final double? lng;
  final bool isMe;
  final String senderName;
  final DateTime? time;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool isDark;

  const _MessageBubble({
    required this.type,
    required this.text,
    this.imageUrl,
    this.lat,
    this.lng,
    required this.isMe,
    required this.senderName,
    required this.time,
    required this.scheme,
    required this.textTheme,
    required this.isDark,
  });

  Future<void> _openLocation() async {
    if (lat == null || lng == null) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
            Container(
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
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
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
                          if (time != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                              child: Text(
                                DateFormat('h:mm a').format(time!),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe ? Colors.white.withOpacity(0.7) : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : type == 'location' && lat != null && lng != null
                      ? GestureDetector(
                          onTap: _openLocation,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  color: isMe ? Colors.white : Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Shared Location',
                                      style: TextStyle(
                                        color: isMe ? Colors.white : scheme.onSurface,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Tap to open in Maps',
                                      style: TextStyle(
                                        color: isMe ? Colors.white.withOpacity(0.7) : scheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (time != null)
                                      Text(
                                        DateFormat('h:mm a').format(time!),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isMe ? Colors.white.withOpacity(0.7) : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
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
                              if (time != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('h:mm a').format(time!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe ? Colors.white.withOpacity(0.7) : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
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