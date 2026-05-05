import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../detail/listing_detail_screen.dart';
import '../../models/listing_model.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
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
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: scheme.surfaceVariant, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded, size: 18, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Notifications', style: textTheme.titleMedium),
                  const Spacer(),
                  // Mark all as read
                  TextButton(
                    onPressed: () => _markAllAsRead(auth.user!.uid),
                    child: Text('Mark all read', style: TextStyle(fontSize: 12, color: scheme.primary)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(auth.user!.uid)
                    .collection('notifications')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final notifications = snapshot.data!.docs;

                  if (notifications.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No notifications yet.', style: textTheme.bodyMedium),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final doc = notifications[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final isRead = data['read'] == true;
                      final type = data['type'] ?? 'general';
                      final title = data['title'] ?? '';
                      final body = data['body'] ?? '';
                      final listingId = data['listingId'];
                      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _markAsRead(auth.user!.uid, doc.id),
                        background: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.done_all_rounded, color: Colors.white, size: 22),
                              SizedBox(height: 4),
                              Text('Read', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () async {
                            // Mark as read
                            await _markAsRead(auth.user!.uid, doc.id);
                            // Navigate to listing if listingId exists
                            if (listingId != null && context.mounted) {
                              _navigateToListing(context, listingId);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isRead ? scheme.surface : scheme.primary.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isRead ? scheme.outline.withOpacity(0.5) : scheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Icon
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: _getIconColor(type).withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getIcon(type),
                                    color: _getIconColor(type),
                                    size: 20,
                                  ),
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
                                              title,
                                              style: textTheme.titleSmall?.copyWith(
                                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              width: 8, height: 8,
                                              decoration: BoxDecoration(
                                                color: scheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (createdAt != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          DateFormat('MMM d, h:mm a').format(createdAt),
                                          style: textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (listingId != null)
                                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: scheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsRead(String uid, String notifId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notifId)
        .update({'read': true});
  }

  Future<void> _markAllAsRead(String uid) async {
    final batch = FirebaseFirestore.instance.batch();
    final unread = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _navigateToListing(BuildContext context, String listingId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('listings')
          .doc(listingId)
          .get();
      if (!doc.exists || !context.mounted) return;
      final listing = ListingModel.fromFirestore(doc);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)),
      );
    } catch (_) {}
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'chat': return Icons.chat_bubble_outline_rounded;
      case 'expiry': return Icons.access_time_rounded;
      default: return Icons.notifications_outlined;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'chat': return const Color(0xFF4F46E5);
      case 'expiry': return Colors.orange;
      default: return Colors.grey;
    }
  }
}