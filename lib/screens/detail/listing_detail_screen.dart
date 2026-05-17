import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listings_provider.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';
import '../chat/chat_screen.dart';

const Map<String, LatLng> _campusCoords = {
  'Main Library':         LatLng(35.3302, 33.3586),
  'Student Union':        LatLng(35.3304, 33.3591),
  'Engineering Building': LatLng(35.3297, 33.3593),
  'Science Hall':         LatLng(35.3295, 33.3582),
  'Arts Center':          LatLng(35.3307, 33.3580),
  'Dining Hall':          LatLng(35.3300, 33.3589),
  'Gym & Recreation':     LatLng(35.3293, 33.3595),
  'Residence Halls':      LatLng(35.3309, 33.3594),
  'Parking Lots':         LatLng(35.3291, 33.3584),
  'Campus Grounds':       LatLng(35.3301, 33.3588),
  'Other':                LatLng(35.3301, 33.3588),
};

class ListingDetailScreen extends StatefulWidget {
  final ListingModel listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete listing?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final auth = context.read<AuthProvider>();
      final success = await context.read<ListingsProvider>().deleteListing(widget.listing.id, auth.user!.uid);
      if (success && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.user?.uid == widget.listing.ownerId;
    final isLost = widget.listing.type == 'lost';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coords = _campusCoords[widget.listing.location] ?? const LatLng(35.3301, 33.3588);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : null,
          color: isDark ? null : scheme.surface,
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: widget.listing.photoUrl != null ? 280 : 0,
              pinned: true,
              backgroundColor: isDark ? const Color(0xFF000000) : scheme.surface,
              surfaceTintColor: Colors.transparent,
              leading: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back_rounded, color: scheme.onSurface, size: 20),
                ),
              ),
              actions: [
                if (isOwner) ...[
                  _ActionIconBtn(
                    icon: Icons.edit_outlined,
                    isDark: isDark,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.postForm, arguments: widget.listing),
                  ),
                  _ActionIconBtn(
                    icon: Icons.delete_outline_rounded,
                    isDark: isDark,
                    onTap: _confirmDelete,
                  ),
                  const SizedBox(width: 4),
                ],
              ],
              flexibleSpace: widget.listing.photoUrl != null
                  ? FlexibleSpaceBar(
                      background: CachedNetworkImage(imageUrl: widget.listing.photoUrl!, fit: BoxFit.cover),
                    )
                  : null,
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badges
                    Row(
                      children: [
                        _Badge(
                          label: isLost ? 'Lost' : 'Found',
                          color: isLost ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50),
                        ),
                        if (widget.listing.isResolved) ...[
                          const SizedBox(width: 8),
                          const _Badge(label: 'Resolved', color: Colors.grey),
                        ],
                        const Spacer(),
                        Text(
                          DateFormat('MMM d, yyyy · h:mm a').format(widget.listing.createdAt),
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(widget.listing.title, style: textTheme.displayMedium),
                    const SizedBox(height: 16),

                    _InfoRow(icon: Icons.location_on_outlined, label: widget.listing.location),
                    const SizedBox(height: 8),
                    _InfoRow(icon: Icons.person_outline_rounded, label: widget.listing.ownerName),
                    const SizedBox(height: 8),
                    _InfoRow(icon: Icons.email_outlined, label: widget.listing.ownerEmail),
                    const SizedBox(height: 20),

                    _LocationMapCard(locationName: widget.listing.location, coords: coords, isDark: isDark),
                    const SizedBox(height: 24),
                    Divider(color: scheme.outline),
                    const SizedBox(height: 24),

                    Text('Description', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      widget.listing.description,
                      style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),

                    // Owner: resolve button only
                    if (isOwner && !widget.listing.isResolved) ...[
                      _ResolveButton(listingId: widget.listing.id),
                    ],

                    // Non-owner: chat button
                    if (!isOwner && auth.isAuthenticated) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                listingId: widget.listing.id,
                                listingTitle: widget.listing.title,
                                otherUserId: widget.listing.ownerId,
                                otherUserName: widget.listing.ownerName,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text('Chat with poster'),
                        ),
                      ),
                    ] else if (!auth.isAuthenticated) ...[
                      _LoginPrompt(),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationMapCard extends StatefulWidget {
  final String locationName;
  final LatLng coords;
  final bool isDark;
  const _LocationMapCard({required this.locationName, required this.coords, required this.isDark});

  @override
  State<_LocationMapCard> createState() => _LocationMapCardState();
}

class _LocationMapCardState extends State<_LocationMapCard> {
  GoogleMapController? _mapController;

  @override
  void dispose() { _mapController?.dispose(); super.dispose(); }

  Future<void> _openInGoogleMaps() async {
    final lat = widget.coords.latitude;
    final lng = widget.coords.longitude;
    final label = Uri.encodeComponent(widget.locationName);

    // Try the native Google Maps URI scheme first (Android/iOS app),
    // then fall back to the universal web URL which the OS will route
    // to the maps app if installed, or to the browser otherwise.
    final candidates = <Uri>[
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
      Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      } catch (_) {
        // Try next candidate.
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marker = Marker(
      markerId: const MarkerId('listing_location'),
      position: widget.coords,
      infoWindow: InfoWindow(title: widget.locationName),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Location on Map',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: _openInGoogleMaps,
              icon: Icon(Icons.open_in_new_rounded,
                  size: 16, color: scheme.primary),
              label: Text('Open in Maps',
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _openInGoogleMaps,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(16),
              ),
              // Wrap the map in IgnorePointer so taps go to the parent
              // GestureDetector instead of being swallowed by the map.
              // This lets the whole card act as an "open in Maps" button.
              child: Stack(
                children: [
                  IgnorePointer(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                          target: widget.coords, zoom: 16),
                      markers: {marker},
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      liteModeEnabled: true,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        if (widget.isDark) {
                          controller.setMapStyle(_darkMapStyle);
                        }
                      },
                    ),
                  ),
                  // Hint overlay so users know the map is tappable
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.touch_app_outlined,
                              size: 12, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'Tap to open',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const String _darkMapStyle = '[{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]}]';

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 16, color: scheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
    ]);
  }
}

class _ResolveButton extends StatelessWidget {
  final String listingId;
  const _ResolveButton({required this.listingId});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () async {
        final success = await context.read<ListingsProvider>().markResolved(listingId);
        if (success && context.mounted) Navigator.pop(context);
      },
      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
      label: const Text('Mark as resolved'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.green,
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );
}

class _LoginPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, color: scheme.onSurfaceVariant, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('Sign in to contact the poster.', style: Theme.of(context).textTheme.bodyMedium)),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
          child: const Text('Sign in'),
        ),
      ]),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _ActionIconBtn({required this.icon, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
    ),
  );
}