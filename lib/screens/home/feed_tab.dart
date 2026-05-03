import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/listings_provider.dart';
import '../../models/listing_model.dart';
import '../../widgets/listing_card.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _activeTab = 'all'; // all, lost, found

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          _activeTab = ['all', 'lost', 'found'][_tabCtrl.index];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        children: [
          // ── Sticky header ──────────────────────────────────────────────
          Container(
            color: scheme.surface,
            child: Column(
              children: [
                // Title bar
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
                            color: provider.selectedLocation != null ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Tabs
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

          // Offline banner
          Consumer<ListingsProvider>(
            builder: (_, provider, __) {
              if (!provider.isOffline) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.orange.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text('Offline — showing cached listings', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              );
            },
          ),

          // Listings
          Expanded(
            child: Consumer<ListingsProvider>(
              builder: (_, provider, __) {
                return TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _ListingsList(
                      listings: [...provider.lostListings, ...provider.foundListings]
                        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
                      isLoading: provider.isLoading,
                      emptyMessage: 'No items posted yet.',
                    ),
                    _ListingsList(
                      listings: provider.lostListings,
                      isLoading: provider.isLoading,
                      emptyMessage: 'No lost items reported.',
                    ),
                    _ListingsList(
                      listings: provider.foundListings,
                      isLoading: provider.isLoading,
                      emptyMessage: 'No found items reported.',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FilterSheet(),
    );
  }
}

class _ListingsList extends StatelessWidget {
  final List<ListingModel> listings;
  final bool isLoading;
  final String emptyMessage;

  const _ListingsList({required this.listings, required this.isLoading, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.surfaceVariant,
        highlightColor: Theme.of(context).colorScheme.surface,
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

    if (listings.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: listings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => ListingCard(listing: listings[i]),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter by location', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (provider.selectedLocation != null)
                TextButton(
                  onPressed: () { provider.clearFilters(); Navigator.pop(context); },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: campusLocations.map((loc) {
              final selected = provider.selectedLocation == loc;
              return FilterChip(
                label: Text(loc),
                selected: selected,
                onSelected: (_) {
                  provider.setLocationFilter(selected ? null : loc);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ListingSearchDelegate extends SearchDelegate {
  final ListingsProvider provider;
  _ListingSearchDelegate(this.provider);

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.close), onPressed: () { query = ''; provider.setSearchQuery(''); }),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
    IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { provider.setSearchQuery(''); close(context, null); });

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    provider.setSearchQuery(query);
    final all = [...provider.lostListings, ...provider.foundListings]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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