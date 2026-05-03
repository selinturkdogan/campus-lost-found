import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../models/listing_model.dart';
import '../detail/listing_detail_screen.dart';

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
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('listings')
                    .where('ownerId', isEqualTo: auth.user!.uid)
                    .snapshots(),
                builder: (context, listingSnap) {
                  if (!listingSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final listings = listingSnap.data!.docs
                      .map(ListingModel.fromFirestore)
                      .toList();

                  if (listings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.message_outlined, size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No messages yet.', style: textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          Text('Messages from your listings will appear here.', style: textTheme.bodySmall, textAlign: TextAlign.center),
                        ],
                      ),
                    );
                  }

                  return _ListingMessagesList(listings: listings);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingMessagesList extends StatelessWidget {
  final List<ListingModel> listings;
  const _ListingMessagesList({required this.listings});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: listings.length,
      itemBuilder: (context, i) {
        final listing = listings[i];
        return _ListingMessageCard(listing: listing);
      },
    );
  }
}

class _ListingMessageCard extends StatelessWidget {
  final ListingModel listing;
  const _ListingMessageCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLost = listing.type == 'lost';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .doc(listing.id)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, msgSnap) {
        if (!msgSnap.hasData) return const SizedBox.shrink();

        final messages = msgSnap.data!.docs;
        if (messages.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Listing header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                      child: Text(listing.title, style: textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text('${messages.length} msg${messages.length > 1 ? 's' : ''}',
                        style: textTheme.bodySmall?.copyWith(color: scheme.primary)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      )),
                      child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outline.withOpacity(0.3)),

              // Messages list
              ...messages.take(3).map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            (data['senderName'] as String? ?? 'U')[0].toUpperCase(),
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(data['senderName'] ?? 'Unknown', style: textTheme.titleSmall),
                                const Spacer(),
                                if (createdAt != null)
                                  Text(DateFormat('MMM d, h:mm a').format(createdAt), style: textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['text'] ?? '',
                              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(data['senderEmail'] ?? '', style: textTheme.bodySmall?.copyWith(color: scheme.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              if (messages.length > 3) ...[
                Divider(height: 1, color: scheme.outline.withOpacity(0.3)),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(listing: listing),
                    )),
                    child: Center(
                      child: Text(
                        'View all ${messages.length} messages',
                        style: textTheme.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}