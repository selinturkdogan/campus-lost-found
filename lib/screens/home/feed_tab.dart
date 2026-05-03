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
  String _activeTab = 'all';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _activeTab = ['all', 'lost', 'found'][_tabCtrl.index]);
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

          // Active filter chips row
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
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text('Offline — showing cached listings',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              );
            },
          ),

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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    if (listings.isEmpty) {
      return Center(child: Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall));
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

            // Location
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

            // Category
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