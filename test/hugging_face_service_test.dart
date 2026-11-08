import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portpotato/hugging_face.dart';

void main() {
  test('search includes related GGUF repositories', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final terms = <String>[];
    server.listen((request) async {
      terms.add(request.uri.queryParameters['search']!);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {'id': 'Qwen/Qwen2.5-GGUF', 'sha': 'a' * 40, 'gated': false},
          if (terms.length == 2)
            {'id': 'bartowski/Qwen2.5-GGUF', 'sha': 'b' * 40, 'gated': false},
        ]),
      );
      await request.response.close();
    });
    final api = HuggingFaceApi(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    addTearDown(api.close);
    final repos = await api.search('Qwen/Qwen2.5-GGUF');
    expect(terms, ['Qwen/Qwen2.5-GGUF', 'Qwen2.5']);
    expect(repos.map((repo) => repo.id), [
      'Qwen/Qwen2.5-GGUF',
      'bartowski/Qwen2.5-GGUF',
    ]);
  });

  test('repository details pair a vision GGUF with its projector', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final sha = 'a' * 40;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'team/vision-GGUF',
          'sha': sha,
          'gated': false,
          'pipeline_tag': 'image-text-to-text',
          'siblings': [
            {'rfilename': 'vision-q4.gguf', 'size': 3},
            {'rfilename': 'mmproj-f16.gguf', 'size': 2},
            {'rfilename': 'vision-q4-00001-of-00002.gguf', 'size': 3},
          ],
        }),
      );
      await request.response.close();
    });
    final api = HuggingFaceApi(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    addTearDown(api.close);
    final variants = await api.variants(
      HubRepository(
        id: 'team/vision-GGUF',
        revision: sha,
        gated: false,
        pipelineTag: 'image-text-to-text',
      ),
    );
    expect(variants, hasLength(2));
    expect(variants.first.projector?.path, 'mmproj-f16.gguf');
    expect(variants.first.canDownload, isTrue);
    expect(variants.last.canDownload, isFalse);
  });

  test(
    'download verifies both vision files before publishing a package',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'portpotato-model-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final mainBytes = utf8.encode('GGUF model fixture');
      final projectorBytes = utf8.encode('GGUF projector fixture');
      server.listen((request) async {
        final bytes = request.uri.path.endsWith('mmproj.gguf')
            ? projectorBytes
            : mainBytes;
        request.response.add(bytes);
        await request.response.close();
      });
      final revision = 'b' * 40;
      final repository = HubRepository(
        id: 'team/model-GGUF',
        revision: revision,
        gated: false,
        pipelineTag: 'image-text-to-text',
      );
      final variant = HubVariant(
        repository,
        HubFile(
          'model-q4.gguf',
          mainBytes.length,
          sha256.convert(mainBytes).toString(),
        ),
        HubFile(
          'mmproj.gguf',
          projectorBytes.length,
          sha256.convert(projectorBytes).toString(),
        ),
        true,
      );
      final downloader = HubDownloader(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final model = await downloader.download(variant, directory.path);
      expect(await File(model.path).readAsBytes(), mainBytes);
      expect(model.vision, isTrue);
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.package.json')),
        hasLength(1),
      );
      downloader.cancel();

      final bad = HubVariant(
        repository,
        HubFile('bad.gguf', mainBytes.length, '0' * 64),
        null,
        false,
      );
      final badDownloader = HubDownloader(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      await expectLater(
        badDownloader.download(bad, directory.path),
        throwsA(isA<FormatException>()),
      );
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
      badDownloader.cancel();
    },
  );
}
