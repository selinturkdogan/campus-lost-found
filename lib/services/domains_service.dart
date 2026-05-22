import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the admin-managed list of allowed email domains from Firestore.
///
/// The list lives at `config/allowed_domains` as:
///   { domains: ['final.edu.tr', 'stu.final.edu.tr'] }
///
/// Used both for client-side UX (validation + hints on the login screen)
/// and for displaying the current state in the admin panel.
class DomainsService {
  static final _ref =
      FirebaseFirestore.instance.collection('config').doc('allowed_domains');

  /// One-shot read. Returns an empty list if the doc is missing or invalid.
  static Future<List<String>> fetch() async {
    try {
      final snap = await _ref.get();
      return _parse(snap.data());
    } catch (_) {
      return const [];
    }
  }

  /// Live stream — admin panel and login screen use this so they update
  /// instantly when a domain is added or removed.
  static Stream<List<String>> stream() {
    return _ref.snapshots().map((snap) => _parse(snap.data()));
  }

  /// Add a single domain. Must be called by an admin user.
  /// Strips leading "@" and lowercases.
  static Future<void> add(String raw) async {
    final domain = _normalize(raw);
    if (domain.isEmpty) {
      throw ArgumentError('Domain cannot be empty');
    }
    await _ref.set({
      'domains': FieldValue.arrayUnion([domain]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Remove a domain from the whitelist.
  static Future<void> remove(String raw) async {
    final domain = _normalize(raw);
    await _ref.set({
      'domains': FieldValue.arrayRemove([domain]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static List<String> _parse(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['domains'];
    if (raw is! List) return const [];
    return raw
        .map((d) => d.toString().toLowerCase().trim())
        .where((d) => d.isNotEmpty)
        .toList();
  }

  static String _normalize(String raw) {
    var d = raw.toLowerCase().trim();
    if (d.startsWith('@')) d = d.substring(1);
    return d;
  }
}
