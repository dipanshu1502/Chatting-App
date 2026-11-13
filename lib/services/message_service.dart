import 'package:supabase_flutter/supabase_flutter.dart';

class MessageService {
  final supabase = Supabase.instance.client;

  Future<void> sendMessage({
    required String receiverId,
    required String message,
  }) async {
    await supabase.from('messages').insert({
      'sender_id': supabase.auth.currentUser!.id,
      'receiver_id': receiverId,
      'message': message,
    });
  }

  Stream<List<Map<String, dynamic>>> getMessages({
    required String otherUserId,
  }) {
    final currentUserId = supabase.auth.currentUser!.id;

    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((data) {
          final filteredMessages = data.where((msg) {
            return (msg['sender_id'] == currentUserId &&
                    msg['receiver_id'] == otherUserId) ||
                (msg['sender_id'] == otherUserId &&
                    msg['receiver_id'] == currentUserId);
          }).toList();

          filteredMessages.sort(
            (a, b) => DateTime.parse(
              a['created_at'],
            ).compareTo(DateTime.parse(b['created_at'])),
          );

          return filteredMessages;
        });
  }
}
