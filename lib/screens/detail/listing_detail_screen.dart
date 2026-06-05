import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
// google_maps_flutter is kept only for its LatLng type (used by the
// `_campusCoords` lookup) — Marker is hidden so it doesn't collide with
// flutter_map's Marker, which is what we now use for the preview.
import 'package:google_maps_flutter/google_maps_flutter.dart' hide Marker;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listings_provider.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';
import '../../widgets/comments_section.dart';
import '../../widgets/delete_reason_sheet.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';

// Approximate coordinates for Final International University — Çatalköy /
// Kyrenia campus (Northern Cyprus). Each entry is offset slightly around
// the main campus point so that different listings render distinct pins.
const Map<String, LatLng> _campusCoords = {
  'Main Library':         LatLng(35.3470, 33.3142),
  'Student Union':        LatLng(35.3472, 33.3145),
  'Engineering Building': LatLng(35.3475, 33.3148),
  'Science Hall':         LatLng(35.3468, 33.3140),
  'Arts Center':          LatLng(35.3466, 33.3144),
  'Dining Hall':          LatLng(35.3471, 33.3146),
  'Gym & Recreation':     LatLng(35.3464, 33.3150),
  'Residence Halls':      LatLng(35.3478, 33.3152),
  'Parking Lots':         LatLng(35.3473, 33.3138),
  'Campus Grounds':       LatLng(35.3470, 33.3145),
  'Other':                LatLng(35.3470, 33.3145),
};

class ListingDetailScreen extends StatefulWidget {
  final ListingModel listing;
  // If true, the screen scrolls straight down to the comments section
  // after the first frame is rendered. Used when the user taps the
  // comment icon on a listing card.
  final bool scrollToComments;

