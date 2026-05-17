import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';
import '../admin/admin_panel_screen.dart';
import '../messages/messages_screen.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback toggleTheme;
  final ThemeMode themeMode;

  const ProfileScreen({
    super.key,
    required this.toggleTheme,
    required this.themeMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('Profile', style: textTheme.displayMedium),
            const SizedBox(height: 28),

            if (auth.isAuthenticated)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          auth.displayName[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
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
                                  auth.displayName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (auth.isAdmin)
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
                          const SizedBox(height: 4),
                          Text(
                            auth.user?.email ?? '',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: scheme.outline, shape: BoxShape.circle),
                      child: Icon(Icons.person_outline_rounded,
                          color: scheme.onSurfaceVariant, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Guest User', style: textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Sign in to post listings',
                              style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.login),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10)),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            _SectionLabel('Appearance'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              iconColor: isDark
                  ? const Color(0xFFA78BFA)
                  : const Color(0xFFF59E0B),
              title: 'Dark mode',
              trailing: Switch.adaptive(
                  value: isDark,
                  onChanged: (_) => toggleTheme(),
                  activeColor: scheme.primary),
            ),

            if (auth.isAuthenticated) ...[
              const SizedBox(height: 24),
              _SectionLabel('Account'),
              const SizedBox(height: 12),

              // Messages button — tüm authenticated kullanıcılar
              _MessagesTile(uid: auth.user!.uid),
              const SizedBox(height: 8),

              if (auth.isAdmin) ...[
                _SettingsTile(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  title: 'Admin Panel',
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminPanelScreen()),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                iconColor: const Color(0xFF7C3AED),
                title: 'Change password',
                trailing: Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
                onTap: () => _showChangePasswordDialog(context),
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.logout_rounded,
                iconColor: scheme.error,
                title: 'Sign out',
                titleColor: scheme.error,
                trailing: Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: scheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: const Text('Sign out?'),
                      content: const Text(
                          'You will need to sign in again to post listings.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                              foregroundColor: scheme.error),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRoutes.login,
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],

            const SizedBox(height: 24),
            _SectionLabel('About'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              iconColor: scheme.primary,
              title: 'Version 1.0.0',
              trailing: const SizedBox.shrink(),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool ob1 = true, ob2 = true, ob3 = true;
    bool loading = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: scheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentCtrl,
                  obscureText: ob1,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    suffixIcon: IconButton(
                      icon: Icon(ob1
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setLocal(() => ob1 = !ob1),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Current password required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: ob2,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(ob2
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setLocal(() => ob2 = !ob2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'New password required';
                    if (v.length < 8) return 'Must be at least 8 characters';
                    if (!RegExp(r'[A-Za-z]').hasMatch(v) ||
                        !RegExp(r'[0-9]').hasMatch(v)) {
                      return 'Must contain letters and numbers';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: ob3,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    suffixIcon: IconButton(
                      icon: Icon(ob3
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setLocal(() => ob3 = !ob3),
                    ),
                  ),
                  validator: (v) =>
                      v != newCtrl.text ? 'Passwords do not match' : null,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText!,
                      style: TextStyle(
                          color: scheme.error, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  loading ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setLocal(() {
                        loading = true;
                        errorText = null;
                      });
                      final auth = context.read<AuthProvider>();
                      final ok = await auth.changePassword(
                        currentPassword: currentCtrl.text,
                        newPassword: newCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Your password has been updated.')),
                        );
                      } else {
                        setLocal(() {
                          loading = false;
                          errorText =
                              auth.errorMessage ?? 'Could not change password.';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesTile extends StatelessWidget {
  final String uid;
  const _MessagesTile({required this.uid});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('chats')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        int totalUnread = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final counts =
                Map<String, dynamic>.from(data['unreadCounts'] ?? {});
            totalUnread += (counts[uid] as num?)?.toInt() ?? 0;
          }
        }

        return _SettingsTile(
          icon: Icons.message_outlined,
          iconColor: const Color(0xFF0EA5E9),
          title: 'Messages',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalUnread > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  constraints:
                      const BoxConstraints(minWidth: 20, minHeight: 20),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    totalUnread > 99 ? '99+' : '$totalUnread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MessagesScreen()),
          ),
        );
      },
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500, color: titleColor),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}