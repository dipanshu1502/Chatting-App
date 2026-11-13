import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// A circular avatar that shows the user's profile photo, or a gradient
/// placeholder with their initial when no photo is available.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 24,
    this.showOnlineDot = false,
    this.dotBorderColor = Colors.white,
  });

  final String? imageUrl;
  final String name;
  final double radius;
  final bool showOnlineDot;
  final Color dotBorderColor;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = ClipOval(child: _buildImage());

    if (!showOnlineDot) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.5,
            height: radius * 0.5,
            decoration: BoxDecoration(
              color: AppColors.online,
              shape: BoxShape.circle,
              border: Border.all(color: dotBorderColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage() {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    if (!hasImage) {
      return _buildInitialAvatar();
    }

    return Image.network(
      imageUrl!,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;

        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildInitialAvatar(),
    );
  }

  Widget _buildInitialAvatar() {
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';

    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.primaryGradient,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}