import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portpotato/local_inference.dart';
import 'package:portpotato/chat_store.dart';
import 'package:portpotato/hugging_face.dart';
import 'package:portpotato/model_downloads_page.dart';

const _themeChannel = MethodChannel('portpotato/theme');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var initialTheme = AppTheme.royalNavy;
  try {
    final saved = await _themeChannel.invokeMethod<String>('read');
    for (final option in AppTheme.values) {
      if (option.name == saved) initialTheme = option;
    }
  } on PlatformException {
    // The default theme remains available if device storage fails.
  } on MissingPluginException {
    // Widget tests and non-Android hosts use the default theme.
  }
  runApp(PortPotatoApp(initialTheme: initialTheme));
}

enum AppTheme { royalNavy, white, black }

extension AppThemeLabel on AppTheme {
  String get label => switch (this) {
    AppTheme.royalNavy => 'Royal navy',
    AppTheme.white => 'White',
    AppTheme.black => 'Black',
  };
}

class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.outgoing,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color outgoing;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final bool isDark;

  static const navy = AppColors(
    background: Color(0xFF071226),
    surface: Color(0xFF0E1C32),
    raised: Color(0xFF182A44),
    outgoing: Color(0xFF203451),
    border: Color(0xFF30425E),
    text: Color(0xFFF5F7FC),
    muted: Color(0xFFB9C8E1),
    accent: Color(0xFFD8E5FA),
    isDark: true,
  );
  static const white = AppColors(
    background: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF0F0EE),
    outgoing: Color(0xFFE7E7E5),
    border: Color(0xFFD3D3D0),
    text: Color(0xFF171717),
    muted: Color(0xFF545454),
    accent: Color(0xFF171717),
    isDark: false,
  );
  static const black = AppColors(
    background: Color(0xFF080808),
    surface: Color(0xFF171717),
    raised: Color(0xFF222222),
    outgoing: Color(0xFF303030),
    border: Color(0xFF474747),
    text: Color(0xFFF8F8F8),
    muted: Color(0xFFBDBDBD),
    accent: Color(0xFFF8F8F8),
    isDark: true,
  );

  static AppColors forTheme(AppTheme theme) => switch (theme) {
    AppTheme.royalNavy => navy,
    AppTheme.white => white,
    AppTheme.black => black,
  };
}

class PortPotatoApp extends StatefulWidget {
  const PortPotatoApp({super.key, this.initialTheme = AppTheme.royalNavy});

  final AppTheme initialTheme;

  @override
  State<PortPotatoApp> createState() => _PortPotatoAppState();
}

