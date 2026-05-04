import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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

  String _getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final chatId = _getChatId(auth.user!.uid, widget.otherUserId);

    setState(() => _sending = true);
    _messageCtrl.clear();

    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': auth.user!.uid,
        'senderName': auth.displayName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update chat metadata
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
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'listingTitle': widget.listingTitle,
      }, SetOptions(merge: true));

      await NotificationService.sendContactNotification(
        posterUid: widget.otherUserId,
        senderName: auth.displayName,
        listingTitle: widget.listingTitle,
      );

      // Scroll to bottom
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
    setState(() => _sending = false);
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

                      return _MessageBubble(
                        text: data['text'] ?? '',
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

            // Input
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
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
                    onTap: _sending ? null : _sendMessage,
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
  final String text;
  final bool isMe;
  final String senderName;
  final DateTime? time;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool isDark;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.senderName,
    required this.time,
    required this.scheme,
    required this.textTheme,
    required this.isDark,
  });

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
                  senderName[0].toUpperCase(),
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}