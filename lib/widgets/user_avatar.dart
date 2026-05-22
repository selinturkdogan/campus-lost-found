import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A small reusable avatar widget. Shows the user's profile photo if
/// available, otherwise falls back to the first letter of the display name
/// on a coloured circle.
///
/// There are two ways to use it:
///   * Pass [photoUrl] and [fallbackName] directly when you already have
///     them in scope (e.g. inside the chat header or a listing card).
///   * Pass [uid] only and the widget will look the user up in Firestore.
///     Useful when you only know the UID (e.g. in messages list).
class UserAvatar extends StatelessWidget {
  final String? uid;
  final String? photoUrl;
  final String? fallbackName;
  final double size;
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    this.uid,
    this.photoUrl,
    this.fallbackName,
    this.size = 40,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Direct mode — we already have the data.
    if (uid == null || photoUrl != null) {
      return _AvatarCircle(
        photoUrl: photoUrl,
        fallbackName: fallbackName,
        size: size,
        backgroundColor: backgroundColor,
      );
    }

    // Lookup mode — fetch the user doc by uid.
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        String? fetchedPhoto;
        String? fetchedName = fallbackName;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          fetchedPhoto = data?['photoUrl'] as String?;
          fetchedName = (data?['displayName'] as String?) ?? fallbackName;
        }
        return _AvatarCircle(
          photoUrl: fetchedPhoto,
          fallbackName: fetchedName,
          size: size,
          backgroundColor: backgroundColor,
        );
      },
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String? photoUrl;
  final String? fallbackName;
  final double size;
  final Color? backgroundColor;

  const _AvatarCircle({
    required this.photoUrl,
    required this.fallbackName,
    required this.size,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.primary.withOpacity(0.15);
    final letter = (fallbackName?.trim().isNotEmpty == true)
        ? fallbackName!.trim()[0].toUpperCase()
        : '?';

    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _letterFallback(scheme, bg, letter),
          errorWidget: (_, __, ___) => _letterFallback(scheme, bg, letter),
        ),
      );
    }
    return _letterFallback(scheme, bg, letter);
  }

  Widget _letterFallback(ColorScheme scheme, Color bg, String letter) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
