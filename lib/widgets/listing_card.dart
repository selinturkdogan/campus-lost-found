import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/listing_model.dart';
import '../utils/app_routes.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLost = listing.type == 'lost';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.listingDetail, arguments: listing),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outline, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top image — only show if photo exists
            if (listing.photoUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child: CachedNetworkImage(
                  imageUrl: listing.photoUrl!,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: double.infinity,
                    height: 160,
                    color: scheme.surfaceVariant,
                  ),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge + time
                  Row(
                    children: [
                      _TypeBadge(isLost: isLost, scheme: scheme),
                      const Spacer(),
                      Text(_formatDate(listing.createdAt), style: textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Title
                  Text(
                    listing.title,
                    style: textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Description
                  Text(
                    listing.description,
                    style: textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Location + owner
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(listing.location, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.person_outline_rounded, size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(listing.ownerName, style: textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),

            // Owner actions
            if (showOwnerActions) ...[
              Divider(color: scheme.outline, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    if (!listing.isResolved && onResolve != null)
                      _ActionBtn(
                        label: 'Mark as Resolved',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green,
                        onTap: onResolve!,
                      ),
                    const Spacer(),
                    if (onEdit != null)
                      _ActionBtn(label: 'Edit', icon: Icons.edit_outlined, color: scheme.primary, onTap: onEdit!),
                    const SizedBox(width: 16),
                    if (onDelete != null)
                      _ActionBtn(label: 'Delete', icon: Icons.delete_outline_rounded, color: scheme.error, onTap: onDelete!),
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
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }
}

class _PlaceholderImage extends StatelessWidget {
  final ColorScheme scheme;
  const _PlaceholderImage({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      color: scheme.surfaceVariant,
      child: Icon(Icons.image_not_supported_outlined, color: scheme.onSurfaceVariant, size: 32),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isLost;
  final ColorScheme scheme;
  const _TypeBadge({required this.isLost, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = isLost ? scheme.error : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(isLost ? 'Lost' : 'Found', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}