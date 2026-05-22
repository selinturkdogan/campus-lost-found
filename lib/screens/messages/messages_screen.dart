import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/message_crypto.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                  Text('Messages', style: textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: _AllChatsView(uid: auth.user!.uid),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllChatsView extends StatelessWidget {
  final String uid;
  const _AllChatsView({required this.uid});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Single collectionGroup query — fetches only chats this user is a
    // participant in. The previous implementation walked every listing
    // and tried to read its chats subcollection, which (a) was N+1, and
    // (b) returned PERMISSION_DENIED under the tightened rules because
    // the queries weren't filtered by participants.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('chats')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, chatSnap) {
        // Surface errors so we don't get stuck on a spinner. The most
        // common cause is a missing collectionGroup index — Firestore
        // returns a FAILED_PRECONDITION with a link to create it.
        if (chatSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 40, color: scheme.error),
                  const SizedBox(height: 12),
                  Text('Could not load messages',
                      style: textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    '${chatSnap.error}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        if (chatSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!chatSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // Filter out chats this user has soft-deleted. Firestore can't
        // combine arrayContains (participants) with array-not-contains
        // in a single query, so we filter on the client.
        final chats = chatSnap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final deletedFor =
              List<String>.from(data['deletedFor'] ?? const []);
          return !deletedFor.contains(uid);
        }).toList()
          ..sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['lastMessageAt']
                as Timestamp?;
            final bTs = (b.data() as Map<String, dynamic>)['lastMessageAt']
                as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 48, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('No conversations yet.',
                    style: textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Message a poster from a listing to start chatting.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: chats.length,
          itemBuilder: (context, i) {
            final chat = chats[i];
            final data = chat.data() as Map<String, dynamic>;
            // listingId is the parent of the parent: .../listings/{id}/chats/{chatId}
            final listingId = chat.reference.parent.parent!.id;
            final listingTitle =
                (data['listingTitle'] as String?) ?? 'Listing';
            return _SingleChatTile(
              uid: uid,
              chat: chat,
              listingId: listingId,
              listingTitle: listingTitle,
            );
          },
        );
      },
    );
  }
}

/// One row in the conversation list.
///
/// Renders the other participant's avatar + name, the (decrypted) last
/// message preview, the unread badge and the timestamp. Tapping opens
/// the chat screen; swiping right-to-left deletes the conversation
/// (after confirmation) by removing the chat doc and all its messages.
class _SingleChatTile extends StatelessWidget {
  final String uid;
  final QueryDocumentSnapshot chat;
  final String listingId;
  final String listingTitle;

  const _SingleChatTile({
    required this.uid,
    required this.chat,
    required this.listingId,
    required this.listingTitle,
  });

  Future<bool> _confirmDelete(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: scheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete conversation?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Per-user soft delete — the conversation is hidden only for the
  /// current user. The other participant keeps seeing it, and the
  /// messages stay in Firestore. If the other person sends a new
  /// message, the chat reappears in this user's list (chat_screen
  /// clears `deletedFor` on every send).
  Future<void> _delete(BuildContext context) async {
    try {
      await chat.reference.update({
        'deletedFor': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete conversation.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = chat.data() as Map<String, dynamic>;

    final participantNames =
        Map<String, dynamic>.from(data['participantNames'] ?? {});
    final participants = (data['participants'] as List?) ?? const [];
    final otherUserId = participants
        .firstWhere((id) => id != uid, orElse: () => '')
        ?.toString() ??
        '';
    final otherUserName =
        participantNames[otherUserId]?.toString() ?? 'Unknown';

    final rawLastMsg = data['lastMessage']?.toString() ?? '';
    final lastMessage = data['lastMessageEncrypted'] == true
        ? MessageCrypto.decryptOrPassthrough(rawLastMsg)
        : rawLastMsg;
    final lastMessageAt = (data['lastMessageAt'] as Timestamp?)?.toDate();

    final unreadCounts =
        Map<String, dynamic>.from(data['unreadCounts'] ?? {});
    final unread = (unreadCounts[uid] as num?)?.toInt() ?? 0;

    return Dismissible(
      key: Key(chat.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _delete(context),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              listingId: listingId,
              listingTitle: listingTitle,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              UserAvatar(
                uid: otherUserId,
                fallbackName: otherUserName,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherUserName,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            listingTitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastMessage.isEmpty ? 'No messages yet' : lastMessage,
                      style: textTheme.bodySmall?.copyWith(
                        color: unread > 0
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastMessageAt != null)
                    Text(
                      DateFormat('h:mm a').format(lastMessageAt),
                      style: textTheme.bodySmall?.copyWith(
                        color: unread > 0 ? scheme.primary : null,
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      constraints: const BoxConstraints(
                          minWidth: 20, minHeight: 20),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
