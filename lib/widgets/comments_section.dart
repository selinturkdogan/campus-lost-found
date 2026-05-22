import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/comment_service.dart';
import 'user_avatar.dart';

/// Comments list + composer (with @-mention autocomplete) for a listing.
class CommentsSection extends StatefulWidget {
  final String listingId;
  final String listingOwnerId;

  const CommentsSection({
    super.key,
    required this.listingId,
    required this.listingOwnerId,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  // Mention picker state
  List<MentionableUser> _mentionSuggestions = const [];
  bool _showMentionPicker = false;
  int _mentionStartIdx = -1;
  Timer? _searchDebounce;

  // Resolved mentions for the current draft. Maps @display-name → uid.
  // Built up as the user picks suggestions.
  final Map<String, String> _resolvedMentions = {};

  @override
  void dispose() {
    _ctrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onTextChanged(String value) {
    // Find the last @ that's still being typed (no space after it).
    final caret = _ctrl.selection.baseOffset;
    // If caret is unknown, default to end of text (TextField doesn't always
    // report the selection right away on Android).
    final effectiveCaret = caret < 0 ? value.length : caret;
    if (value.isEmpty) {
      _hideMentionPicker();
      return;
    }
    final textBefore = value.substring(0, effectiveCaret);
    final atIdx = textBefore.lastIndexOf('@');
    if (atIdx < 0) {
      _hideMentionPicker();
      return;
    }
    // The @-token continues until a space.
    final token = textBefore.substring(atIdx + 1);
    if (token.contains(' ') || token.contains('\n')) {
      _hideMentionPicker();
      return;
    }

    _mentionStartIdx = atIdx;

    // Show the picker frame immediately so the user gets visual feedback
    // even before the async query finishes.
    if (!_showMentionPicker) {
      setState(() {
        _showMentionPicker = true;
      });
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final matches = await CommentService.searchUsers(token);
        if (!mounted) return;
        setState(() {
          _mentionSuggestions = matches;
          // Keep the picker open even with zero results so we can show a
          // "no users found" hint — otherwise the user has no idea what's
          // happening.
          _showMentionPicker = true;
        });
      } catch (e) {
        debugPrint('Mention search failed: $e');
        if (!mounted) return;
        setState(() {
          _mentionSuggestions = const [];
          _showMentionPicker = true;
        });
      }
    });
  }

  void _hideMentionPicker() {
    if (_showMentionPicker || _mentionSuggestions.isNotEmpty) {
      setState(() {
        _showMentionPicker = false;
        _mentionSuggestions = const [];
        _mentionStartIdx = -1;
      });
    }
  }

  void _insertMention(MentionableUser user) {
    if (_mentionStartIdx < 0) return;
    final caret = _ctrl.selection.baseOffset;
    final before = _ctrl.text.substring(0, _mentionStartIdx);
    final after = _ctrl.text.substring(caret);
    final mentionText = '@${user.displayName.replaceAll(' ', '_')}';
    final newText = '$before$mentionText $after';
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (before + mentionText + ' ').length,
      ),
    );
    _resolvedMentions[mentionText] = user.uid;
    _hideMentionPicker();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Only keep mentions whose token actually still appears in the final
      // text — user may have deleted some.
      final mentions = <String>[];
      for (final entry in _resolvedMentions.entries) {
        if (text.contains(entry.key)) mentions.add(entry.value);
      }
      await CommentService.add(
        listingId: widget.listingId,
        text: text,
        mentions: mentions.toSet().toList(),
      );
      _ctrl.clear();
      _resolvedMentions.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post comment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(Comment c) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: scheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CommentService.delete(
          listingId: widget.listingId, commentId: c.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete comment.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final myUid = auth.user?.uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Comments', style: textTheme.titleMedium),
            const SizedBox(width: 6),
            StreamBuilder<List<Comment>>(
              stream: CommentService.stream(widget.listingId),
              builder: (_, snap) {
                final count = snap.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Composer (only if signed in)
        if (auth.isAuthenticated) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outline),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatar(
                      photoUrl: auth.photoUrl,
                      fallbackName: auth.displayName,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onChanged: _onTextChanged,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          hintText: 'Write a comment… type @ to mention',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showMentionPicker) ...[
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: _mentionSuggestions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Searching users…',
                                  style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _mentionSuggestions.length,
                            itemBuilder: (_, i) {
                              final u = _mentionSuggestions[i];
                              return ListTile(
                                dense: true,
                                leading: UserAvatar(
                                  photoUrl: u.photoUrl,
                                  fallbackName: u.displayName,
                                  size: 28,
                                ),
                                title: Text(u.displayName,
                                    style: textTheme.bodyMedium),
                                subtitle: Text(u.email,
                                    style: textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                                onTap: () => _insertMention(u),
                              );
                            },
                          ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Post'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Comments list
        StreamBuilder<List<Comment>>(
          stream: CommentService.stream(widget.listingId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final comments = snap.data!;
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No comments yet — be the first to comment.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: comments
                  .map((c) => _CommentTile(
                        comment: c,
                        canDelete: myUid != null &&
                            (c.authorId == myUid ||
                                widget.listingOwnerId == myUid ||
                                auth.isAdmin),
                        onDelete: () => _confirmDelete(c),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            photoUrl: comment.authorPhotoUrl,
            fallbackName: comment.authorName,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.authorName,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (comment.createdAt != null)
                      Text(
                        _relTime(comment.createdAt!),
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    if (canDelete)
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 16, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                _CommentBody(text: comment.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('d MMM').format(dt);
  }
}

/// Renders the comment body with @mentions highlighted in the primary color.
class _CommentBody extends StatelessWidget {
  final String text;
  const _CommentBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyMedium;
    final spans = <TextSpan>[];
    final regex = RegExp(r'@[\w\.\-_]+');
    int idx = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ));
      idx = match.end;
    }
    if (idx < text.length) {
      spans.add(TextSpan(text: text.substring(idx)));
    }
    return RichText(
      text: TextSpan(style: base, children: spans),
    );
  }
}
