import 'package:flutter/material.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as user_models;

class UserDisplay {
  static String shortId(String id, {String fallbackLabel = 'User'}) {
    if (id.isEmpty) return fallbackLabel;
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  static String nameOrFallback(user_models.AppUser? u, String userId,
      {String? fallbackLabel}) {
    if (u != null) {
      if ((u.displayName?.isNotEmpty ?? false)) return u.displayName!;
      if (u.email.isNotEmpty) return u.email;
    }
    return shortId(userId, fallbackLabel: fallbackLabel ?? 'User');
  }

  static Widget avatarCircle(
      {required user_models.AppUser? user, required String userId}) {
    final initials = _initialsFromUser(user) ??
        shortId(userId).characters.take(2).toString();
    if (user?.photoUrl != null) {
      return CircleAvatar(backgroundImage: NetworkImage(user!.photoUrl!));
    }
    return CircleAvatar(child: Text(initials));
  }

  static String? _initialsFromUser(user_models.AppUser? u) {
    final src = (u?.displayName?.isNotEmpty ?? false)
        ? u!.displayName!
        : (u?.email ?? '');
    if (src.isEmpty) return null;
    return src.trim().characters.take(2).toString();
  }
}
