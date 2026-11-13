import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/message_service.dart';
import '../../services/notification_service.dart';
import '../../services/presence_service.dart';
import '../../services/unread_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;

  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessageService messageService = MessageService();

  final TextEditingController messageController = TextEditingController();

  final ScrollController scrollController = ScrollController();

  final currentUserId = Supabase.instance.client.auth.currentUser!.id;

  bool isOnline = false;

  StreamSubscription<Set<String>>? _presenceSub;

  // Bookkeeping to detect freshly arrived incoming messages so the newest
  // one can be highlighted in the list.
  String? _lastSeenMessageId;
  bool _hasSeenMessages = false;

  @override
  void initState() {
    super.initState();

    // Suppress system notifications for THIS conversation while it is open
    // in the foreground; the open chat highlights the new bubble instead.
    // Messages in any other conversation still notify.
    NotificationService.instance.activeChatId = widget.receiverId;

    // Mark everything up to now as seen so the home list highlight clears.
    unawaited(UnreadService.instance.markSeen(widget.receiverId));

    // Seed from already-synced presence, then listen for live changes.
    isOnline = PresenceService.instance.isOnline(widget.receiverId);
    _presenceSub = PresenceService.instance.onlineUsersStream.listen((ids) {
      final nowOnline = ids.contains(widget.receiverId);
      if (!mounted || nowOnline == isOnline) return;
      setState(() => isOnline = nowOnline);
    });
  }

  @override
  void dispose() {
    // Anything received while the chat was open counts as seen on exit.
    unawaited(UnreadService.instance.markSeen(widget.receiverId));

    NotificationService.instance.activeChatId = null;
    _presenceSub?.cancel();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    if (messageController.text.trim().isEmpty) {
      return;
    }

    await messageService.sendMessage(
      receiverId: widget.receiverId,
      message: messageController.text.trim(),
    );

    messageController.clear();

    Future.delayed(const Duration(milliseconds: 200), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  PreferredSizeWidget buildAppBar() {
    return AppBar(
      toolbarHeight: 72,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryGradient,
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: UserAvatar(
              imageUrl: widget.receiverAvatar,
              name: widget.receiverName,
              radius: 19,
              showOnlineDot: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.receiverName, overflow: TextOverflow.ellipsis),
                Text(
                  isOnline ? 'Online' : 'Last seen recently',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: isOnline ? const Color(0xFFA7F3D0) : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messageService.getMessages(
                otherUserId: widget.receiverId,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEEEDFB),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.waving_hand_rounded,
                            size: 38,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Say hello 👋',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Break the ice with a friendly message.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Detect a message that arrived from the other user since
                // the previous snapshot so it gets highlighted below.
                String? newIncomingId;
                if (_hasSeenMessages && messages.isNotEmpty) {
                  final lastId = messages.last['id']?.toString();
                  final isFromOther =
                      messages.last['sender_id'] != currentUserId;
                  if (lastId != null &&
                      lastId != _lastSeenMessageId &&
                      isFromOther) {
                    newIncomingId = lastId;
                  }
                  _lastSeenMessageId = lastId;
                }
                _hasSeenMessages = true;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!scrollController.hasClients) return;

                  final target = scrollController.position.maxScrollExtent;

                  if (newIncomingId != null) {
                    // Smoothly follow the newly highlighted message.
                    scrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    scrollController.jumpTo(target);
                  }
                });

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];

                    final isMe = msg['sender_id'] == currentUserId;

                    final time = DateTime.parse(msg['created_at']);

                    final formattedTime =
                        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

                    final messageId = msg['id']?.toString();

                    return MessageBubble(
                      key: ValueKey<String>(messageId ?? 'msg-$index'),
                      message: msg,
                      isMe: isMe,
                      timeText: formattedTime,
                      isNewIncoming:
                          messageId != null && messageId == newIncomingId,
                    );
                  },
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => sendMessage(),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppColors.primaryGradient,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: sendMessage,
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
