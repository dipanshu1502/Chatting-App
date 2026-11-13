import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks which users are currently online using Supabase Realtime Presence.
///
/// Unlike the old `is_online` database flag (which stayed `true` when the app
/// was killed or the connection dropped), presence is managed by the Realtime
/// server: a user is only present while their app is actually connected, so
/// the status self-corrects on app kill, crash or network loss.
class PresenceService {
  PresenceService._();

  /// Singleton so every screen observes the same presence channel.
  static final PresenceService instance = PresenceService._();

  static const String _channelName = 'online-users';

  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _channel;

  final Set<String> _onlineUserIds = {};

  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  /// Stream emitting the set of currently-online user IDs on every change.
  Stream<Set<String>> get onlineUsersStream => _controller.stream;

  /// Snapshot of the currently-online user IDs.
  Set<String> get onlineUserIds => Set<String>.unmodifiable(_onlineUserIds);

  /// Whether the given user is currently online.
  bool isOnline(String userId) => _onlineUserIds.contains(userId);

  /// Joins the presence channel and starts tracking the current user.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops until
  /// [stopTracking] is called.
  Future<void> startTracking() async {
    if (_channel != null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final channel = _supabase.channel(_channelName);

    channel
        .onPresenceSync((RealtimePresenceSyncPayload payload) => _sync())
        .onPresenceJoin((RealtimePresenceJoinPayload payload) => _sync())
        .onPresenceLeave((RealtimePresenceLeavePayload payload) => _sync());

    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({
          'user_id': userId,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });

        // Our own presence is now part of the local state.
        _sync();
      }
    });

    _channel = channel;
  }

  /// Stops tracking and leaves the presence channel.
  ///
  /// Also called on logout so other users immediately see us offline.
  Future<void> stopTracking() async {
    final channel = _channel;
    _channel = null;

    _onlineUserIds.clear();
    _emit();

    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {}

      try {
        await _supabase.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Rebuilds the online set from the channel's current presence state.
  void _sync() {
    final channel = _channel;
    if (channel == null) return;

    final ids = <String>{};

    for (final state in channel.presenceState()) {
      for (final presence in state.presences) {
        final userId = presence.payload['user_id'];
        if (userId != null) ids.add(userId.toString());
      }
    }

    final unchanged =
        ids.length == _onlineUserIds.length && ids.containsAll(_onlineUserIds);
    if (unchanged) return;

    _onlineUserIds
      ..clear()
      ..addAll(ids);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(Set<String>.unmodifiable(_onlineUserIds));
    }
  }
}
