import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portpotato/local_inference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing native reply is reported as an error', () async {
    const channel = MethodChannel('portpotato/inference');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await expectLater(LocalInference().generate('Hello'), throwsStateError);
  });

  test(
    'downloaded files use the app model path, imports use document URIs',
    () async {
      const channel = MethodChannel('portpotato/inference');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final inference = LocalInference();
      await inference.loadSelectedModel(
        const ImportedModel(uri: '/app/models/q4.gguf', name: 'q4.gguf'),
      );
      await inference.loadSelectedModel(
        const ImportedModel(
          uri: 'content://downloads/q4.gguf',
          name: 'q4.gguf',
        ),
      );

      expect(calls.map((call) => call.method), ['loadModel', 'loadDocument']);
      expect(calls.first.arguments, {'path': '/app/models/q4.gguf'});
    },
  );
}
