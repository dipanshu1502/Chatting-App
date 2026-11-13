import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/presence_service.dart';
import '../../services/unread_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/user_avatar.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserService userService = UserService();
  final PresenceService presenceService = PresenceService.instance;
  final UnreadService unreadService = UnreadService.instance;

  final currentUserId = Supabase.instance.client.auth.currentUser!.id;

  Map<String, dynamic>? currentUserProfile;
  bool isUploading = false;
  String searchQuery = '';

  // Chat list state. Kept as fields so unread-highlight updates can refresh
  // silently without flashing the loading spinner.
  List<Map<String, dynamic>>? _users;
  bool _loadingUsers = true;
  Object? _usersError;

  Set<String> onlineUserIds = {};
  StreamSubscription<Set<String>>? _presenceSub;

  @override
  void initState() {
    super.initState();
    loadProfile();
    _loadUsers();

    // Seed with any presence already synced, then keep listening for changes.
    onlineUserIds = presenceService.onlineUserIds;
    _presenceSub = presenceService.onlineUsersStream.listen((ids) {
      if (!mounted) return;
      setState(() => onlineUserIds = ids);
    });

    // Refresh unread highlights when a message arrives or a chat is seen.
    unreadService.addListener(_onUnreadChanged);
  }

  @override
  void dispose() {
    unreadService.removeListener(_onUnreadChanged);
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final result = await userService.getUsers();

      if (!mounted) return;

      setState(() {
        _users = result;
        _usersError = null;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _usersError = e;
        _loadingUsers = false;
      });
    }
  }

  void _onUnreadChanged() {
    if (!mounted) return;

    // Recompute highlights from cached data immediately, then refetch quietly
    // so brand-new messages also show up (no spinner flash).
    setState(() {});
    _loadUsers();
  }

  Future<void> loadProfile() async {
    final profile = await userService.getCurrentUserProfile();

    if (!mounted) return;

    setState(() {
      currentUserProfile = profile;
    });
  }

  Future<void> pickAndUploadImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) return;

      setState(() {
        isUploading = true;
      });

      Uint8List bytes = await image.readAsBytes();

      await userService.uploadProfileImage(bytes);

      await loadProfile();

      if (!mounted) return;

      showAppSnackBar(context, 'Profile photo updated');
    } catch (e) {
      if (!mounted) return;

      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
        });
      }
    }
  }

  Future<void> logout() async {
    await AuthService().logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget buildCurrentUserAvatar() {
    final avatarUrl = currentUserProfile?['avatar_url'];
    final name = currentUserProfile?['name'] ?? 'U';

    // White ring keeps the avatar readable on the gradient header.
    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: UserAvatar(
        imageUrl: avatarUrl?.toString(),
        name: name.toString(),
        radius: 22,
      ),
    );

    if (isUploading) {
      return Stack(
        alignment: Alignment.center,
        children: [
          avatar,
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Small camera badge makes it obvious the avatar is tappable.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 1.5),
            ),
            child: const Icon(
              Icons.photo_camera_rounded,
              size: 10,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// Generic icon + title + subtitle block for empty / error states.
  Widget buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
            child: Icon(icon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gradient dashboard header: profile, greeting, logout and search.
  Widget buildHeader() {
    final name = currentUserProfile?['name']?.toString() ?? 'there';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.primaryGradient,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: pickAndUploadImage,
                    child: buildCurrentUserAvatar(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hi, $name 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _circleIconButton(
                    icon: Icons.logout_rounded,
                    tooltip: 'Log out',
                    onTap: logout,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              buildSearchField(),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _circleIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          hintText: 'Search users...',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
          ),
          suffixIcon: searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setState(() => searchQuery = ''),
                ),
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          buildHeader(),
          Expanded(child: buildUserList()),
        ],
      ),
    );
  }

  /// Builds the chat list. Chats with unseen incoming messages stay
  /// highlighted until their conversation is opened (message seen).
  Widget buildUserList() {
    if (_loadingUsers && _users == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (_usersError != null) {
      return buildMessageState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        subtitle: _usersError.toString(),
      );
    }

    final users = _users ?? [];

    final filteredUsers = users.where((user) {
      final name = user['name'].toString().toLowerCase();

      return name.contains(searchQuery.toLowerCase());
    }).toList();

    if (filteredUsers.isEmpty) {
      return buildMessageState(
        icon: searchQuery.isEmpty
            ? Icons.people_outline_rounded
            : Icons.search_off_rounded,
        title: searchQuery.isEmpty ? 'No users yet' : 'No users found',
        subtitle: searchQuery.isEmpty
            ? 'Invite your friends to start chatting.'
            : 'Try a different name.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        itemCount: filteredUsers.length,
        itemBuilder: (context, index) {
          final user = filteredUsers[index];

          // Online status comes from realtime presence, not the
          // stale DB flag.
          final isOnline = onlineUserIds.contains(user['id'].toString());
          final lastTime = user['last_time']?.toString() ?? '';

          // Highlighted until the chat is opened (message seen).
          final hasUnread = unreadService.isChatUnread(
            chatUserId: user['id'].toString(),
            currentUserId: currentUserId,
            lastSenderId: user['last_sender_id']?.toString(),
            lastCreatedAt: user['last_created_at']?.toString(),
          );

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: hasUnread
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: hasUnread
                  ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
                  : null,
              boxShadow: AppTheme.cardShadow,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        receiverId: user['id'],
                        receiverName: user['name'],
                        receiverAvatar: user['avatar_url'],
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        imageUrl: user['avatar_url']?.toString(),
                        name: user['name'].toString(),
                        radius: 26,
                        showOnlineDot: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: hasUnread
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user['last_message'] ?? 'Start chatting',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: hasUnread
                                    ? AppColors.textPrimary
                                    : isOnline
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      if (lastTime.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          lastTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
