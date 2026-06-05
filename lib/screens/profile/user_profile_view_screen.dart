import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/user_avatar.dart';

/// Read-only profile screen for *another* user.
///
/// Shows the user's avatar, display name, department, bio, and the public
/// versions of phone/city (only if the owner has flagged them public).
///
/// Also includes a Block / Unblock action so a participant can stop
/// receiving messages from this person.
class UserProfileViewScreen extends StatefulWidget {
  final String uid;
  final String fallbackName;

  const UserProfileViewScreen({
    super.key,
    required this.uid,
    this.fallbackName = '',
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  bool _busy = false;

  Future<void> _toggleBlock(BuildContext context, bool currentlyBlocked) async {
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(currentlyBlocked ? 'Unblock user?' : 'Block this user?'),
        content: Text(
          currentlyBlocked
              ? 'You will start seeing their messages and listings again.'
              : 'They will no longer be able to message you, and their conversations '
                'will be hidden from your messages list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  currentlyBlocked ? null : Theme.of(context).colorScheme.error,
            ),
            child: Text(currentlyBlocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final ok = currentlyBlocked
        ? await auth.unblockUser(widget.uid)
        : await auth.blockUser(widget.uid);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (currentlyBlocked ? 'User unblocked.' : 'User blocked.')
              : 'Action failed. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final isSelf = auth.user?.uid == widget.uid;
    final isBlocked = auth.isBlocked(widget.uid);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.uid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data =
                (snap.data?.data() as Map<String, dynamic>?) ?? const {};
            final displayName = (data['displayName'] as String?) ??
                (widget.fallbackName.isNotEmpty ? widget.fallbackName : 'User');
            final email = data['email'] as String?;
            final photoUrl = data['photoUrl'] as String?;
            final phone = data['phone'] as String?;
            final city = data['city'] as String?;
            final department = data['department'] as String?;
            final bio = data['bio'] as String?;
            final phonePublic = data['phonePublic'] == true;
            final cityPublic = data['cityPublic'] == true;
            final isAdmin = data['isAdmin'] == true;
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!isSelf)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz_rounded,
                              color: scheme.onSurface),
                          onSelected: (val) {
                            if (val == 'block') _toggleBlock(context, isBlocked);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'block',
                              child: Row(
                                children: [
                                  Icon(
                                    isBlocked
                                        ? Icons.lock_open_rounded
                                        : Icons.block_rounded,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(isBlocked ? 'Unblock user' : 'Block user'),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Header card with avatar + name + email
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C3AED).withOpacity(0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          photoUrl: photoUrl,
                          fallbackName: displayName,
                          size: 64,
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (isAdmin)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.shield_rounded,
                                              size: 12, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text('Admin',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (email != null && email.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (createdAt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Member since ${DateFormat.yMMM().format(createdAt)}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isBlocked && !isSelf) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.error.withOpacity(0.08),
                        border: Border.all(color: scheme.error.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded,
                              size: 18, color: scheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You have blocked this user. They cannot message you.',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  _SectionLabel('About'),
                  const SizedBox(height: 10),

                  if ((bio == null || bio.isEmpty) &&
                      (department == null || department.isEmpty))
                    _InfoTile(
                      icon: Icons.info_outline_rounded,
                      label: 'No bio yet.',
                      iconColor: scheme.onSurfaceVariant,
                    ),

                  if (department != null && department.isNotEmpty)
                    _InfoTile(
                      icon: Icons.school_outlined,
                      label: department,
                      iconColor: const Color(0xFF7C3AED),
                    ),
                  if (bio != null && bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoTile(
                      icon: Icons.format_quote_rounded,
                      label: bio,
                      iconColor: const Color(0xFF0EA5E9),
                      multiLine: true,
                    ),
                  ],

                  const SizedBox(height: 24),
                  _SectionLabel('Contact'),
                  const SizedBox(height: 10),

                  if (phone != null && phone.isNotEmpty && phonePublic)
                    _InfoTile(
                      icon: Icons.phone_outlined,
                      label: phone,
                      iconColor: const Color(0xFF22C55E),
                    ),
                  if (city != null && city.isNotEmpty && cityPublic) ...[
                    const SizedBox(height: 8),
                    _InfoTile(
                      icon: Icons.location_city_outlined,
                      label: city,
                      iconColor: const Color(0xFFF59E0B),
                    ),
                  ],
                  if ((phone == null || phone.isEmpty || !phonePublic) &&
                      (city == null || city.isEmpty || !cityPublic))
                    _InfoTile(
                      icon: Icons.lock_outline_rounded,
                      label: 'This user has not shared any contact info.',
                      iconColor: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final bool multiLine;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.multiLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment:
            multiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: multiLine ? null : 2,
              overflow: multiLine ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
