import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks, per conversation, the point up to which messages have been seen.
///
/// A conversation counts as unread while its latest message was sent by the
/// other user and is newer than the stored "seen" timestamp. The state is
/// persisted with SharedPreferences so highlights survive app restarts.
class UnreadService extends ChangeNotifier {
  UnreadService._();

  /// Singleton shared across the app (home list, chat screen, notifications).
  static final UnreadService instance = UnreadService._();

  static const String _storageKey = 'chat_last_seen_at_v1';

  /// chatUserId -> ISO-8601 UTC timestamp of the last "seen" moment.
  final Map<String, String> _lastSeenAt = {};

  Future<void>? _loadFuture;

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) {
              _lastSeenAt[key] = value;
            }
          });
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage: start with a clean slate.
      _lastSeenAt.clear();
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_lastSeenAt));
    } catch (_) {
      // Persistence is best-effort; in-memory state still works.
    }
  }

  /// Marks every message in [chatUserId]'s conversation as seen up to [at]
  /// (defaults to now). The marker never moves backwards.
  Future<void> markSeen(String chatUserId, {DateTime? at}) async {
    await _ensureLoaded();

    final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    final existing = _lastSeenAt[chatUserId];

    if (existing != null) {
      try {
        if (DateTime.parse(existing).isAfter(DateTime.parse(stamp))) return;
      } catch (_) {}
    }

    _lastSeenAt[chatUserId] = stamp;
    await _persist();
    notifyListeners();
  }

  /// Whether [chatUserId]'s conversation has messages the current user has
  /// not seen yet.
  ///
  /// A conversation is unread when its latest message ([lastSenderId] /
  /// [lastCreatedAt]) was sent by the other user and is newer than the last
  /// seen marker. A conversation that was never opened is always unread
  /// while it has at least one incoming message.
  bool isChatUnread({
    required String chatUserId,
    required String currentUserId,
    String? lastSenderId,
    String? lastCreatedAt,
  }) {
    if (lastSenderId == null ||
        lastSenderId.isEmpty ||
        lastCreatedAt == null ||
        lastCreatedAt.isEmpty) {
      return false;
    }

    // My own last message can never make the conversation unread.
    if (lastSenderId == currentUserId) return false;

    final seenAt = _lastSeenAt[chatUserId];
    if (seenAt == null) return true;

    try {
      return DateTime.parse(lastCreatedAt).isAfter(DateTime.parse(seenAt));
    } catch (_) {
      return false;
    }
  }

  /// Forces listeners (e.g. the home chat list) to recompute unread state,
  /// e.g. right after a new message arrives.
  void notifyNewMessage() => notifyListeners();

  /// Clears in-memory state and reloads it from storage. Only for tests.
  @visibleForTesting
  Future<void> reset() async {
    _lastSeenAt.clear();
    _loadFuture = null;
    await _ensureLoaded();
  }
}