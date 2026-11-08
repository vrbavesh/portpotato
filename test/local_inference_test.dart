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
}
