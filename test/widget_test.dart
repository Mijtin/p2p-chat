import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const P2PChatApp());

    // Verify that the app title is present
    expect(find.text('P2P Chat'), findsOneWidget);
  });
}
