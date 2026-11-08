import 'package:flutter/material.dart';
import 'package:portpotato/hugging_face.dart';
import 'package:portpotato/local_inference.dart';

class ModelDownloadsPage extends StatefulWidget {
  const ModelDownloadsPage({super.key, required this.inference, this.api});

  final LocalInference inference;
  final HuggingFaceApi? api;

  @override
  State<ModelDownloadsPage> createState() => _ModelDownloadsPageState();
}

class _ModelDownloadsPageState extends State<ModelDownloadsPage> {
  final _query = TextEditingController();
  late final HuggingFaceApi _api = widget.api ?? HuggingFaceApi();
  List<HubRepository> _results = [];
  List<HubVariant> _variants = [];
  List<DownloadedModel> _downloaded = [];
  HubRepository? _expanded;
  HubDownloader? _downloader;
  String? _error;
  bool _searching = false;
  bool _searched = false;
  bool _loadingVariants = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  @override
  void dispose() {
    _downloader?.cancel();
    if (widget.api == null) _api.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadDownloads() async {
    try {
      final models = await ModelDownloads(widget.inference).list();
      if (mounted) setState(() => _downloaded = models);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not read downloaded models: $error');
      }
    }
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.isEmpty || _searching || _downloader != null) return;
    setState(() {
      _searching = true;
      _searched = true;
      _error = null;
      _results = [];
      _variants = [];
      _expanded = null;
    });
    try {
      final results = await _api.search(text);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = 'Search failed: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _expand(HubRepository repository) async {
    if (_expanded?.id == repository.id) {
      setState(() {
        _expanded = null;
        _variants = [];
      });
      return;
    }
    setState(() {
      _expanded = repository;
      _variants = [];
      _loadingVariants = true;
      _error = null;
    });
    try {
      final variants = await _api.variants(repository);
      if (mounted && _expanded?.id == repository.id) {
        setState(() => _variants = variants);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not read model files: $error');
      }
    } finally {
      if (mounted && _expanded?.id == repository.id) {
        setState(() => _loadingVariants = false);
      }
    }
  }

  Future<void> _download(HubVariant variant) async {
    final downloader = HubDownloader(endpoint: _api.endpoint);
    setState(() {
      _downloader = downloader;
      _progress = null;
      _error = null;
    });
    try {
      final directory = await widget.inference.modelsDirectory;
      await downloader.download(
        variant,
        directory,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      await _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Model downloaded')));
      }
    } on DownloadCancelled {
      if (mounted) setState(() => _error = 'Download cancelled');
    } catch (error) {
      if (mounted) setState(() => _error = 'Download failed: $error');
    } finally {
      downloader.close();
      if (mounted) {
        setState(() {
          _downloader = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _confirmDownload(HubVariant variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download model?'),
        content: Text(
          '${variant.repository.id}\n${variant.label}\n${_size(variant.totalSize)}'
          '${variant.vision ? '\nIncludes vision projector' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && _downloader == null) {
      await _download(variant);
    }
  }

  String _size(int? bytes) {
    if (bytes == null) return 'Size unknown';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Model downloads')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search Hugging Face models',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Search models',
                  onPressed: _searching || _downloader != null ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          if (_downloader != null) ...[
            LinearProgressIndicator(value: _progress),
            TextButton(
              onPressed: _downloader!.cancel,
              child: const Text('Cancel download'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (_downloaded.isNotEmpty) ...[
                  const ListTile(title: Text('Downloaded')),
                  for (final model in _downloaded)
                    ListTile(
                      leading: Icon(
                        model.vision
                            ? Icons.visibility_outlined
                            : Icons.memory_outlined,
                      ),
                      title: Text(
                        model.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: model.vision
                          ? const Text(
                              'Vision package · image chat unavailable',
                            )
                          : null,
                      trailing: model.vision
                          ? null
                          : TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, model.chatModel),
                              child: const Text('Use'),
                            ),
                    ),
                  const Divider(),
                ],
                if (_searching)
                  const Center(child: CircularProgressIndicator()),
                if (!_searching && _results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _searched
                          ? 'No public GGUF models found.'
                          : 'Enter a model name and tap the search icon.',
                    ),
                  ),
                for (final repository in _results) ...[
                  ListTile(
                    title: Text(
                      repository.id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: repository.gated
                        ? const Text('Requires Hugging Face access')
                        : null,
                    trailing: Icon(
                      repository.gated ? Icons.lock_outline : Icons.expand_more,
                    ),
                    onTap: repository.gated || _downloader != null
                        ? null
                        : () => _expand(repository),
                  ),
                  if (_expanded?.id == repository.id)
                    if (_loadingVariants)
                      const Center(child: CircularProgressIndicator())
                    else if (_variants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No GGUF files found in this repository'),
                      )
                    else
                      for (final variant in _variants)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 32,
                            right: 16,
                          ),
                          title: Text(
                            variant.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            variant.isSplit
                                ? 'Split GGUF is not supported'
                                : variant.vision && variant.projector == null
                                ? 'Matching vision projector unavailable'
                                : '${_size(variant.totalSize)}${variant.vision ? ' · includes vision projector' : ''}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Download ${variant.label}',
                            onPressed:
                                variant.canDownload && _downloader == null
                                ? () => _confirmDownload(variant)
                                : null,
                            icon: const Icon(Icons.download_outlined),
                          ),
                        ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
