import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portpotato/hugging_face.dart';
import 'package:portpotato/local_inference.dart';
import 'package:portpotato/model_downloads_page.dart';

class _FakeApi extends HuggingFaceApi {
  int searches = 0;
  final repository = const HubRepository(
    id: 'team/model-GGUF',
    revision: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    gated: false,
    pipelineTag: 'text-generation',
  );

  @override
  Future<List<HubRepository>> search(String text) async {
    searches++;
    return [repository];
  }

  @override
  Future<List<HubVariant>> variants(HubRepository repository) async => [
    HubVariant(
      repository,
      const HubFile('model-q4.gguf', 1048576, null),
      null,
      false,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capsule search waits for the icon and download asks first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
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
    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.border! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(28));
    expect(find.text('Search'), findsNothing);
    await tester.tap(find.byTooltip('Search models'));
    await tester.pumpAndSettle();
    expect(api.searches, 1);
    await tester.tap(find.text(api.repository.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Download model-q4.gguf'));
    await tester.pumpAndSettle();
    expect(find.text('Download model?'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel download'), findsNothing);
    api.close();
  });
}
