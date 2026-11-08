import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:portpotato/local_inference.dart';

class HubRepository {
  const HubRepository({
    required this.id,
    required this.revision,
    required this.gated,
    required this.pipelineTag,
  });

  final String id;
  final String revision;
  final bool gated;
  final String? pipelineTag;

  factory HubRepository.fromJson(Map<String, dynamic> value) => HubRepository(
    id: value['id'] as String,
    revision: value['sha'] as String? ?? '',
    gated: value['gated'] != null && value['gated'] != false,
    pipelineTag: value['pipeline_tag'] as String?,
  );
}

class HubFile {
  const HubFile(this.path, this.size, this.sha256);

  final String path;
  final int? size;
  final String? sha256;

  factory HubFile.fromJson(Map<String, dynamic> value) {
    final lfs = value['lfs'];
    return HubFile(
      value['rfilename'] as String,
      value['size'] as int?,
      lfs is Map ? lfs['sha256'] as String? : null,
    );
  }
}

class HubVariant {
  const HubVariant(this.repository, this.model, this.projector, this.vision);

  final HubRepository repository;
  final HubFile model;
  final HubFile? projector;
  final bool vision;

  bool get isSplit => RegExp(
    r'-\d{5}-of-\d{5}\.gguf$',
    caseSensitive: false,
  ).hasMatch(model.path);
  bool get canDownload =>
      !isSplit &&
      model.size != null &&
      model.size! > 0 &&
      (!vision || (projector?.size != null && projector!.size! > 0));
  String get label => model.path.split('/').last;
  int? get totalSize =>
      model.size == null || (projector != null && projector!.size == null)
      ? null
      : model.size! + (projector?.size ?? 0);
}

class HuggingFaceApi {
  HuggingFaceApi({Uri? endpoint, HttpClient? client})
    : endpoint = endpoint ?? Uri.https('huggingface.co', '/'),
      _client = client ?? HttpClient();

  final Uri endpoint;
  final HttpClient _client;

  Future<dynamic> _get(String path, [Map<String, String>? parameters]) async {
    final uri = endpoint.replace(path: path, queryParameters: parameters);
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Hugging Face returned ${response.statusCode}',
        uri: uri,
      );
    }
    if (response.contentLength > 10 * 1024 * 1024) {
      throw const FormatException('Model list is too large');
    }
    return jsonDecode(await utf8.decoder.bind(response).join());
  }

  Future<List<HubRepository>> search(String text) async {
    final query = text.trim();
    if (query.isEmpty) return [];
    final baseName = query
        .split('/')
        .last
        .replaceFirst(RegExp(r'[-_]gguf$', caseSensitive: false), '');
    final terms = <String>{query, baseName};
    final found = <String, HubRepository>{};
    for (final term in terms) {
      final items = await _get('/api/models', {
        'search': term,
        'filter': 'gguf',
        'sort': 'downloads',
        'direction': '-1',
        'limit': '100',
      }) as List<dynamic>;
      for (final item in items) {
        final repo = HubRepository.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        found[repo.id] = repo;
      }
    }
    return found.values.toList();
  }

  Future<List<HubVariant>> variants(HubRepository repository) async {
    final parts = repository.id.split('/');
    if (parts.length != 2 ||
        parts.any((part) => !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part))) {
      throw const FormatException('Invalid model repository');
    }
    final detail = Map<String, dynamic>.from(
      await _get('/api/models/${parts[0]}/${parts[1]}', {'blobs': 'true'})
          as Map,
    );
    final current = HubRepository.fromJson(detail);
    final files = (detail['siblings'] as List<dynamic>? ?? [])
        .map((item) => HubFile.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((file) => file.path.toLowerCase().endsWith('.gguf'))
        .toList();
    final projectors = files.where((file) => _isProjector(file.path)).toList();
    final vision =
        projectors.isNotEmpty ||
        (current.pipelineTag?.contains('image') ?? false) ||
        (current.pipelineTag?.contains('video') ?? false);
    return [
      for (final file in files.where((file) => !_isProjector(file.path)))
        HubVariant(current, file, _projectorFor(file, projectors), vision),
    ];
  }

  static bool _isProjector(String path) => RegExp(
    r'(^|[/_.-])(mmproj|projector)([/_.-]|$)',
    caseSensitive: false,
  ).hasMatch(path);

  static HubFile? _projectorFor(HubFile model, List<HubFile> projectors) {
    if (projectors.length == 1) return projectors.single;
    final folder = model.path.contains('/')
        ? model.path.substring(0, model.path.lastIndexOf('/'))
        : '';
    final nearby = projectors.where((file) {
      final parent = file.path.contains('/')
          ? file.path.substring(0, file.path.lastIndexOf('/'))
          : '';
      return parent == folder;
    }).toList();
    return nearby.length == 1 ? nearby.single : null;
  }

  void close() => _client.close(force: true);
}

class DownloadedModel {
  const DownloadedModel({
    required this.name,
    required this.path,
    required this.vision,
  });

  final String name;
  final String path;
  final bool vision;

  ImportedModel get chatModel => ImportedModel(uri: path, name: name);
}

class ModelDownloads {
  ModelDownloads(this.inference);

  final LocalInference inference;