  const ListingDetailScreen({
    super.key,
    required this.listing,
    this.scrollToComments = false,
  });

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _scrollCtrl = ScrollController();
  final _commentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToComments) {
      // Wait for the first frame so the comments widget actually has a
      // position to scroll to.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToComments();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToComments() {
    final ctx = _commentsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.0, // bring the comments to the top of the viewport
    );
  }
  Future<void> _share() async {
    // Share ONLY the URL as the body — that way the system share sheet
    // recognises it as a link and the "Copy link" option copies just the
    // URL instead of a multi-line text blob. The title goes into the
    // subject (used by email clients) and the description tags along
    // inside the subject so receivers still get context in apps that
    // surface it (WhatsApp preview, mail).
    final isLost = widget.listing.type == 'lost';
    final intro = isLost ? 'Lost item' : 'Found item';
    final url =
        'https://campus-lost-found-68e7d.web.app/listing/${widget.listing.id}';
    await Share.share(
      url,
      subject: '$intro: ${widget.listing.title}',
    );
  }

  Future<void> _confirmDelete() async {
    final result = await showDeleteReasonSheet(
      context,
      listingTitle: widget.listing.title,
    );
    if (result == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    final provider = context.read<ListingsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (result.action == DeleteReasonAction.resolve) {
      final ok = await provider.markResolved(widget.listing.id,
          reason: result.reason);
      if (ok && mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Marked as resolved — great news! 🎉'),
        ));
        Navigator.pop(context);
      }
    } else {
      final ok = await provider.deleteListing(
        widget.listing.id,
        auth.user!.uid,
        reason: result.reason,
        reasonText: result.text,
      );
      if (ok && mounted) Navigator.pop(context);
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
                _ActionIconBtn(
                  icon: Icons.share_outlined,
                  isDark: isDark,
                  onTap: _share,
                ),
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
                ],
                const SizedBox(width: 4),
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
                    const SizedBox(height: 12),

                    // Context banner — explains what kind of post this is.
                    // Hidden for the listing's own owner because they know
                    // what their own post is about; the third-person
                    // "Someone lost this item" reads awkwardly to them.
                    if (!isOwner) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: (isLost
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFF4CAF50))
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isLost
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFF4CAF50))
                                .withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isLost
                                  ? Icons.search_rounded
                                  : Icons.emoji_objects_outlined,
                              size: 18,
                              color: isLost
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isLost
                                    ? 'Someone lost this item — help them find it.'
                                    : 'Someone found this item — is it yours?',
                                style: textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isLost
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Text(widget.listing.title, style: textTheme.displayMedium),
                    const SizedBox(height: 16),

                    _InfoRow(icon: Icons.location_on_outlined, label: widget.listing.location),
                    const SizedBox(height: 16),

                    _PosterCard(
                      ownerId: widget.listing.ownerId,
                      fallbackName: widget.listing.ownerName,
                      fallbackEmail: widget.listing.ownerEmail,
                    ),
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

                    // Non-owner: chat button or pickup-info card
                    if (!isOwner && auth.isAuthenticated) ...[
                      if (widget.listing.chatEnabled)
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
                            icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18),
                            label: Text(isLost
                                ? 'I might have it — message owner'
                                : 'This is mine — message finder'),
                          ),
                        )
                      else
                        _ChatDisabledCard(
                          pickupNote: widget.listing.pickupNote ?? '',
                        ),
                    ] else if (!auth.isAuthenticated) ...[
                      _LoginPrompt(),
                    ],

                    const SizedBox(height: 32),
                    Divider(color: scheme.outline),
                    const SizedBox(height: 24),

                    CommentsSection(
                      key: _commentsKey,
                      listingId: widget.listing.id,
                      listingOwnerId: widget.listing.ownerId,
                    ),

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

  Future<void> _openInGoogleMaps() async {
    final lat = widget.coords.latitude;
    final lng = widget.coords.longitude;

    // Use Google's official "Maps URL" format — most reliable across
    // Android and iOS. The OS routes it to the installed Maps app, and
    // falls back to the browser if Maps is not installed.
    // https://developers.google.com/maps/documentation/urls/get-started
    // Try a few URL formats in order. The generic `geo:` URI is
    // honoured by every Android map app (Google Maps, OsmAnd, Maps.me,
    // HERE WeGo etc.). The OpenStreetMap web URL is a safe browser
    // fallback that works everywhere — important for Northern Cyprus
    // where Google's coverage is patchy.
    final candidates = <Uri>[
      Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(widget.locationName)})'),
      Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat%2C$lng'),
      Uri.parse(
          'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng'),
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
              // Render the preview with flutter_map + OpenStreetMap
              // tiles. OSM covers Northern Cyprus properly (Google's
              // tile data is patchy here) and needs no API key. The
              // widget is wrapped in IgnorePointer so the parent
              // GestureDetector still gets the tap → Open in Maps.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: ll.LatLng(
                              widget.coords.latitude, widget.coords.longitude),
                          initialZoom: 16,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.example.campus_lf_new',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: ll.LatLng(widget.coords.latitude,
                                    widget.coords.longitude),
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 36,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

class _PosterCard extends StatelessWidget {
  final String ownerId;
  final String fallbackName;
  final String fallbackEmail;

  const _PosterCard({
    required this.ownerId,
    required this.fallbackName,
    required this.fallbackEmail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(ownerId).get(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>?
            : null;
        final photoUrl = data?['photoUrl'] as String?;
        final name =
            (data?['displayName'] as String?) ?? fallbackName;
        final email = (data?['email'] as String?) ?? fallbackEmail;
        final phone = data?['phone'] as String?;
        final city = data?['city'] as String?;
        final department = data?['department'] as String?;
        final bio = data?['bio'] as String?;
        final phonePublic = data?['phonePublic'] == true;
        final cityPublic = data?['cityPublic'] == true;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    photoUrl: photoUrl,
                    fallbackName: name,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant),
                        ),
                        if (department != null && department.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            department,
                            style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (bio != null && bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(bio,
                    style: textTheme.bodySmall?.copyWith(height: 1.4)),
              ],
              if ((phonePublic && phone != null && phone.isNotEmpty) ||
                  (cityPublic && city != null && city.isNotEmpty)) ...[
                const SizedBox(height: 10),
                Divider(color: scheme.outline, height: 12),
                const SizedBox(height: 6),
                if (phonePublic && phone != null && phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(phone, style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                if (cityPublic && city != null && city.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.location_city_outlined,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(city, style: textTheme.bodyMedium),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChatDisabledCard extends StatelessWidget {
  final String pickupNote;

  const _ChatDisabledCard({required this.pickupNote});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Chat is disabled for this item',
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          if (pickupNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pickupNote,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
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