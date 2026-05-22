import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/listing_model.dart';
import '../screens/detail/listing_detail_screen.dart';
import '../utils/app_routes.dart';
import 'user_avatar.dart';

/// Instagram-style listing card.
///
/// Layout:
///   ┌─────────────────────────────┐
///   │ avatar  Name           ⋮    │  ← header
///   │         time · location     │
///   ├─────────────────────────────┤
///   │                             │
///   │   Photo (4:5, full-width)   │  ← image with Lost/Found chip overlay
///   │                             │
///   ├─────────────────────────────┤
///   │ 💬 3      🔗 Share          │  ← action row
///   ├─────────────────────────────┤
///   │ Title                       │  ← caption
///   │ description preview…        │
///   │ View details →              │
///   └─────────────────────────────┘
///
/// Tapping anywhere on the card (except the share button) opens the
/// detail screen. The card always renders the image area — when there's
/// no photo, a tasteful gradient placeholder is shown so the cards keep
/// a consistent rhythm in the feed.
class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final bool showOwnerActions;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onResolve;

  const ListingCard({
    super.key,
    required this.listing,
    this.showOwnerActions = false,
    this.onEdit,
    this.onDelete,
    this.onResolve,
  });

  void _share() {
    final isLost = listing.type == 'lost';
    final intro = isLost
        ? 'Lost item on campus — help find it!'
        : 'Found item on campus — looking for the owner!';
    final url =
        'https://campus-lost-found-68e7d.web.app/listing/${listing.id}';
    final msg = '$intro\n\n'
        '"${listing.title}"\n'
        '${listing.description}\n'
        '📍 ${listing.location}\n\n'
        '$url';
    Share.share(msg, subject: listing.title);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLost = listing.type == 'lost';
    final accent =
        isLost ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50);

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.listingDetail,
        arguments: listing,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: avatar + name + time/location ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
              child: Row(
                children: [
                  UserAvatar(
                    uid: listing.ownerId,
                    fallbackName: listing.ownerName,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.ownerName,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 11,
                                color: scheme.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                listing.location,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '  ·  ${_formatDate(listing.createdAt)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Lost/Found chip in the header
                  Container(
                    margin: const EdgeInsets.only(left: 6, right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isLost ? 'Lost' : 'Found',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Image (16:9 aspect ratio, full-width) ─────────────────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _ListingImage(
                photoUrl: listing.photoUrl,
                accent: accent,
                isLost: isLost,
                scheme: scheme,
              ),
            ),

            // ── Action row: comment count + share ─────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  _ActionIconBtn(
                    icon: Icons.mode_comment_outlined,
                    label: listing.commentCount > 0
                        ? '${listing.commentCount}'
                        : null,
                    color: scheme.onSurface,
                    // Open detail AND scroll straight to the comments
                    // section so the user can read/post without scrolling
                    // through the whole listing first.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(
                          listing: listing,
                          scrollToComments: true,
                        ),
                      ),
                    ),
                  ),
                  _ActionIconBtn(
                    icon: Icons.share_outlined,
                    color: scheme.onSurface,
                    onTap: _share,
                  ),
                  const Spacer(),
                  if (listing.isResolved)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_circle_rounded,
                              size: 12, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Resolved',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Caption: title + description + "view details" ─────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: '${listing.title}  ',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: listing.description,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'View details',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 12, color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),

            // ── Owner actions (only in "My Posts" screen) ─────────────
            if (showOwnerActions) ...[
              Divider(color: scheme.outline, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    if (!listing.isResolved && onResolve != null)
                      _OwnerActionBtn(
                        label: 'Mark as Resolved',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green,
                        onTap: onResolve!,
                      ),
                    const Spacer(),
                    if (onEdit != null)
                      _OwnerActionBtn(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          color: scheme.primary,
                          onTap: onEdit!),
                    const SizedBox(width: 16),
                    if (onDelete != null)
                      _OwnerActionBtn(
                          label: 'Delete',
                          icon: Icons.delete_outline_rounded,
                          color: scheme.error,
                          onTap: onDelete!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m';
      return '${diff.inHours}h';
    }
    if (diff.inDays < 7) return '${diff.inDays}d';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }
}

/// Image area for a listing card. Shows a CachedNetworkImage when a
/// photo is available, otherwise a tasteful gradient placeholder so the
/// cards keep a consistent rhythm even without an image.
class _ListingImage extends StatelessWidget {
  final String? photoUrl;
  final Color accent;
  final bool isLost;
  final ColorScheme scheme;

  const _ListingImage({
    required this.photoUrl,
    required this.accent,
    required this.isLost,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: photoUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: scheme.surfaceVariant),
        errorWidget: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.18),
            scheme.surfaceVariant,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLost ? Icons.help_outline_rounded : Icons.find_in_page_outlined,
            size: 36,
            color: accent.withOpacity(0.6),
          ),
          const SizedBox(height: 6),
          Text(
            isLost ? 'Lost item' : 'Found item',
            style: TextStyle(
              color: accent.withOpacity(0.85),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconBtn({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnerActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _OwnerActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
