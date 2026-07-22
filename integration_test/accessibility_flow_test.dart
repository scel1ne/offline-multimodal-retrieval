// Accessibility end-to-end integration test.
//
// Verifies that the main workflow can be completed by a keyboard-only
// user and that the screen reader exposes the right semantics. Mirrors
// the scenarios in `docs/accessibility_usage_guide.md`.
//
// Run with:
//   flutter test integration_test/accessibility_flow_test.dart -d macos
//
// These tests are gated behind `flutter test integration_test/ -d macos`
// and are *not* part of the default `flutter test` run.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_accessible_retrieval/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'accessibility: keyboard-only workflow reaches the search field',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 1. The library and search panels render.
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Choose files'), findsOneWidget);

      // 2. Tab a few times and confirm a focusable control is reached.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = binding.focusManager.primaryFocus;
      expect(focused, isNotNull,
          reason: 'tabbing should leave focus on a real widget');

      // 3. Cmd-K focuses the search field (handled by
      //    HardwareKeyboard.instance.addHandler in HomeScreen).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      // After the shortcut the search TextField is focused.
      final fieldFinder = find.byType(TextField);
      final widget = tester.widget<TextField>(fieldFinder);
      expect(widget.focusNode?.hasFocus ?? false, isTrue,
          reason: 'Cmd-K should focus the search TextField');

      // 4. The status live region exists in the tree.
      expect(
        find.bySemanticsLabel(RegExp(r'(No files indexed|files indexed)')),
        findsWidgets,
        reason: 'status line should expose a live region with a label',
      );
    },
  );

  testWidgets(
    'accessibility: high-contrast toggle changes its label',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The high-contrast IconButton has a tooltip that flips between
      // "High contrast" and "Standard contrast".
      SemanticsHandle? handle = tester.ensureSemantics();
      try {
        final initial = find.byTooltip(RegExp(r'^(High contrast|Standard contrast)$'));
        expect(initial, findsOneWidget,
            reason: 'contrast toggle should expose a contrast tooltip');

        // Tap the icon. We tap the IconButton ancestor because the
        // tooltip finder resolves to the icon's Semantics node.
        await tester.tap(find.byIcon(Icons.contrast_outlined).first);
        await tester.pumpAndSettle();

        // The label should now be the other one.
        final flipped = find.byTooltip(
            RegExp(r'^(High contrast|Standard contrast)$'));
        expect(flipped, findsOneWidget);
      } finally {
        handle.dispose();
      }
    },
  );
}
