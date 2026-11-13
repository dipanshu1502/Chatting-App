import 'package:supabase_flutter/supabase_flutter.dart';

import 'presence_service.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    final user = response.user;

    if (user != null) {
      await supabase.from('profiles').insert({
        'id': user.id,
        'name': name,
        'email': email,
        'is_online': false,
      });
    }

    return response;
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;

    if (user != null) {
      await supabase
          .from('profiles')
          .update({'is_online': true})
          .eq('id', user.id);
    }

    // Start realtime presence tracking for this session.
    await PresenceService.instance.startTracking();

    return response;
  }

  Future<void> logout() async {
    // Leave the presence channel first so other users see us offline.
    await PresenceService.instance.stopTracking();

    final user = supabase.auth.currentUser;

    if (user != null) {
      await supabase
          .from('profiles')
          .update({'is_online': false})
          .eq('id', user.id);
    }

    await supabase.auth.signOut();
  }
}
