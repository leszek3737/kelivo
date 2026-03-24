import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'overlay_settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

class ToolbarOverlayApp extends StatelessWidget {
  const ToolbarOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OverlaySettingsProvider()..init(),
      child: Consumer<OverlaySettingsProvider>(
        builder: (context, settings, _) {
          final themeMode = settings.themeMode;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            theme: ThemeData.light(useMaterial3: true),
            darkTheme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ToolbarOverlayPage(),
          );
        },
      ),
    );
  }
}

class ToolbarOverlayPage extends StatefulWidget {
  const ToolbarOverlayPage({super.key});

  @override
  State<ToolbarOverlayPage> createState() => _ToolbarOverlayPageState();
}

class _ToolbarOverlayPageState extends State<ToolbarOverlayPage> {
  static const _channel = MethodChannel('app.selectionAssistant/toolbar');
  String _text = '';

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'setText') {
        final text = (call.arguments as Map?)?['text'] as String? ?? '';
        if (mounted) setState(() => _text = text);
      }
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _onAction(String action) {
    _channel.invokeMethod('onAction', {'action': action, 'text': _text});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<OverlaySettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (settings.showTranslateButton)
              _ActionButton(
                icon: Icons.translate,
                label: l10n.saActionTranslate,
                onTap: () => _onAction('translate'),
              ),
            if (settings.showTtsButton)
              _ActionButton(
                icon: Icons.volume_up_rounded,
                label: l10n.saActionRead,
                onTap: () => _onAction('tts'),
              ),
            if (settings.showChatButton)
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: l10n.saActionSendToChat,
                onTap: () => _onAction('chat'),
              ),
            if (settings.showPresets) ...[
              _ActionButton(
                icon: Icons.summarize_outlined,
                label: l10n.saPresetSummarize,
                onTap: () => _onAction('preset:summarize'),
              ),
              _ActionButton(
                icon: Icons.lightbulb_outline,
                label: l10n.saPresetExplain,
                onTap: () => _onAction('preset:explain'),
              ),
              _ActionButton(
                icon: Icons.spellcheck,
                label: l10n.saPresetFixGrammar,
                onTap: () => _onAction('preset:fixGrammar'),
              ),
              _ActionButton(
                icon: Icons.record_voice_over_outlined,
                label: l10n.saPresetTranslateAndRead,
                onTap: () => _onAction('preset:translateAndRead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
