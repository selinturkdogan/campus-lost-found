import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listings_provider.dart';
import '../../models/listing_model.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';
import '../../widgets/listing_card.dart';

class FeedScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const FeedScreen({super.key, required this.toggleTheme});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Start Firestore streams
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ListingsProvider>().startListening();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : null,
          color: isDark ? null : scheme.surface,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── AppBar ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _showSearch
                            ? _SearchBar(
                                controller: _searchCtrl,
                                onChanged: (q) => context
                                    .read<ListingsProvider>()
                                    .setSearchQuery(q),
                                onClose: () {
                                  setState(() => _showSearch = false);
                                  _searchCtrl.clear();
                                  context
                                      .read<ListingsProvider>()
                                      .setSearchQuery('');
                                },
                              )
                            : _AppBarTitle(
                                key: const ValueKey('title'),
                                toggleTheme: widget.toggleTheme,
                                isDark: isDark,
                              ),
                      ),
                    ),
                    if (!_showSearch) ...[
                      const SizedBox(width: 8),
                      _IconBtn(
                        icon: Icons.search_rounded,
                        onTap: () => setState(() => _showSearch = true),
                      ),
                      const SizedBox(width: 8),
                      _FilterButton(),
                      const SizedBox(width: 8),
                      if (auth.isAuthenticated)
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, AppRoutes.myPosts),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: scheme.primary.withOpacity(0.15),
                            child: Text(
                              (auth.user?.displayName ?? 'U')[0].toUpperCase(),
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      else
                        _IconBtn(
                          icon: Icons.login_rounded,
                          onTap: () => Navigator.pushNamed(context, AppRoutes.login),
                        ),
                    ],
                  ],
                ),
              ),

              // ── Offline banner ─────────────────────────────────────────────
              Consumer<ListingsProvider>(
                builder: (_, provider, __) {
                  if (!provider.isOffline) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'You\'re offline — showing cached listings',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // ── Tab bar ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: TabBar(
                  controller: _tabCtrl,
                  tabs: const [
                    Tab(text: 'Lost'),
                    Tab(text: 'Found'),
                  ],
                ),
              ),

              // ── Tab views ──────────────────────────────────────────────────
              Expanded(
                child: Consumer<ListingsProvider>(
                  builder: (_, provider, __) {
                    return TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _ListingsList(
                          listings: provider.lostListings,
                          isLoading: provider.isLoading,
                          emptyMessage: 'No lost items reported yet.',
                        ),
                        _ListingsList(
                          listings: provider.foundListings,
                          isLoading: provider.isLoading,
                          emptyMessage: 'No found items reported yet.',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),

      // ── FAB — only for authenticated users ─────────────────────────────────
      floatingActionButton: Consumer<AuthProvider>(
        builder: (_, auth, __) {
          if (!auth.isAuthenticated) return const SizedBox.shrink();
          return Container(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.postForm),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          );
        },
      ),
    );
  }
}

// ── Listings list with shimmer loading ─────────────────────────────────────────
class _ListingsList extends StatelessWidget {
  final List<ListingModel> listings;
  final bool isLoading;
  final String emptyMessage;

  const _ListingsList({
    required this.listings,
    required this.isLoading,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _ShimmerList();

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: listings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => ListingCard(listing: listings[i]),
    );
  }
}

// ── Shimmer loading skeleton ──────────────────────────────────────────────────
class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E1E35) : const Color(0xFFE8E8F0),
      highlightColor: isDark ? const Color(0xFF2A2A45) : const Color(0xFFF5F5FF),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search listings...',
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: scheme.onSurfaceVariant),
        suffixIcon: IconButton(
          icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
          onPressed: onClose,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        isDense: true,
      ),
    );
  }
}

// ── Filter button ─────────────────────────────────────────────────────────────
class _FilterButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<ListingsProvider>();
    final hasFilter = provider.selectedLocation != null;

    return GestureDetector(
      onTap: () => _showFilterSheet(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: hasFilter ? scheme.primary.withOpacity(0.15) : scheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasFilter ? scheme.primary : scheme.outline,
          ),
        ),
        child: Icon(
          Icons.tune_rounded,
          size: 18,
          color: hasFilter ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter by location', style: textTheme.titleMedium),
              const Spacer(),
              if (provider.selectedLocation != null)
                TextButton(
                  onPressed: () {
                    provider.clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 16),
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

// ── AppBar title ──────────────────────────────────────────────────────────────
class _AppBarTitle extends StatelessWidget {
  final VoidCallback toggleTheme;
  final bool isDark;

  const _AppBarTitle({
    super.key,
    required this.toggleTheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.search_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          'Campus L&F',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Spacer(),
        GestureDetector(
          onTap: toggleTheme,
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outline),
        ),
        child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
