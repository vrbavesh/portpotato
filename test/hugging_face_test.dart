import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portpotato/hugging_face.dart';
import 'package:portpotato/local_inference.dart';
import 'package:portpotato/model_downloads_page.dart';

class _FakeApi extends HuggingFaceApi {
  int searches = 0;

  @override
  Future<List<HubRepository>> search(String text) async {
    searches++;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing does not search until Search is tapped', (tester) async {
    final directory = Directory.systemTemp.createTempSync('portpotato-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('portpotato/inference');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'modelsDirectory') return directory.path;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ModelDownloadsPage(inference: LocalInference(), api: api),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Qwen');
    await tester.pump();
    expect(api.searches, 0);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(api.searches, 1);
    api.close();
  });
}
