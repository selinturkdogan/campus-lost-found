import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('listings').snapshots(),
      builder: (context, listingSnap) {
        if (!listingSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final listings = listingSnap.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: listings.length,
          itemBuilder: (context, i) {
            final listingData = listings[i].data() as Map<String, dynamic>;
            final listingId = listings[i].id;
            final listingTitle = listingData['title'] ?? '';
            return _ListingChatsCard(
              uid: uid,
              listingId: listingId,
              listingTitle: listingTitle,
              listingData: listingData,
            );
          },
        );
      },
    );
  }
}

class _ListingChatsCard extends StatelessWidget {
  final String uid;
  final String listingId;
  final String listingTitle;
  final Map<String, dynamic> listingData;

  const _ListingChatsCard({
    required this.uid,
    required this.listingId,
    required this.listingTitle,
    required this.listingData,
  });

  Future<void> _deleteChat(BuildContext context, String chatId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete conversation?'),
        content: const Text('This will delete the conversation for you. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete all messages in the chat
      final messages = await FirebaseFirestore.instance
          .collection('listings')
          .doc(listingId)
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }
      // Delete the chat document itself
      batch.delete(
        FirebaseFirestore.instance
            .collection('listings')
            .doc(listingId)
            .collection('chats')
            .doc(chatId),
      );
      await batch.commit();
    } catch (e) {
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
    final isLost = listingData['type'] == 'lost';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .doc(listingId)
          .collection('chats')
          .snapshots(),
      builder: (context, chatSnap) {
        if (!chatSnap.hasData) return const SizedBox.shrink();

        final chats = chatSnap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final participants = List<String>.from(data['participants'] ?? []);
          return participants.contains(uid);
        }).toList();

        if (chats.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Listing header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isLost ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50)).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isLost ? 'Lost' : 'Found',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isLost ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      listingTitle,
                      style: textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Chat items with swipe to delete
            ...chats.map((chat) {
              final data = chat.data() as Map<String, dynamic>;
              final participantNames = Map<String, dynamic>.from(data['participantNames'] ?? {});
              final otherUserId = (data['participants'] as List?)
                  ?.firstWhere((id) => id != uid, orElse: () => '')
                  ?.toString() ?? '';
              final otherUserName = participantNames[otherUserId]?.toString() ?? 'Unknown';
              final lastMessage = data['lastMessage']?.toString() ?? '';
              final lastMessageAt = (data['lastMessageAt'] as Timestamp?)?.toDate();
              final chatId = chat.id;

              return Dismissible(
                key: Key(chatId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: scheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Delete conversation?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  return confirmed ?? false;
                },
                onDismissed: (_) async {
                  try {
                    final messages = await FirebaseFirestore.instance
                        .collection('listings')
                        .doc(listingId)
                        .collection('chats')
                        .doc(chatId)
                        .collection('messages')
                        .get();
                    final batch = FirebaseFirestore.instance.batch();
                    for (final doc in messages.docs) {
                      batch.delete(doc.reference);
                    }
                    batch.delete(
                      FirebaseFirestore.instance
                          .collection('listings')
                          .doc(listingId)
                          .collection('chats')
                          .doc(chatId),
                    );
                    await batch.commit();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to delete conversation.')),
                      );
                    }
                  }
                },
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
                      Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                      SizedBox(height: 4),
                      Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(otherUserName, style: textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                lastMessage.isEmpty ? 'No messages yet' : lastMessage,
                                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (lastMessageAt != null)
                              Text(
                                DateFormat('h:mm a').format(lastMessageAt),
                                style: textTheme.bodySmall,
                              ),
                            const SizedBox(height: 4),
                            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}