  Future<List<DownloadedModel>> list() async {
    final root = Directory(await inference.modelsDirectory);
    if (!await root.exists()) return [];
    final models = <DownloadedModel>[];
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.package.json')) continue;
      try {
        final info = Map<String, dynamic>.from(
          jsonDecode(await entry.readAsString()) as Map,
        );
        final file = info['main'] as String;
        if (file.contains('/') ||
            file.contains('\\') ||
            file == '.' ||
            file == '..') {
          continue;
        }
        final model = File(
          '${entry.parent.path}${Platform.pathSeparator}$file',
        );
        if (!await model.exists()) continue;
        final vision = info['vision'] == true;
        final projector = info['projector'] as String?;
        if (vision &&
            (projector == null ||
                projector.contains('/') ||
                projector.contains('\\') ||
                projector == '.' ||
                projector == '..' ||
                !await File(
                  '${entry.parent.path}${Platform.pathSeparator}$projector',
                ).exists())) {
          continue;
        }
        models.add(
          DownloadedModel(
            name: '${info['repo']} · ${info['label']}',
            path: model.path,
            vision: vision,
          ),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return models;
  }
}

class DownloadCancelled implements Exception {}

class HubDownloader {
  HubDownloader({Uri? endpoint, HttpClient? client})
    : endpoint = endpoint ?? Uri.https('huggingface.co', '/'),
      _client = client ?? HttpClient();

  final Uri endpoint;
  final HttpClient _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  void close() => _client.close(force: true);

  Future<DownloadedModel> download(
    HubVariant variant,
    String modelsDirectory, {
    void Function(double?)? onProgress,
  }) async {
    if (!variant.canDownload) {
      throw StateError('This GGUF package is not supported');
    }
    final revision = variant.repository.revision;
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision)) {
      throw const FormatException('Model revision is unavailable');
    }
    final slug = variant.repository.id.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final folder = Directory(
      '$modelsDirectory${Platform.pathSeparator}hf-${slug.length > 80 ? slug.substring(0, 80) : slug}-${revision.substring(0, 12)}',
    );
    await folder.create(recursive: true);
    final files = [
      variant.model,
      if (variant.projector != null) variant.projector!,
    ];
    final total = variant.totalSize;
    var completed = 0;
    final downloaded = <String, String>{};
    for (final file in files) {
      final localName = _localName(file.path);
      final destination = File(
        '${folder.path}${Platform.pathSeparator}$localName',
      );
      await _downloadFile(variant.repository, file, destination, (bytes) {
        onProgress?.call(
          total == null || total == 0 ? null : (completed + bytes) / total,
        );
      });
      completed += file.size ?? await destination.length();
      downloaded[file.path] = localName;
    }
    if (_cancelled) throw DownloadCancelled();
    final manifest = File(
      '${folder.path}${Platform.pathSeparator}${_localName(variant.model.path)}.package.json',
    );
    final temporary = File('${manifest.path}.part');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'repo': variant.repository.id,
          'revision': revision,
          'label': variant.label,
          'main': downloaded[variant.model.path],
          'projector': variant.projector == null
              ? null
              : downloaded[variant.projector!.path],
          'vision': variant.vision,
        }),
        flush: true,
      );
      if (_cancelled) throw DownloadCancelled();
      await temporary.rename(manifest.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    onProgress?.call(1);
    return DownloadedModel(
      name: '${variant.repository.id} · ${variant.label}',
      path:
          '${folder.path}${Platform.pathSeparator}${downloaded[variant.model.path]}',
      vision: variant.vision,
    );
  }

  Future<void> _downloadFile(
    HubRepository repository,
    HubFile file,
    File destination,
    void Function(int) onBytes,
  ) async {
    final segments = file.path.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains('\\'),
    )) {
      throw const FormatException('Invalid model filename');
    }
    if (await destination.exists()) {
      if (await _valid(destination, file)) {
        onBytes(file.size ?? await destination.length());
        return;
      }
      throw StateError('Existing model file is damaged: ${destination.path}');
    }
    final url = endpoint.replace(
      pathSegments: [
        ...repository.id.split('/'),
        'resolve',
        repository.revision,
        ...segments,
      ],
    );
    final part = File('${destination.path}.part');
    try {
      if (_cancelled) throw DownloadCancelled();
      final request = await _client
          .getUrl(url)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Download failed (${response.statusCode})',
          uri: url,
        );
      }
      var bytes = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(minutes: 2),
        )) {
          if (_cancelled) throw DownloadCancelled();
          sink.add(chunk);
          bytes += chunk.length;
          onBytes(bytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (_cancelled) throw DownloadCancelled();
      if (!await _valid(part, file)) {
        throw const FormatException('Model download failed integrity check');
      }
      if (_cancelled) throw DownloadCancelled();
      await part.rename(destination.path);
    } catch (error) {
      if (_cancelled) throw DownloadCancelled();
      rethrow;
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  static Future<bool> _valid(File file, HubFile metadata) async {
    if (metadata.size != null && await file.length() != metadata.size) {
      return false;
    }
    if (metadata.sha256 != null) {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == metadata.sha256!.toLowerCase();
    }
    return await file.length() > 0;
  }

  static String _localName(String path) {
    final base = path
        .split('/')
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final hash = sha256.convert(utf8.encode(path)).toString().substring(0, 12);
    return '$hash-${base.length > 120 ? base.substring(base.length - 120) : base}';
  }
}
