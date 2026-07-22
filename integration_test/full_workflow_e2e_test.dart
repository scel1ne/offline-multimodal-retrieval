// Full end-to-end integration test for the offline retrieval app.
//
// Exercises the real user workflow against the real Flutter widgets on a
// macOS desktop runner. The file picker plugin's MethodChannel is mocked
// at the test binding so the test stays hermetic and does not require a
// real NSOpenPanel / NSSavePanel interaction.
//
// Run with:
//   flutter test integration_test/full_workflow_e2e_test.dart -d macos
//
// These tests are gated behind `flutter test integration_test/ -d macos`
// and are *not* part of the default `flutter test` run (which only picks
// up files under `test/`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_accessible_retrieval/main.dart' as app;

/// MethodChannel name for the macOS `file_picker` plugin.
const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _MockFilePickerHandler.instance.install();
  });

  tearDown(() {
    _MockFilePickerHandler.instance.uninstall();
  });

  testWidgets(
    'E2E: pick files -> search -> filter -> export -> clear -> import',
    (tester) async {
      // 1. Write three fixture files to a temp directory. We point the
      //    mocked file picker at these absolute paths.
      final tmp = await Directory.systemTemp.createTemp('celine_e2e_');
      final notes = File('${tmp.path}/notes.txt')
        ..writeAsStringSync(
          'offline notes about accessibility and semantic search',
        );
      final acc = File('${tmp.path}/accessibility.md')
        ..writeAsStringSync(
          '# Accessibility\nThis file covers WCAG 2.1 AA and screen readers.',
        );
      final csv = File('${tmp.path}/people.csv')
        ..writeAsStringSync('name,role\nAlice,engineer\nBob,designer\n');

      // 2. Configure the picker mock with the three file paths. The
      //    macOS channel returns `List<String>?` (absolute paths) for
      //    `pickFiles` and `String?` for `saveFile`.
      _MockFilePickerHandler.instance
        ..nextPickPaths = [notes.path, acc.path, csv.path]
        ..nextSavePath = null;

      // 3. Boot the app.
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 4. Library is empty initially.
      expect(find.text('No files indexed yet.'), findsOneWidget);

      // 5. Tap "Choose files" - the mock returns the three paths.
      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 6. The status line announces the new library size. The actual
      //    message format is "<n> files indexed. Library has <m> files.".
      expect(
        find.textContaining('3 files indexed'),
        findsOneWidget,
        reason: 'status line should announce the 3 newly indexed files',
      );

      // 7. Search for "accessibility". The query box is the only
      //    TextField on the screen.
      final queryField = find.byType(TextField);
      expect(queryField, findsOneWidget);
      await tester.enterText(queryField, 'accessibility');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle(const Duration(milliseconds: 800));

      // 8. The accessibility.md file should be in the result list.
      expect(
        find.text('accessibility.md'),
        findsWidgets,
        reason: 'accessibility.md should match the query and be listed',
      );

      // 9. Filter to "text" via the SegmentedButton<IndexedKind>.
      final textSegment = find.text('text');
      expect(textSegment, findsWidgets);
      await tester.tap(textSegment.first);
      await tester.pumpAndSettle();

      // 10. accessibility.md is a text file and should still be visible.
      expect(
        find.text('accessibility.md'),
        findsWidgets,
        reason: 'text filter should keep accessibility.md visible',
      );

      // 11. Export the index. The saveFile mock returns a known path
      //     so the export actually writes to disk and can be read back.
      final exportFile = File('${tmp.path}/export.json');
      _MockFilePickerHandler.instance.nextSavePath = exportFile.path;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(exportFile.existsSync(), isTrue,
          reason: 'export file should exist on disk');
      final exported = jsonDecode(await exportFile.readAsString())
          as Map<String, Object?>;
      expect(exported['version'], 1);
      final records = (exported['records'] as List).cast<Map>();
      expect(records, hasLength(3),
          reason: 'export should contain all 3 indexed files');

      // 12. Clear the library.
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(find.text('No files indexed yet.'), findsOneWidget);

      // 13. Import the previously exported JSON.
      _MockFilePickerHandler.instance
        ..nextPickPaths = [exportFile.path]
        ..nextSavePath = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.textContaining('3 records imported'),
        findsOneWidget,
        reason: 'status line should announce the import count',
      );

      // 14. Sanity-check the re-imported index: search for "semantic"
      //     which only appears in notes.txt.
      await tester.enterText(queryField, 'semantic');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      expect(
        find.text('notes.txt'),
        findsWidgets,
        reason: 'notes.txt should match "semantic" after re-import',
      );

      // 15. Cleanup.
      await tmp.delete(recursive: true);
    },
  );

  testWidgets(
    'E2E: cancel on the file picker is a no-op',
    (tester) async {
      // Configure the picker to return an empty list (NSOpenPanel
      // dismissed with no selection).
      _MockFilePickerHandler.instance
        ..nextPickPaths = const <String>[]
        ..nextSavePath = null;

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Library is still empty and no error status is shown.
      expect(find.text('No files indexed yet.'), findsOneWidget);
    },
  );
}

/// Singleton handler for the file_picker MethodChannel. We keep this
/// at top-level so it can be installed once and shared across tests in
/// the suite. The binding is captured in [install] and used to register
/// a mock handler on the default binary messenger.
class _MockFilePickerHandler {
  _MockFilePickerHandler._();
  static final _MockFilePickerHandler instance = _MockFilePickerHandler._();

  IntegrationTestWidgetsFlutterBinding? _binding;
  List<String>? nextPickPaths;
  String? nextSavePath;

  void install() {
    if (_binding != null) return;
    _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    _binding!.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, _handle);
  }

  void uninstall() {
    _binding?.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, null);
    _binding = null;
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'pickFiles':
        // The macOS plugin returns a `List<String>?` of absolute paths.
        // Returning an empty list (not null) is the "user picked nothing
        // and confirmed" path; null would be the "cancel" path.
        return nextPickPaths;
      case 'saveFile':
        return nextSavePath;
      case 'getDirectoryPath':
        return null;
      case 'openFile':
        return null;
      default:
        return null;
    }
  }
}
