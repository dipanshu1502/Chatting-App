import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/chat/chat_screen.dart';
import '../utils/app_navigator.dart';
import 'unread_service.dart';
import 'user_service.dart';

/// Listens to the Supabase Realtime `messages` table for new incoming
/// messages and surfaces them as system notifications.
///
/// - A notification is shown for every incoming message, even while the app
///   is open — as long as the conversation the message arrived in is not
///   currently open. The open chat highlights the new bubble in-app instead.
/// - Tapping a notification opens the sender's chat via the global navigator.
///
/// Note: this works while the app process is alive (foreground/background).
/// Notifications when the app is fully killed require FCM push, which is a
/// separate infrastructure setup.
class NotificationService {
  NotificationService._();

  /// Singleton so the whole app shares one realtime subscription.
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'messages';
  static const String _channelName = 'Messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final SupabaseClient _supabase = Supabase.instance.client;

  final UserService _userService = UserService();

  RealtimeChannel? _channel;

  final Map<String, Map<String, dynamic>> _profileCache = {};

  bool _initialized = false;

  /// The chat the user is currently viewing, if any. While it is set and the
  /// app is in the foreground, messages from this sender do not notify (the
  /// open chat highlights the new bubble in-app instead).
  String? _activeChatId;

  set activeChatId(String? value) => _activeChatId = value;

  /// Initializes the plugin and wires up auth-based start/stop.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open chat'),
      windows: WindowsInitializationSettings(
        appName: 'Chatting App',
        appUserModelId: 'com.example.chattingapp',
        guid: 'A4E5D6C7-8B90-4C2D-9E1F-3A5B7C9D1E2F',
      ),
      web: WebInitializationSettings(),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _requestPermissions();

    // Start/stop the realtime listener together with the auth session.
    // The subscription lives for the app's lifetime, so it isn't stored.
    _supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        start();
      } else if (state.event == AuthChangeEvent.signedOut) {
        stop();
      }
    });

    if (_supabase.auth.currentSession != null) {
      start();
    }
  }

  /// Subscribes to new messages addressed to the current user.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops until [stop].
  void start() {
    if (_channel != null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = _supabase
        .channel('message-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (payload) {
            unawaited(_handleNewMessage(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Cancels the realtime subscription (e.g. on logout).
  Future<void> stop() async {
    final channel = _channel;
    _channel = null;

    if (channel != null) {
      try {
        await _supabase.removeChannel(channel);
      } catch (_) {}
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {
      // Permissions are best-effort; the platform may not support the call.
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> message) async {
    final senderId = message['sender_id']?.toString();
    if (senderId == null || senderId.isEmpty) return;

    // Let the home chat list refresh its unread highlight.
    UnreadService.instance.notifyNewMessage();

    // Skip only when the user is actively reading this very conversation
    // (app in the foreground). Messages for any other conversation still
    // notify even while the app is open.
    final appResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (appResumed && _activeChatId == senderId) return;

    final body = message['message']?.toString() ?? '';
    final profile = await _loadProfile(senderId);
    final senderName = (profile['name'] ?? 'New message').toString();

    await _plugin.show(
      id: senderId.hashCode & 0x7FFFFFFF,
      title: senderName,
      body: body,
      notificationDetails: _details(),
      payload: senderId,
    );
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Notifications for incoming chat messages',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<Map<String, dynamic>> _loadProfile(String userId) async {
    final cached = _profileCache[userId];
    if (cached != null) return cached;

    try {
      final profile = await _userService.getUserProfile(userId);
      if (profile != null) {
        _profileCache[userId] = profile;
        return profile;
      }
    } catch (_) {}

    return const <String, dynamic>{};
  }

  /// Opens the sender's chat when a notification is tapped.
  Future<void> _onNotificationTap(NotificationResponse response) async {
    final senderId = response.payload;
    if (senderId == null || senderId.isEmpty) return;

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    final profile = await _loadProfile(senderId);

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          receiverId: senderId,
          receiverName: (profile['name'] ?? 'Chat').toString(),
          receiverAvatar: profile['avatar_url']?.toString(),
        ),
      ),
    );
  }
}