import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'utils/app_navigator.dart';
import 'utils/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/notification_service.dart';
import 'services/presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Light status bar icons so the time/battery stay visible on the
  // dark gradient headers.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  await Supabase.initialize(
    url: 'https://uznlcnjxpbawlldqfiho.supabase.co',
    anonKey: 'sb_publishable_FEMR27wWZO4bj-iQCauYUg_Z63Do9aQ',
  );

  // If a persisted session was restored, start realtime presence tracking.
  // No-op when not logged in.
  await PresenceService.instance.startTracking();

  // Start the global incoming-message notification watcher.
  await NotificationService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chatting App',
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light,
      home: session != null ? const HomeScreen() : const LoginScreen(),
    );
  }
}
