import 'package:chattingapp/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(MessageBubble bubble) => MaterialApp(
        home: Scaffold(body: Center(child: bubble)),
      );

  testWidgets('MessageBubble renders message text and time',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      message: {'message': 'Hello there'},
      isMe: false,
      timeText: '09:41',
    )));

    expect(find.text('Hello there'), findsOneWidget);
    expect(find.text('09:41'), findsOneWidget);
  });

  testWidgets('old bubbles do not play the highlight animation',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      message: {'message': 'Old message'},
      isMe: false,
      timeText: '09:40',
    )));

    // No glow/pop-in TweenAnimationBuilders are mounted.
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('new incoming bubble plays the one-shot highlight',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      message: {'message': 'Hi!'},
      isMe: true,
      timeText: '10:00',
      isNewIncoming: true,
    )));

    // Glow + pop-in TweenAnimationBuilders are mounted while animating.
    expect(find.byType(TweenAnimationBuilder<double>), findsNWidgets(2));
    expect(find.text('Hi!'), findsOneWidget);
  });
}
