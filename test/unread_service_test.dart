import 'package:chattingapp/services/unread_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('never-opened chat with an incoming message is unread', () async {
    SharedPreferences.setMockInitialValues({});
    final service = UnreadService.instance;
    await service.reset();

    expect(
      service.isChatUnread(
        chatUserId: 'user-1',
        currentUserId: 'me',
        lastSenderId: 'user-1',
        lastCreatedAt: '2026-09-14T10:00:00Z',
      ),
      isTrue,
    );
  });

  test('markSeen clears the highlight until a newer message arrives',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = UnreadService.instance;
    await service.reset();

    await service.markSeen('user-1', at: DateTime.utc(2026, 9, 14, 11, 0));

    // Older than the seen marker -> not unread.
    expect(
      service.isChatUnread(
        chatUserId: 'user-1',
        currentUserId: 'me',
        lastSenderId: 'user-1',
        lastCreatedAt: '2026-09-14T10:00:00Z',
      ),
      isFalse,
    );

    // Newer than the seen marker -> unread again.
    expect(
      service.isChatUnread(
        chatUserId: 'user-1',
        currentUserId: 'me',
        lastSenderId: 'user-1',
        lastCreatedAt: '2026-09-14T12:00:00Z',
      ),
      isTrue,
    );
  });

  test('own last message never marks the chat unread', () async {
    SharedPreferences.setMockInitialValues({});
    final service = UnreadService.instance;
    await service.reset();

    expect(
      service.isChatUnread(
        chatUserId: 'user-1',
        currentUserId: 'me',
        lastSenderId: 'me',
        lastCreatedAt: '2026-09-14T10:00:00Z',
      ),
      isFalse,
    );
  });

  test('seen markers persist via SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'chat_last_seen_at_v1': '{"user-2": "2026-09-14T09:00:00.000Z"}',
    });
    final service = UnreadService.instance;
    await service.reset();

    // Message before the persisted seen marker -> not unread.
    expect(
      service.isChatUnread(
        chatUserId: 'user-2',
        currentUserId: 'me',
        lastSenderId: 'user-2',
        lastCreatedAt: '2026-09-14T08:00:00Z',
      ),
      isFalse,
    );

    // Message after the persisted seen marker -> unread.
    expect(
      service.isChatUnread(
        chatUserId: 'user-2',
        currentUserId: 'me',
        lastSenderId: 'user-2',
        lastCreatedAt: '2026-09-14T10:00:00Z',
      ),
      isTrue,
    );
  });
}