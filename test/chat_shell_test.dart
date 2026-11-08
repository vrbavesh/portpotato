import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portpotato/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatsChannel = MethodChannel('portpotato/chats');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(chatsChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(chatsChannel, null);
  });
  testWidgets('chat and settings fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(const PortPotatoApp());
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Royal navy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history opens settings and switches the chat theme', (
    tester,
  ) async {
    String? savedTheme;
    const channel = MethodChannel('portpotato/theme');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'write') savedTheme = call.arguments as String;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const PortPotatoApp());

    expect(
      find.text('Pick a model and start chatting with it !!!'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    expect(find.text('No chats yet'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(
      Theme.of(tester.element(find.byWidget(scaffold))).scaffoldBackgroundColor,
      AppColors.white.background,
    );
    expect(savedTheme, 'white');

    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();
    expect(savedTheme, 'black');
    expect(
      Theme.of(tester.element(find.text('Black'))).scaffoldBackgroundColor,
      AppColors.black.background,
    );
  });

  testWidgets('imports an existing GGUF and chats through inference', (
    tester,
  ) async {
    const channel = MethodChannel('portpotato/inference');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'listModels':
          return <Map<String, String>>[
            {'uri': 'content://downloads/older.gguf', 'name': 'older.gguf'},
          ];
        case 'importModel':
          return <String, String>{
            'uri': 'content://downloads/model.gguf',
            'name': 'model.gguf',
          };
        case 'loadDocument':
          expect(call.arguments, {'uri': 'content://downloads/model.gguf'});
          return null;
        case 'generate':
          expect((call.arguments as Map)['prompt'], 'Hello');
          return 'Hi there';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(const PortPotatoApp());
    await tester.tap(find.text('Choose model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import GGUF'));
    await tester.pumpAndSettle();
    expect(find.text('Ready to chat with model.gguf'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();
    final sendButton = find.ancestor(
      of: find.byIcon(Icons.arrow_upward),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(calls, contains('generate'));
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);
    expect(
      calls,
      containsAllInOrder(['importModel', 'loadDocument', 'generate']),
    );
  });

  testWidgets('saved chats reopen and can be deleted', (tester) async {
    String? archive;
    final messenger = tester.binding.defaultBinaryMessenger;
    const chats = MethodChannel('portpotato/chats');
    const inference = MethodChannel('portpotato/inference');
    messenger.setMockMethodCallHandler(chats, (call) async {
      if (call.method == 'read') return archive;
      if (call.method == 'write') archive = call.arguments as String;
      return null;
    });
    messenger.setMockMethodCallHandler(inference, (call) async {
      switch (call.method) {
        case 'listModels':
          return <Map<String, String>>[];
        case 'importModel':
          return {
            'uri': 'content://downloads/model.gguf',
            'name': 'model.gguf',
          };
        case 'configure':
          return false;
        case 'generate':
          return 'Hi there';
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(chats, null);
      messenger.setMockMethodCallHandler(inference, null);
    });

    await tester.pumpWidget(const PortPotatoApp());
    await tester.tap(find.text('Choose model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import GGUF'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(archive, contains('Hi there'));

    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Hi there'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const PortPotatoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    expect(find.text('Hi there'), findsOneWidget);

    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(archive, isNot(contains('Hi there')));
  });

  testWidgets('settings reach the next native reply', (tester) async {
    final calls = <MethodCall>[];
    const inference = MethodChannel('portpotato/inference');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(inference, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'listModels':
          return <Map<String, String>>[];
        case 'importModel':
          return {
            'uri': 'content://downloads/model.gguf',
            'name': 'model.gguf',
          };
        case 'configure':
          return (call.arguments as Map)['contextWindow'] == 2048;
        case 'generate':
          return 'Reply';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        inference,
        null,
      ),
    );

    await tester.pumpWidget(const PortPotatoApp());
    await tester.tap(find.text('Choose model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import GGUF'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4096'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2048').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('256').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    final configured =
        calls.where((call) => call.method == 'configure').last.arguments as Map;
    final generated =
        calls.singleWhere((call) => call.method == 'generate').arguments as Map;
    expect(configured['contextWindow'], 2048);
    expect(generated['maxTokens'], 256);
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(['configure', 'restoreHistory', 'generate']),
    );
  });
}