class _PortPotatoAppState extends State<PortPotatoApp> {
  late AppTheme _theme = widget.initialTheme;
  int _contextWindow = 4096;
  double _temperature = 0.7;
  double _topP = 0.95;
  int _maxTokens = 1024;
  double _repeatPenalty = 1.1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final raw = await _themeChannel.invokeMethod<String>('readSettings');
      if (raw == null || !mounted) return;
      final values = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _contextWindow = values['contextWindow'] as int;
        _temperature = (values['temperature'] as num).toDouble();
        _topP = (values['topP'] as num).toDouble();
        _maxTokens = values['maxTokens'] as int;
        _repeatPenalty = (values['repeatPenalty'] as num).toDouble();
      });
    } on Object {
      // Keep safe defaults if saved settings are unavailable or invalid.
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _themeChannel.invokeMethod<void>(
        'writeSettings',
        jsonEncode({
          'contextWindow': _contextWindow,
          'temperature': _temperature,
          'topP': _topP,
          'maxTokens': _maxTokens,
          'repeatPenalty': _repeatPenalty,
        }),
      );
    } on PlatformException {
      // The current session still uses the selected settings.
    } on MissingPluginException {
      // Widget tests have no Android preference store.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.forTheme(_theme);
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
      surface: colors.background,
      onSurface: colors.text,
    );
    return MaterialApp(
      title: 'PortPotato',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: colors.background,
        drawerTheme: DrawerThemeData(backgroundColor: colors.surface),
        cardTheme: CardThemeData(
          color: colors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: colors.background,
          foregroundColor: colors.text,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle:
              (colors.isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                  .copyWith(
                    statusBarColor: colors.background,
                    systemNavigationBarColor: colors.background,
                  ),
        ),
        textTheme: ThemeData(brightness: scheme.brightness).textTheme
            .apply(bodyColor: colors.text, displayColor: colors.text),
      ),
      home: Builder(
        builder: (context) => ChatPage(
          colors: colors,
          contextWindow: _contextWindow,
          temperature: _temperature,
          topP: _topP,
          maxTokens: _maxTokens,
          repeatPenalty: _repeatPenalty,
          onSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StatefulBuilder(
                builder: (context, updatePage) => SettingsPage(
                  colors: AppColors.forTheme(_theme),
                  theme: _theme,
                  contextWindow: _contextWindow,
                  temperature: _temperature,
                  topP: _topP,
                  maxTokens: _maxTokens,
                  repeatPenalty: _repeatPenalty,
                  onThemeChanged: (value) {
                    setState(() => _theme = value);
                    updatePage(() {});
                    unawaited(_saveTheme(value));
                  },
                  onContextChanged: (value) {
                    setState(() => _contextWindow = value);
                    updatePage(() {});
                    unawaited(_saveSettings());
                  },
                  onTemperatureChanged: (value) {
                    setState(() => _temperature = value);
                    updatePage(() {});
                    unawaited(_saveSettings());
                  },
                  onTopPChanged: (value) {
                    setState(() => _topP = value);
                    updatePage(() {});
                    unawaited(_saveSettings());
                  },
                  onMaxTokensChanged: (value) {
                    setState(() => _maxTokens = value);
                    updatePage(() {});
                    unawaited(_saveSettings());
                  },
                  onRepeatPenaltyChanged: (value) {
                    setState(() => _repeatPenalty = value);
                    updatePage(() {});
                    unawaited(_saveSettings());
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveTheme(AppTheme value) async {
    try {
      await _themeChannel.invokeMethod<void>('write', value.name);
    } on PlatformException {
      // The chosen theme still applies for this session.
    } on MissingPluginException {
      // Widget tests have no Android preference store.
    }
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.colors,
    required this.onSettings,
    required this.contextWindow,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.repeatPenalty,
  });

  final AppColors colors;
  final VoidCallback onSettings;
  final int contextWindow;
  final double temperature;
  final double topP;
  final int maxTokens;
  final double repeatPenalty;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _inference = LocalInference();
  final _store = ChatStore();
  final _messageController = TextEditingController();
  final List<SavedChat> _chats = [];
  List<DownloadedModel> _drawerModels = [];
  SavedChat? _activeChat;
  List<ChatMessage> get _messages => _activeChat?.messages ?? <ChatMessage>[];
  ImportedModel? _selectedModel;
  bool _loadingChats = true;
  bool _canWriteChats = true;
  bool _loadingModel = false;
  bool _generating = false;
  bool _modelsExpanded = false;
  bool _loadingDrawerModels = false;
  String? _drawerModelsError;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    try {
      final chats = await _store.read();
      if (mounted) setState(() => _chats.addAll(chats));
    } on MissingPluginException {
      // Widget tests can run without Android storage.
    } on PlatformException catch (error) {
      _canWriteChats = false;
      if (mounted) _showError(error.message ?? 'Could not read saved chats');
    } on FormatException {
      _canWriteChats = false;
      if (mounted) _showError('Saved chats could not be read');
    } on TypeError {
      _canWriteChats = false;
      if (mounted) _showError('Saved chats could not be read');
    } finally {
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<void> _saveChats() async {
    if (!_canWriteChats) return;
    try {
      await _store.write(_chats);
    } on MissingPluginException {
      // Widget tests can run without Android storage.
    } on PlatformException catch (error) {
      if (mounted) _showError(error.message ?? 'Could not save chats');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _configure() => _inference.configure(
    contextWindow: widget.contextWindow,
    temperature: widget.temperature,
    topP: widget.topP,
    repeatPenalty: widget.repeatPenalty,
  );

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _selectModel(ImportedModel model) async {
    if (_selectedModel?.uri == model.uri) return;
    setState(() => _loadingModel = true);
    try {
      await _configure();
      await _inference.loadSelectedModel(model);
      if (!mounted) return;
      setState(() {
        _selectedModel = model;
        if (_activeChat == null || _activeChat!.messages.isNotEmpty) {
          _activeChat = SavedChat(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'New chat',
            modelUri: model.uri,
            modelName: model.name,
            messages: [],
          );
          _chats.insert(0, _activeChat!);
        } else {
          _activeChat!.modelUri = model.uri;
          _activeChat!.modelName = model.name;
        }
      });
      await _saveChats();
    } on PlatformException {
      if (mounted) setState(() => _selectedModel = null);
      rethrow;
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<void> _send() async {
    final prompt = _messageController.text.trim();
    if (prompt.isEmpty ||
        _selectedModel == null ||
        _generating ||
        _loadingChats) {
      return;
    }
    _messageController.clear();
    setState(() {
      if (_activeChat!.messages.isEmpty) {
        _activeChat!.title = prompt.length > 40
            ? '${prompt.substring(0, 40)}…'
            : prompt;
      }
      _messages.add((fromUser: true, text: prompt));
      _generating = true;
    });
    try {
      await _saveChats();
      final rebuilt = await _configure();
      if (rebuilt) {
        await _inference.restoreHistory(
          _messages.sublist(0, _messages.length - 1),
        );
      }
      final reply = await _inference.generate(
        prompt,
        maxTokens: widget.maxTokens,
      );
      if (mounted && reply.isNotEmpty) {
        setState(() => _messages.add((fromUser: false, text: reply)));
        await _saveChats();
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not generate a reply'),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _newChat() async {
    if (_generating || _loadingModel || _loadingChats) return;
    if (_activeChat != null && _activeChat!.messages.isEmpty) return;
    try {
      if (_selectedModel != null) await _inference.restoreHistory([]);
      if (!mounted) return;
      setState(() {
        if (_selectedModel == null) {
          _activeChat = null;
        } else {
          _activeChat = SavedChat(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'New chat',
            modelUri: _selectedModel!.uri,
            modelName: _selectedModel!.name,
            messages: [],
          );
          _chats.insert(0, _activeChat!);
        }
      });
      await _saveChats();
    } on PlatformException catch (error) {
      if (mounted) _showError(error.message ?? 'Could not start a new chat');
    }
  }

  Future<void> _openChat(SavedChat chat) async {
    if (_generating || _loadingModel || _loadingChats) return;
    setState(() => _loadingModel = true);
    try {
      await _configure();
      await _inference.loadSelectedModel(
        ImportedModel(uri: chat.modelUri, name: chat.modelName),
      );
      await _inference.restoreHistory(chat.messages);
      if (mounted) {
        setState(() {
          _activeChat = chat;
          _selectedModel = ImportedModel(
            uri: chat.modelUri,
            name: chat.modelName,
          );
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _activeChat = chat;
          _selectedModel = null;
        });
        _showError(error.message ?? 'Could not open chat');
      }
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<void> _deleteChat(SavedChat chat) async {
    if (_generating || _loadingModel) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('Delete "${chat.title}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_activeChat?.id == chat.id) {
      try {
        await _inference.unloadModel();
      } on PlatformException catch (error) {
        if (mounted) _showError(error.message ?? 'Could not unload model');
      }
    }
    if (!mounted) return;
    setState(() {
      _chats.removeWhere((item) => item.id == chat.id);
      if (_activeChat?.id == chat.id) {
        _activeChat = null;
        _selectedModel = null;
      }
    });
    await _saveChats();
  }

  Future<void> _cancel() async {
    try {
      await _inference.cancel();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Could not stop generation')),
        );
      }
    }
  }

  void _showModels(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ModelPickerSheet(
        inference: _inference,
        selectedUri: _selectedModel?.uri,
        onSelected: _selectModel,
      ),
    );
  }

  Future<void> _openDownloads() async {
    Navigator.pop(context);
    final model = await Navigator.push<ImportedModel>(
      context,
      MaterialPageRoute(
        builder: (context) => ModelDownloadsPage(inference: _inference),
      ),
    );
    if (model == null || !mounted) return;
    try {
      await _selectModel(model);
    } on PlatformException catch (error) {
      if (mounted) _showError(error.message ?? 'Could not load model');
    } on StateError catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _toggleDrawerModels() async {
    if (_modelsExpanded) {
      setState(() => _modelsExpanded = false);
      return;
    }
    setState(() {
      _modelsExpanded = true;
      _loadingDrawerModels = true;
      _drawerModelsError = null;
    });
    try {
      final models = await ModelDownloads(_inference).list();
      if (mounted) setState(() => _drawerModels = models);
    } catch (_) {
      if (mounted) {
        setState(() => _drawerModelsError = 'Could not read downloaded models');
      }
    } finally {
      if (mounted) setState(() => _loadingDrawerModels = false);
    }
  }

  Future<void> _selectDrawerModel(DownloadedModel model) async {
    Navigator.pop(context);
    try {
      await _selectModel(model.chatModel);
    } on PlatformException catch (error) {
      if (mounted) _showError(error.message ?? 'Could not load model');
    } on StateError catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _importFromDrawer() async {
    Navigator.pop(context);
    if (!mounted) return;
    setState(() => _loadingModel = true);
    try {
      final model = await _inference.importModel();
      if (model != null && mounted) await _selectModel(model);
    } on PlatformException catch (error) {
      if (mounted) _showError(error.message ?? 'Could not import model');
    } catch (_) {
      if (mounted) _showError('Could not import model');
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Text(
                  'PortPotato',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.tonalIcon(
                  onPressed: _generating || _loadingModel || _loadingChats
                      ? null
                      : () {
                          Navigator.pop(context);
                          _newChat();
                        },
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('New chat'),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 24, right: 12),
                leading: const Icon(Icons.memory_outlined),
                title: const Text('Models'),
                onTap: _generating || _loadingModel ? null : _openDownloads,
                trailing: IconButton(
                  tooltip: _modelsExpanded
                      ? 'Hide downloaded models'
                      : 'Show downloaded models',
                  onPressed: _generating || _loadingModel
                      ? null
                      : _toggleDrawerModels,
                  icon: Icon(
                    _modelsExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ),
              ),
              if (_modelsExpanded) ...[
                if (_loadingDrawerModels)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: LinearProgressIndicator(),
                  )
                else if (_drawerModelsError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 4, 24, 8),
                    child: Text(
                      _drawerModelsError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                else if (_drawerModels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(56, 4, 24, 8),
                    child: Text('No downloaded models'),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 184),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _drawerModels.length,
                      itemBuilder: (context, index) {
                        final model = _drawerModels[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(
                            left: 56,
                            right: 24,
                          ),
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
                              ? const Text('Image chat unavailable')
                              : null,
                          selected: _selectedModel?.uri == model.path,
                          onTap: model.vision || _loadingModel || _generating
                              ? null
                              : () => _selectDrawerModel(model),
                        );
                      },
                    ),
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 56, right: 24),
                  leading: const Icon(Icons.add),
                  title: const Text('Import GGUF'),
                  onTap: _generating || _loadingModel
                      ? null
                      : _importFromDrawer,
                ),
              ],
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Chats',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: _loadingChats
                    ? const Center(child: CircularProgressIndicator())
                    : _chats.isEmpty
                    ? const Center(child: Text('No chats yet'))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (context, index) {
                          final chat = _chats[index];
                          return ListTile(
                            title: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              chat.modelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _activeChat?.id == chat.id,
                            onTap: _generating || _loadingModel
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _openChat(chat);
                                  },
                            trailing: IconButton(
                              tooltip: 'Delete ${chat.title}',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _generating || _loadingModel
                                  ? null
                                  : () => _deleteChat(chat),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSettings();
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open chat history',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('PortPotato'),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _generating || _loadingModel || _loadingChats
                ? null
                : _newChat,
          ),
        ],
      ),
      body: ColoredBox(
        color: colors.background,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: _selectedModel == null
                      ? [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 80),
                              child: Text(
                                'Pick a model and start chatting with it !!!',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: colors.muted),
                              ),
                            ),
                          ),
                        ]
                      : [
                          if (_messages.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 80),
                                child: Text(
                                  'Ready to chat with ${_selectedModel!.name}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: colors.muted),
                                ),
                              ),
                            ),
                          for (final message in _messages) ...[
                            _PreviewMessage(
                              colors: colors,
                              fromUser: message.fromUser,
                              text: message.text,
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (_generating)
                            Padding(
                              padding: const EdgeInsets.only(left: 44),
                              child: Text(
                                'Thinking…',
                                style: TextStyle(color: colors.muted),
                              ),
                            ),
                        ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: colors.background,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.memory_outlined, size: 18),
                      label: Text(
                        _loadingModel
                            ? 'Loading model…'
                            : _selectedModel?.name ?? 'Choose model',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.muted,
                      ),
                      onPressed: _loadingModel || _generating
                          ? null
                          : () => _showModels(context),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            enabled:
                                _selectedModel != null &&
                                !_loadingModel &&
                                !_generating,
                            onChanged: (_) => setState(() {}),
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: _selectedModel == null
                                  ? 'Choose a model to send a message'
                                  : 'Message',
                              hintStyle: TextStyle(color: colors.muted),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _generating
                              ? 'Stop generation'
                              : 'Send message',
                          onPressed: _generating
                              ? _cancel
                              : _selectedModel != null &&
                                    _messageController.text.trim().isNotEmpty
                              ? _send
                              : null,
                          icon: Icon(
                            _generating ? Icons.stop : Icons.arrow_upward,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.inference,
    required this.selectedUri,
    required this.onSelected,
  });

  final LocalInference inference;
  final String? selectedUri;
  final Future<void> Function(ImportedModel) onSelected;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  List<ImportedModel> _models = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final models = await widget.inference.listImportedModels();
      try {
        final downloaded = await ModelDownloads(widget.inference).list();
        models.addAll(
          downloaded
              .where((model) => !model.vision)
              .map((model) => model.chatModel),
        );
      } on MissingPluginException {
        // Widget previews may not have Android storage.
      } on StateError {
        // Imported documents can still be selected if local storage is unavailable.
      }
      if (mounted) {
        setState(() {
          _models = models;
          _error = null;
          _busy = false;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'Could not list models';
          _busy = false;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _error = 'Model import is available on Android';
          _busy = false;
        });
      }
    } on TypeError {
      if (mounted) {
        setState(() {
          _error = 'Could not read the model list';
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not read the model list';
          _busy = false;
        });
      }
    }
  }

  Future<void> _choose(ImportedModel model) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSelected(model);
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Could not load model');
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final model = await widget.inference.importModel();
      if (!mounted) return;
      if (model == null) {
        setState(() => _busy = false);
        return;
      }
      await _refresh();
      if (mounted) await _choose(model);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'Could not import model';
          _busy = false;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _error = 'Model import is available on Android';
          _busy = false;
        });
      }
    } on TypeError {
      if (mounted) {
        setState(() {
          _error = 'Could not read the selected model';
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not read the selected model';
          _busy = false;
        });
      }
    }
  }

  Future<void> _browse() async {
    final selected = await Navigator.push<ImportedModel>(
      context,
      MaterialPageRoute(
        builder: (context) => ModelDownloadsPage(inference: widget.inference),
      ),
    );
    if (!mounted) return;
    await _refresh();
    if (selected != null && mounted) await _choose(selected);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a model',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _models.isEmpty
                  ? const Center(child: Text('No imported models yet'))
                  : ListView.builder(
                      itemCount: _models.length,
                      itemBuilder: (context, index) {
                        final model = _models[index];
                        return ListTile(
                          leading: const Icon(Icons.memory_outlined),
                          title: Text(
                            model.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: model.uri == widget.selectedUri
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => _choose(model),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import GGUF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _browse,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Find models'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.colors,
    required this.fromUser,
    required this.text,
  });

  final AppColors colors;
  final bool fromUser;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: fromUser
        ? MainAxisAlignment.end
        : MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!fromUser) ...[
        CircleAvatar(
          radius: 17,
          backgroundColor: colors.raised,
          child: Icon(Icons.memory_outlined, size: 19, color: colors.text),
        ),
        const SizedBox(width: 10),
      ],
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: fromUser ? colors.outgoing : colors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ),
    ],
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.colors,
    required this.theme,
    required this.contextWindow,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.repeatPenalty,
    required this.onThemeChanged,
    required this.onContextChanged,
    required this.onTemperatureChanged,
    required this.onTopPChanged,
    required this.onMaxTokensChanged,
    required this.onRepeatPenaltyChanged,
  });

  final AppColors colors;
  final AppTheme theme;
  final int contextWindow;
  final double temperature;
  final double topP;
  final int maxTokens;
  final double repeatPenalty;
  final ValueChanged<AppTheme> onThemeChanged;
  final ValueChanged<int> onContextChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<double> onTopPChanged;
  final ValueChanged<int> onMaxTokensChanged;
  final ValueChanged<double> onRepeatPenaltyChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            color: colors.surface,
            child: Column(
              children: [
                for (final option in AppTheme.values)
                  ListTile(
                    title: Text(option.label),
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: AppColors.forTheme(option).background,
                      child: option == theme
                          ? Icon(
                              Icons.check,
                              size: 17,
                              color: AppColors.forTheme(option).text,
                            )
                          : null,
                    ),
                    trailing: option == theme
                        ? const Icon(Icons.check_circle)
                        : null,
                    selected: option == theme,
                    onTap: () => onThemeChanged(option),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Model & context',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(child: Text('Context window')),
                  DropdownButton<int>(
                    value: contextWindow,
                    items: [2048, 4096, 8192, 16384]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onContextChanged(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Generation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            color: colors.surface,
            child: Column(
              children: [
                _SettingSlider(
                  label: 'Temperature',
                  value: temperature,
                  min: 0,
                  max: 2,
                  onChanged: onTemperatureChanged,
                ),
                const Divider(height: 1),
                _SettingSlider(
                  label: 'Top P',
                  value: topP,
                  min: 0,
                  max: 1,
                  onChanged: onTopPChanged,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Max tokens')),
                      DropdownButton<int>(
                        value: maxTokens,
                        items: [256, 512, 1024, 2048]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) onMaxTokensChanged(value);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _SettingSlider(
                  label: 'Repeat penalty',
                  value: repeatPenalty,
                  min: 1,
                  max: 2,
                  onChanged: onRepeatPenaltyChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value.toStringAsFixed(2),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          label: value.toStringAsFixed(2),
        ),
      ],
    ),
  );
}
