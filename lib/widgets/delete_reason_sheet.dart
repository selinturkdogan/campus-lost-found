import 'package:flutter/material.dart';

/// Result returned by [showDeleteReasonSheet].
///
/// [action] tells the caller whether to RESOLVE (mark the listing as
/// fixed-up but keep it in history) or DELETE it for good. [reason] is a
/// stable string ID we persist to Firestore. [text] is the optional
/// free-form description for the "other" branch.
class DeleteReasonResult {
  final DeleteReasonAction action;
  final String reason;
  final String? text;

  const DeleteReasonResult({
    required this.action,
    required this.reason,
    this.text,
  });
}

enum DeleteReasonAction { resolve, delete }

/// Shows the modal sheet and returns the user's choice, or `null` if they
/// dismissed it without picking one.
Future<DeleteReasonResult?> showDeleteReasonSheet(
  BuildContext context, {
  required String listingTitle,
}) {
  return showModalBottomSheet<DeleteReasonResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeleteReasonSheet(listingTitle: listingTitle),
  );
}

class _DeleteReasonSheet extends StatefulWidget {
  final String listingTitle;
  const _DeleteReasonSheet({required this.listingTitle});

  @override
  State<_DeleteReasonSheet> createState() => _DeleteReasonSheetState();
}

class _DeleteReasonSheetState extends State<_DeleteReasonSheet> {
  String? _selected;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selected == null) return;
    if (_selected == 'found') {
      Navigator.pop(
        context,
        const DeleteReasonResult(
          action: DeleteReasonAction.resolve,
          reason: 'found',
        ),
      );
      return;
    }
    if (_selected == 'other' && _otherCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the reason.')),
      );
      return;
    }
    Navigator.pop(
      context,
      DeleteReasonResult(
        action: DeleteReasonAction.delete,
        reason: _selected!,
        text: _selected == 'other' ? _otherCtrl.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Why are you removing this listing?',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.listingTitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                _ReasonTile(
                  id: 'found',
                  selected: _selected == 'found',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF22C55E),
                  title: 'It was found / returned',
                  subtitle:
                      'Marks the listing as resolved so others see the happy ending.',
                  onTap: () => setState(() => _selected = 'found'),
                ),
                const SizedBox(height: 8),
                _ReasonTile(
                  id: 'mistake',
                  selected: _selected == 'mistake',
                  icon: Icons.undo_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Posted by mistake',
                  subtitle: 'The listing will be deleted permanently.',
                  onTap: () => setState(() => _selected = 'mistake'),
                ),
                const SizedBox(height: 8),
                _ReasonTile(
                  id: 'no_longer_needed',
                  selected: _selected == 'no_longer_needed',
                  icon: Icons.do_not_disturb_alt_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'No longer needed',
                  subtitle: 'I solved the problem outside the app.',
                  onTap: () => setState(() => _selected = 'no_longer_needed'),
                ),
                const SizedBox(height: 8),
                _ReasonTile(
                  id: 'other',
                  selected: _selected == 'other',
                  icon: Icons.edit_note_rounded,
                  iconColor: scheme.onSurfaceVariant,
                  title: 'Other (specify)',
                  subtitle: 'Tell us briefly why you are removing this.',
                  onTap: () => setState(() => _selected = 'other'),
                ),

                if (_selected == 'other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otherCtrl,
                    maxLength: 120,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Type your reason…',
                      filled: true,
                      fillColor: scheme.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selected == null ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _selected == 'found'
                              ? const Color(0xFF22C55E)
                              : scheme.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          _selected == 'found' ? 'Mark as resolved' : 'Delete',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String id;
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.id,
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withOpacity(0.08)
              : scheme.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline.withOpacity(0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant, fontSize: 11.5)),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}
