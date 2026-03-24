import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/tts_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import '../../shared/interfaces/markdown_settings.dart';
import '../../shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'overlay_settings_provider.dart';

class ResultOverlayApp extends StatelessWidget {
  const ResultOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OverlaySettingsProvider()..init()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
      ],
      child: Consumer<OverlaySettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: ThemeData.light(useMaterial3: true),
            darkTheme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ResultOverlayPage(),
          );
        },
      ),
    );
  }
}

enum _ResultState { idle, loading, streaming, done, error }

class ResultOverlayPage extends StatefulWidget {
  const ResultOverlayPage({super.key});

  @override
  State<ResultOverlayPage> createState() => _ResultOverlayPageState();
}

class _ResultOverlayPageState extends State<ResultOverlayPage> {
  static const _channel = MethodChannel('app.selectionAssistant/result');

  _ResultState _state = _ResultState.idle;
  String _title = '';
  String _type = 'standard';
  String _sourceText = '';
  String _targetLang = 'pl';
  String _result = '';
  String _error = '';
  StreamSubscription<ChatStreamChunk>? _streamSub;

  // For height reporting
  final _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'showResult':
          final args = call.arguments as Map?;
          final title = args?['title'] as String? ?? '';
          final type = args?['type'] as String? ?? 'standard';
          final sourceText = args?['sourceText'] as String? ?? '';
          final targetLang = args?['targetLang'] as String? ?? 'pl';
          _startRequest(
            title: title,
            type: type,
            sourceText: sourceText,
            targetLang: targetLang,
          );
        case 'hideResult':
          _cancelRequest();
          if (mounted) {
            setState(() {
              _state = _ResultState.idle;
              _result = '';
            });
          }
      }
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  void _startRequest({
    required String title,
    required String type,
    required String sourceText,
    required String targetLang,
  }) {
    _cancelRequest();
    if (!mounted) return;
    setState(() {
      _title = title;
      _type = type;
      _sourceText = sourceText;
      _targetLang = targetLang;
      _state = _ResultState.loading;
      _result = '';
      _error = '';
    });

    final settings = context.read<OverlaySettingsProvider>();
    final cfg = settings.activeProviderConfig;
    final modelId = settings.activeModelId;

    if (cfg == null || modelId == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _state = _ResultState.error;
          _error = l10n?.saErrorNoProvider ??
              'No LLM provider configured';
        });
      }
      return;
    }

    // Build prompt
    final l10n = AppLocalizations.of(context);
    final prompt = _buildPrompt(
      type: type,
      sourceText: sourceText,
      targetLang: targetLang,
      l10n: l10n,
    );

    final stream = ChatApiService.sendMessageStream(
      config: cfg,
      modelId: modelId,
      messages: [
        {'role': 'user', 'content': prompt}
      ],
      temperature: 0.7,
      maxTokens: 1024,
      requestId: 'sa_result_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (mounted) setState(() => _state = _ResultState.streaming);

    _streamSub = stream.listen(
      (chunk) {
        if (!mounted) return;
        setState(() {
          _result += chunk.content;
          _state = _ResultState.streaming;
        });
        _reportHeight();
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _state = _ResultState.done);
        _reportHeight();
        // Auto-speak for translateAndRead preset
        if (type == 'translateAndRead' && _result.isNotEmpty) {
          try {
            context.read<TtsProvider>().speak(_result);
          } catch (_) {}
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _state = _ResultState.error;
          _error = e.toString();
        });
        _reportHeight();
      },
    );
  }

  String _buildPrompt({
    required String type,
    required String sourceText,
    required String targetLang,
    AppLocalizations? l10n,
  }) {
    switch (type) {
      case 'translation':
      case 'translateAndRead':
        return l10n?.saPromptTranslate(targetLang, sourceText) ??
            'Translate to $targetLang:\n\n$sourceText';
      default:
        // Match on action keys (lowercase) sent by Swift/toolbar, not display labels.
        switch (_title) {
          case 'summarize':
            return l10n?.saPromptSummarize(sourceText) ??
                'Summarize: $sourceText';
          case 'explain':
            return l10n?.saPromptExplain(sourceText) ??
                'Explain: $sourceText';
          case 'fixGrammar':
            return l10n?.saPromptFixGrammar(sourceText) ??
                'Fix grammar: $sourceText';
          default:
            return '$_title:\n\n$sourceText';
        }
    }
  }

  void _cancelRequest() {
    _streamSub?.cancel();
    _streamSub = null;
  }

  void _reportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro =
          _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (ro == null) return;
      final height = ro.size.height + 60; // add padding
      _channel.invokeMethod('reportHeight', {'height': height});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<OverlaySettingsProvider>();

    return Provider<MarkdownSettings>.value(
      value: settings,
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: _contentKey,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, 6),
              )
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_state == _ResultState.loading ||
                      _state == _ResultState.streaming)
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      tooltip: l10n.saResultCancel,
                      onPressed: () {
                        _cancelRequest();
                        setState(() => _state = _ResultState.done);
                      },
                    ),
                  if (_state == _ResultState.done ||
                      _state == _ResultState.error)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.saResultClose,
                      onPressed: () =>
                          _channel.invokeMethod('dismiss'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Content
              if (_state == _ResultState.loading)
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_state == _ResultState.streaming ||
                  _state == _ResultState.done)
                MarkdownWithCodeHighlight(text: _result),
              if (_state == _ResultState.error)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error,
                      style: TextStyle(color: cs.error),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.saResultRetry),
                      onPressed: () => _startRequest(
                        title: _title,
                        type: _type,
                        sourceText: _sourceText,
                        targetLang: _targetLang,
                      ),
                    ),
                  ],
                ),
              // Footer: TTS + Copy buttons
              if (_result.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Consumer<TtsProvider>(
                      builder: (context, tts, _) {
                        final speaking = tts.isSpeaking;
                        return IconButton(
                          icon: Icon(
                            speaking
                                ? Icons.stop_circle_outlined
                                : Icons.volume_up_outlined,
                            size: 18,
                          ),
                          tooltip: l10n.saActionRead,
                          onPressed: () {
                            if (speaking) {
                              tts.stop();
                            } else {
                              tts.speak(_result);
                            }
                          },
                        );
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(l10n.saResultCopy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _result)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
