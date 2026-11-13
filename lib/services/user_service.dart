import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getUsers() async {
    final currentUserId = supabase.auth.currentUser!.id;

    final users = await supabase
        .from('profiles')
        .select()
        .neq('id', currentUserId);

    List<Map<String, dynamic>> result = [];

    for (final user in users) {
      final messages = await supabase
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.$currentUserId,receiver_id.eq.${user['id']}),'
            'and(sender_id.eq.${user['id']},receiver_id.eq.$currentUserId)',
          )
          .order('created_at', ascending: false)
          .limit(1);

      String lastMessage = 'Start chatting';
      String lastTime = '';
      String? lastSenderId;
      String? lastCreatedAt;

      if (messages.isNotEmpty) {
        lastMessage = messages[0]['message'] ?? '';
        lastTime = messages[0]['created_at'].toString().substring(11, 16);
        lastSenderId = messages[0]['sender_id']?.toString();
        lastCreatedAt = messages[0]['created_at']?.toString();
      }

      result.add({
        ...user,
        'last_message': lastMessage,
        'last_time': lastTime,
        'last_sender_id': lastSenderId,
        'last_created_at': lastCreatedAt,
        'is_online': user['is_online'] ?? false,
      });
    }

    return result;
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) return null;

    return await supabase.from('profiles').select().eq('id', userId).single();
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    return await supabase.from('profiles').select().eq('id', userId).single();
  }

  Future<String> uploadProfileImage(Uint8List imageBytes) async {
    final userId = supabase.auth.currentUser!.id;

    final filePath = '$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage
        .from('profile-images')
        .uploadBinary(
          filePath,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final imageUrl = supabase.storage
        .from('profile-images')
        .getPublicUrl(filePath);

    await supabase
        .from('profiles')
        .update({'avatar_url': imageUrl})
        .eq('id', userId);

    return imageUrl;
  }
}
