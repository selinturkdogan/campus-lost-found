import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listings_provider.dart';
import '../../utils/app_routes.dart';
import '../../widgets/listing_card.dart';

class MyPostsScreen extends StatefulWidget {
  final bool embedded;
  const MyPostsScreen({super.key, this.embedded = false});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();

    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Sign in to view your posts', style: textTheme.bodyMedium),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('ownerId', isEqualTo: auth.user!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          List<ListingModel> myListings = [];
          if (snapshot.hasData) {
            myListings = snapshot.data!.docs
                .map(ListingModel.fromFirestore)
                .toList();
            myListings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }

          final active = myListings.where((l) => !l.isResolved).toList();
          final resolved = myListings.where((l) => l.isResolved).toList();

          return Column(
            children: [
              Container(
                color: scheme.surface,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              if (!widget.embedded)
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () => Navigator.pop(context),
                                )
                              else
                                const SizedBox(width: 16),
                              Text('My Posts', style: textTheme.titleMedium),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.add_rounded),
                                onPressed: () => Navigator.pushNamed(context, AppRoutes.postForm),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: scheme.outline, width: 1)),
                        ),
                        child: TabBar(
                          controller: _tabCtrl,
                          tabs: [
                            Tab(text: 'Active (${active.length})'),
                            Tab(text: 'Resolved (${resolved.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : myListings.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined, size: 48, color: scheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text("You haven't posted anything yet", style: textTheme.bodyMedium),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => Navigator.pushNamed(context, AppRoutes.postForm),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Post Your First Item'),
                                ),
                              ],
                            ),
                          )
                        : TabBarView(
                            controller: _tabCtrl,
                            children: [
                              _ListingsList(listings: active, emptyMessage: 'No active listings.'),
                              _ListingsList(listings: resolved, emptyMessage: 'No resolved listings.'),
                            ],
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ListingsList extends StatelessWidget {
  final List<ListingModel> listings;
  final String emptyMessage;

  const _ListingsList({required this.listings, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: listings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final listing = listings[i];
        return Column(
          children: [
            // Expiry warning banner
            if (!listing.isResolved) _ExpiryBanner(listing: listing),
            ListingCard(
              listing: listing,
              showOwnerActions: true,
              onEdit: () => Navigator.pushNamed(context, AppRoutes.postForm, arguments: listing),
              onDelete: () async {
                final scheme = Theme.of(context).colorScheme;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: scheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('Delete listing?'),
                    content: Text(
                      'Are you sure you want to delete "${listing.title}"? '
                      'This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style:
                            TextButton.styleFrom(foregroundColor: scheme.error),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                final auth = context.read<AuthProvider>();
                await context
                    .read<ListingsProvider>()
                    .deleteListing(listing.id, auth.user!.uid);
              },
              onResolve: listing.isResolved
                  ? null
                  : () async {
                      await context.read<ListingsProvider>().markResolved(listing.id);
                    },
            ),
          ],
        );
      },
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  final ListingModel listing;
  const _ExpiryBanner({required this.listing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get expiresAt from Firestore directly via stream
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .doc(listing.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt == null) return const SizedBox.shrink();

        final daysLeft = expiresAt.difference(DateTime.now()).inDays;

        // Only show banner if 7 days or less remaining
        if (daysLeft > 7) return const SizedBox.shrink();

        final isExpired = daysLeft < 0;
        final color = isExpired ? Colors.red : Colors.orange;
        final message = isExpired
            ? 'This listing has expired!'
            : daysLeft == 0
                ? 'Expires today!'
                : '$daysLeft day${daysLeft == 1 ? '' : 's'} left before expiry';

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time_rounded, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final success = await context.read<ListingsProvider>().extendListing(listing.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Listing extended by 60 days!' : 'Failed to extend listing.'),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Extend', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }
}