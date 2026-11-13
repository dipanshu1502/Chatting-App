import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// A single chat message bubble.
///
/// When [isNewIncoming] is true the bubble plays a one-shot "new message"
/// animation on first build: a soft glowing border that fades out plus a
/// small pop-in scale, so freshly received messages stand out while the
/// chat is open.
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.timeText,
    this.isNewIncoming = false,
  });

  final Map<String, dynamic> message;

  final bool isMe;

  /// Pre-formatted "HH:mm" timestamp shown in the bubble footer.
  final String timeText;

  /// Marks the bubble that has just arrived from the other user.
  final bool isNewIncoming;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// Whether the one-shot highlight animation is running. Copied into state
  /// so the animation keeps running even when a later stream snapshot stops
  /// flagging this bubble as new.
  bool _playingHighlight = false;

  @override
  void initState() {
    super.initState();

    // Bubbles are keyed by message id, so initState only runs the first
    // time a message appears in the list.
    _playingHighlight = widget.isNewIncoming;
  }

  @override
  Widget build(BuildContext context) {
    Widget bubble = _buildBubble();

    if (_playingHighlight) {
      bubble = _buildGlow(bubble);
      bubble = _buildPopIn(bubble);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  /// Small pop-in scale so the bubble doesn't just abruptly appear.
  Widget _buildPopIn(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          alignment: widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Glowing border around the bubble that fades out and removes itself
  /// once finished.
  Widget _buildGlow(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeOut,
      onEnd: () {
        if (mounted) {
          setState(() => _playingHighlight = false);
        }
      },
      builder: (context, t, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _bubbleRadius,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.8 * t),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.40 * t),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  BorderRadius get _bubbleRadius =>
      BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(widget.isMe ? 18 : 5),
        bottomRight: Radius.circular(widget.isMe ? 5 : 18),
      );

  Widget _buildBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        gradient: widget.isMe
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.primaryGradient,
              )
            : null,
        color: widget.isMe ? null : AppColors.surface,
        borderRadius: _bubbleRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.message['message']?.toString() ?? '',
            style: TextStyle(
              color: widget.isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 15.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.timeText,
                style: TextStyle(
                  color:
                      widget.isMe ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.done_all_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}