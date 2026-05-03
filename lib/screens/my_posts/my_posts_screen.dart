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
        return ListingCard(
          listing: listing,
          showOwnerActions: true,
          onEdit: () => Navigator.pushNamed(context, AppRoutes.postForm, arguments: listing),
          onDelete: () async {
            final auth = context.read<AuthProvider>();
            await context.read<ListingsProvider>().deleteListing(listing.id, auth.user!.uid);
          },
          onResolve: listing.isResolved
              ? null
              : () async {
                  await context.read<ListingsProvider>().markResolved(listing.id);
                },
        );
      },
    );
  }
}