import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// CRUD for comments under a listing.
///
/// Comments live at `listings/{listingId}/comments/{commentId}` with shape:
///   {
///     authorId, authorName, authorPhotoUrl,
///     text, mentions: [uid, ...],
///     createdAt
///   }
class CommentService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ref(String listingId) =>
      _db.collection('listings').doc(listingId).collection('comments');

  /// Live stream of comments for a listing (newest first).
  static Stream<List<Comment>> stream(String listingId) {
    return _ref(listingId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Comment.fromDoc).toList());
  }

  /// Add a new comment. [mentions] is a list of UIDs that were @-mentioned.
  static Future<void> add({
    required String listingId,
    required String text,
    required List<String> mentions,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    // Fetch the author's displayName / photoUrl from their user doc so the
    // comment has a stable snapshot even if the user updates their profile.
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? {};
    final authorName = (data['displayName'] as String?) ??
        user.displayName ??
        user.email?.split('@').first ??
        'Student';
    final authorPhoto = data['photoUrl'] as String?;

    await _ref(listingId).add({
      'authorId': user.uid,
      'authorName': authorName,
      'authorPhotoUrl': authorPhoto,
      'text': text.trim(),
      'mentions': mentions,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a comment. Only the author, the listing owner, or an admin
  /// should call this — enforced by Firestore rules.
  static Future<void> delete({
    required String listingId,
    required String commentId,
  }) async {
    await _ref(listingId).doc(commentId).delete();
  }

  /// Search users for the @-mention picker.
  /// Returns at most 6 matches. If [prefix] is empty, returns the first
  /// few users (so the picker shows something the moment the user types `@`).
  /// Matching is case-insensitive AND diacritic-insensitive so typing
  /// "ozgur" finds "Özgür".
  static Future<List<MentionableUser>> searchUsers(String prefix) async {
    final p = _foldDiacritics(prefix.trim().toLowerCase());

    // Pull a small batch and filter client-side — fine for a campus app.
    final snap = await _db.collection('users').limit(50).get();
    final matches = <MentionableUser>[];
    for (final d in snap.docs) {
      final data = d.data();
      final rawName = (data['displayName'] as String? ?? '').toLowerCase();
      final rawEmail = (data['email'] as String? ?? '').toLowerCase();
      final name = _foldDiacritics(rawName);
      final email = _foldDiacritics(rawEmail);

      // Empty prefix → show everyone (capped to 6).
      // Otherwise → match anywhere in the name/email (contains, not just prefix).
      final matchesQuery =
          p.isEmpty || name.contains(p) || email.contains(p);

      if (matchesQuery) {
        matches.add(MentionableUser(
          uid: d.id,
          displayName: data['displayName'] ?? 'Student',
          email: data['email'] ?? '',
          photoUrl: data['photoUrl'] as String?,
        ));
        if (matches.length >= 6) break;
      }
    }
    return matches;
  }

  /// Replace Turkish/diacritic characters with their ASCII equivalents
  /// so the picker matches "Özgür" when the user types "ozgur".
  static String _foldDiacritics(String s) {
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u',
      'é': 'e', 'è': 'e', 'ê': 'e',
      'á': 'a', 'à': 'a', 'ä': 'a',
      'ó': 'o', 'ô': 'o',
      'ú': 'u',
      'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }
}

class Comment {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final List<String> mentions;
  final DateTime? createdAt;

  Comment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.text,
    required this.mentions,
    required this.createdAt,
  });

  factory Comment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    return Comment(
      id: d.id,
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Student',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      text: data['text'] ?? '',
      mentions: (data['mentions'] as List?)?.cast<String>() ?? const [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MentionableUser {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  const MentionableUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
  });
}
