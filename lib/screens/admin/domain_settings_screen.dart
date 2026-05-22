import 'package:flutter/material.dart';
import '../../services/domains_service.dart';
import '../../utils/app_theme.dart';

class DomainSettingsScreen extends StatefulWidget {
  const DomainSettingsScreen({super.key});

  @override
  State<DomainSettingsScreen> createState() => _DomainSettingsScreenState();
}

class _DomainSettingsScreenState extends State<DomainSettingsScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    final cleaned = raw.toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (!cleaned.contains('.') || cleaned.contains(' ')) {
      _snack('Please enter a valid domain (e.g. final.edu.tr)', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await DomainsService.add(cleaned);
      _ctrl.clear();
      if (mounted) _snack('Domain added.');
    } catch (_) {
      if (mounted) {
        _snack('Could not add domain. Are you signed in as admin?',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(String domain) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: scheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove domain?'),
        content: Text(
            'Users with @$domain emails will no longer be able to register or reset passwords.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DomainsService.remove(domain);
      if (mounted) _snack('Domain removed.');
    } catch (_) {
      if (mounted) _snack('Could not remove domain.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? scheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : null,
          color: isDark ? null : scheme.surface,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
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
                        child: Icon(Icons.arrow_back_rounded,
                            size: 18, color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Allowed Domains',
                            style: textTheme.titleMedium),
                        Text('Manage which email domains can sign up',
                            style: textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Warning banner if list is empty
                      StreamBuilder<List<String>>(
                        stream: DomainsService.stream(),
                        builder: (context, snap) {
                          final list = snap.data ?? const [];
                          if (list.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB020)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFFFFB020)
                                        .withOpacity(0.5)),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Color(0xFFFFB020), size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'No domains are allowed. New users cannot register and existing users cannot reset their password. Add at least one domain below.',
                                      style: textTheme.bodySmall
                                          ?.copyWith(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      Text('Add a domain', style: textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              enabled: !_busy,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _add(),
                              decoration: const InputDecoration(
                                hintText: 'e.g. final.edu.tr',
                                prefixIcon: Icon(
                                    Icons.alternate_email_rounded,
                                    size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _add,
                              child: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2))
                                  : const Text('Add'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),
                      Text('Active domains', style: textTheme.titleSmall),
                      const SizedBox(height: 8),

                      StreamBuilder<List<String>>(
                        stream: DomainsService.stream(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                  child: CircularProgressIndicator()),
                            );
                          }
                          final domains = snap.data!;
                          if (domains.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color:
                                    scheme.surfaceVariant.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'No domains configured yet.',
                                style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return Column(
                            children: domains
                                .map((d) => Container(
                                      margin: const EdgeInsets.only(
                                          bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: scheme.surface,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border:
                                            Border.all(color: scheme.outline),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.public_rounded,
                                              size: 16,
                                              color: scheme.primary),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text('@$d',
                                                style: textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                )),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                _confirmRemove(d),
                                            icon: Icon(
                                                Icons
                                                    .delete_outline_rounded,
                                                color: scheme.error,
                                                size: 20),
                                            tooltip: 'Remove',
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 20),
                      Text(
                        'Changes take effect immediately. The Cloud Function checks the live list for every sign-up and password reset request.',
                        style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
