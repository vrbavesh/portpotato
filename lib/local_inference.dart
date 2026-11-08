import 'package:flutter/services.dart';

class ImportedModel {
  const ImportedModel({required this.uri, required this.name});

  final String uri;
  final String name;

  factory ImportedModel.fromMap(Map<String, String> value) {
    final uri = value['uri'];
    final name = value['name'];
    if (uri == null || name == null) throw StateError('Invalid model document');
    return ImportedModel(uri: uri, name: name);
  }
}

/// Android bridge to the pinned llama.cpp engine and selected GGUF documents.
class LocalInference {
  static const _channel = MethodChannel('portpotato/inference');

  Future<String> get modelsDirectory async {
    final path = await _channel.invokeMethod<String>('modelsDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('Models directory is unavailable');
    }
    return path;
  }

  Future<void> loadModel(String path) =>
      _channel.invokeMethod<void>('loadModel', {'path': path});

  Future<List<ImportedModel>> listImportedModels() async {
    final models = await _channel.invokeListMethod<dynamic>('listModels');
    return (models ?? [])
        .map(
          (value) =>
              ImportedModel.fromMap(Map<String, String>.from(value as Map)),
        )
        .toList();
  }

  Future<ImportedModel?> importModel() async {
    final selected = await _channel.invokeMapMethod<dynamic, dynamic>(
      'importModel',
    );
    return selected == null
        ? null
        : ImportedModel.fromMap(Map<String, String>.from(selected));
  }

  Future<void> loadDocument(ImportedModel model) =>
      _channel.invokeMethod<void>('loadDocument', {'uri': model.uri});

  Future<void> loadSelectedModel(ImportedModel model) =>
      model.uri.startsWith('content://')
      ? loadDocument(model)
      : loadModel(model.uri);

  Future<bool> configure({
    required int contextWindow,
    required double temperature,
    required double topP,
    required double repeatPenalty,
  }) async =>
      await _channel.invokeMethod<bool>('configure', {
        'contextWindow': contextWindow,
        'temperature': temperature,
        'topP': topP,
        'repeatPenalty': repeatPenalty,
      }) ??
      false;

  Future<void> restoreHistory(List<({bool fromUser, String text})> messages) =>
      _channel.invokeMethod<void>('restoreHistory', {
        'messages': [
          for (final message in messages)
            {'fromUser': message.fromUser.toString(), 'text': message.text},
        ],
      });

  Future<String> generate(String prompt, {int maxTokens = 1024}) async {
    final reply = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
    });
    if (reply == null) throw StateError('Native inference returned no reply');
    return reply;
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  Future<void> unloadModel() => _channel.invokeMethod<void>('unloadModel');
}
