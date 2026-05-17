import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/listings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/listing_model.dart';
import '../../widgets/listing_card.dart';
import '../notifications/notifications_screen.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
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

    return SafeArea(
      child: Column(
        children: [
          Container(
            color: scheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lost & Found', style: textTheme.titleLarge),
                          Consumer<ListingsProvider>(
                            builder: (_, provider, __) {
                              final count = provider.lostListings.length + provider.foundListings.length;
                              return Text('$count items', style: textTheme.bodySmall);
                            },
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => showSearch(
                          context: context,
                          delegate: _ListingSearchDelegate(context.read<ListingsProvider>()),
                        ),
                        icon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
                      ),
                      IconButton(
                        onPressed: () => _showFilterSheet(context),
                        icon: Consumer<ListingsProvider>(
                          builder: (_, provider, __) => Icon(
                            Icons.tune_rounded,
                            color: (provider.selectedLocation != null || provider.selectedCategory != null)
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // Bell icon with badge
                      if (auth.isAuthenticated)
                        _NotificationBell(uid: auth.user!.uid),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: scheme.outline, width: 1)),
                  ),
                  child: TabBar(
                    controller: _tabCtrl,
                    tabs: const [Tab(text: 'All'), Tab(text: 'Lost'), Tab(text: 'Found')],
                    indicatorWeight: 2,
                  ),
                ),
              ],
            ),
          ),

          // Active filter chips
          Consumer<ListingsProvider>(
            builder: (_, provider, __) {
              final hasFilters = provider.selectedLocation != null || provider.selectedCategory != null;
              if (!hasFilters) return const SizedBox.shrink();
              return Container(
                color: scheme.surface,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  children: [
                    if (provider.selectedLocation != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          label: Text(provider.selectedLocation!, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => provider.setLocationFilter(null),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (provider.selectedCategory != null)
                      Chip(
                        label: Text(provider.selectedCategory!, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => provider.setCategoryFilter(null),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: provider.clearFilters,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),

          // Offline banner
          Consumer<ListingsProvider>(
            builder: (_, provider, __) {
              if (!provider.isOffline) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.orange.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Offline — showing cached listings',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _PaginatedList(type: 'all', emptyMessage: 'No items posted yet.'),
                _PaginatedList(type: 'lost', emptyMessage: 'No lost items reported.'),
                _PaginatedList(type: 'found', emptyMessage: 'No found items reported.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FilterSheet(),
    );
  }
}

// ── Notification Bell ─────────────────────────────────────────────────────────

class _NotificationBell extends StatelessWidget {
  final String uid;
  const _NotificationBell({required this.uid});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  unreadCount > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: unreadCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
                  size: 24,
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Paginated List ─────────────────────────────────────────────────────────────

class _PaginatedList extends StatefulWidget {
  final String type;
  final String emptyMessage;

  const _PaginatedList({required this.type, required this.emptyMessage});

  @override
  State<_PaginatedList> createState() => _PaginatedListState();
}

class _PaginatedListState extends State<_PaginatedList> {
  Future<void> _loadMore(ListingsProvider provider) {
    switch (widget.type) {
      case 'lost':
        return provider.loadMoreLost();
      case 'found':
        return provider.loadMoreFound();
      default:
        return provider.loadMoreAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<ListingsProvider>(
      builder: (_, provider, __) {
        if (provider.isLoading) {
          return Shimmer.fromColors(
            baseColor: scheme.surfaceVariant,
            highlightColor: scheme.surface,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, __) => Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          );
        }

        List<ListingModel> listings;
        bool isLoadingMore;
        bool hasMore;

        if (widget.type == 'lost') {
          listings = provider.lostListings;
          isLoadingMore = provider.isLoadingMoreLost;
          hasMore = provider.hasMoreLost;
        } else if (widget.type == 'found') {
          listings = provider.foundListings;
          isLoadingMore = provider.isLoadingMoreFound;
          hasMore = provider.hasMoreFound;
        } else {
          listings = provider.allListings;
          isLoadingMore = provider.isLoadingMoreAll;
          hasMore = provider.hasMoreAll;
        }

        if (listings.isEmpty) {
          return RefreshIndicator(
            onRefresh: provider.refreshAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Text(
                      widget.emptyMessage,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.refreshAll,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: listings.length + 1, // +1 for footer (load more / end marker)
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i == listings.length) {
                return _LoadMoreFooter(
                  isLoading: isLoadingMore,
                  hasMore: hasMore,
                  totalShown: listings.length,
                  onLoadMore: () => _loadMore(provider),
                );
              }
              return ListingCard(listing: listings[i]);
            },
          ),
        );
      },
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  final bool isLoading;
  final bool hasMore;
  final int totalShown;
  final VoidCallback onLoadMore;

  const _LoadMoreFooter({
    required this.isLoading,
    required this.hasMore,
    required this.totalShown,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        children: [
          if (hasMore)
            GestureDetector(
              onTap: isLoading ? null : onLoadMore,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline),
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.expand_more_rounded,
                                size: 18, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Load more',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Showing all $totalShown items',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Filter Sheet ──────────────────────────────────────────────────────────────

class _FilterSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Filters', style: textTheme.titleMedium),
                const Spacer(),
                if (provider.selectedLocation != null || provider.selectedCategory != null)
                  TextButton(
                    onPressed: () { provider.clearFilters(); Navigator.pop(context); },
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Location', style: textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: campusLocations.map((loc) {
                final selected = provider.selectedLocation == loc;
                return FilterChip(
                  label: Text(loc, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => provider.setLocationFilter(selected ? null : loc),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Category', style: textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: itemCategories.map((cat) {
                final selected = provider.selectedCategory == cat;
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => provider.setCategoryFilter(selected ? null : cat),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search Delegate ───────────────────────────────────────────────────────────

class _ListingSearchDelegate extends SearchDelegate {
  final ListingsProvider provider;
  _ListingSearchDelegate(this.provider);

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.close), onPressed: () { query = ''; provider.setSearchQuery(''); }),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () { provider.setSearchQuery(''); close(context, null); },
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    provider.setSearchQuery(query);
    final all = provider.allListings;
    if (all.isEmpty) {
      return Center(child: Text('No results for "$query"', style: Theme.of(context).textTheme.bodySmall));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: all.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => ListingCard(listing: all[i]),
    );
  }
}