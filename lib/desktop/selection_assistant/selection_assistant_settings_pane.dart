import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../icons/lucide_adapter.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../core/services/haptics.dart';
import 'accessibility_onboarding_dialog.dart';

class SelectionAssistantSettingsPane extends StatefulWidget {
  const SelectionAssistantSettingsPane({super.key});

  @override
  State<SelectionAssistantSettingsPane> createState() => _State();
}

class _State extends State<SelectionAssistantSettingsPane> {
  bool _enabled = false;
  bool _showTranslate = true;
  bool _showTts = true;
  bool _showChat = true;
  bool _showPresets = true;
  String _translateLang = 'pl';
  int _dismissDelay = 4000;
  int _maxTextLength = 5000;
  bool _loaded = false;
  bool _axExplained = false;

  static final List<(String, String)> _langs = [
    ('en', 'English'),
    ('pl', 'Polish'),
    ('de', 'German'),
    ('fr', 'French'),
    ('es', 'Spanish'),
    ('zh', 'Chinese'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('ru', 'Russian'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('nl', 'Dutch'),
    ('uk', 'Ukrainian'),
    ('ar', 'Arabic'),
    ('tr', 'Turkish'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool('sa_enabled') ?? false;
      _showTranslate = prefs.getBool('sa_showTranslateButton') ?? true;
      _showTts = prefs.getBool('sa_showTtsButton') ?? true;
      _showChat = prefs.getBool('sa_showChatButton') ?? true;
      _showPresets = prefs.getBool('sa_showPresets') ?? true;
      _translateLang = prefs.getString('sa_translateTargetLanguage') ?? 'pl';
      _dismissDelay = prefs.getInt('sa_dismissDelay') ?? 4000;
      _maxTextLength = prefs.getInt('sa_maxTextLength') ?? 5000;
      _axExplained = prefs.getBool('sa_ax_explained') ?? false;
      _loaded = true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _showAccessibilityOnboarding() async {
    if (!mounted) return;
    await AccessibilityOnboardingDialog.show(context);
    // Mark as explained so we don't show again after permission is granted
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sa_ax_explained', true);
    if (mounted) setState(() => _axExplained = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.saSettingsTitle),
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                // Main toggle section
                _iosSectionCard(
                  children: [
                    _iosSwitchRow(
                      context,
                      icon: Lucide.TextSelect,
                      label: l10n.saSettingsEnable,
                      subtitle: l10n.saSettingsEnableSubtitle,
                      value: _enabled,
                      onChanged: (v) {
                        setState(() => _enabled = v);
                        _saveBool('sa_enabled', v);
                        // On macOS, show accessibility onboarding when enabling
                        // for the first time (until AX permission is confirmed).
                        if (v && Platform.isMacOS && !_axExplained) {
                          _showAccessibilityOnboarding();
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _sectionHeader(l10n.saSettingsShowTranslate.replaceAll(' button', '')),
                _iosSectionCard(
                  children: [
                    _iosSwitchRow(
                      context,
                      icon: Lucide.Languages,
                      label: l10n.saSettingsShowTranslate,
                      value: _showTranslate,
                      enabled: _enabled,
                      onChanged: (v) {
                        setState(() => _showTranslate = v);
                        _saveBool('sa_showTranslateButton', v);
                      },
                    ),
                    _iosDivider(context),
                    _iosSwitchRow(
                      context,
                      icon: Lucide.Volume2,
                      label: l10n.saSettingsShowTts,
                      value: _showTts,
                      enabled: _enabled,
                      onChanged: (v) {
                        setState(() => _showTts = v);
                        _saveBool('sa_showTtsButton', v);
                      },
                    ),
                    _iosDivider(context),
                    _iosSwitchRow(
                      context,
                      icon: Lucide.MessageCirclePlus,
                      label: l10n.saSettingsShowChat,
                      value: _showChat,
                      enabled: _enabled,
                      onChanged: (v) {
                        setState(() => _showChat = v);
                        _saveBool('sa_showChatButton', v);
                      },
                    ),
                    _iosDivider(context),
                    _iosSwitchRow(
                      context,
                      icon: Lucide.ListOrdered,
                      label: l10n.saSettingsShowPresets,
                      value: _showPresets,
                      enabled: _enabled,
                      onChanged: (v) {
                        setState(() => _showPresets = v);
                        _saveBool('sa_showPresets', v);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _sectionHeader(l10n.saSettingsTranslateLanguage),
                _iosSectionCard(
                  children: [
                    _iosNavRow(
                      context,
                      icon: Lucide.Globe,
                      label: l10n.saSettingsTranslateLanguage,
                      detailText: _langDisplayName(_translateLang),
                      enabled: _enabled,
                      onTap: () => _showLanguageSheet(context),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _sectionHeader(l10n.saSettingsDismissDelay),
                _iosSectionCard(
                  children: [
                    _iosNavRow(
                      context,
                      icon: Lucide.Timer,
                      label: l10n.saSettingsDismissDelay,
                      detailText: l10n.saSettingsDismissDelayMs(_dismissDelay),
                      enabled: _enabled,
                      onTap: () => _showDismissDelaySheet(context),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _sectionHeader(l10n.saSettingsMaxTextLength),
                _iosSectionCard(
                  children: [
                    _iosNavRow(
                      context,
                      icon: Lucide.TextSelect,
                      label: l10n.saSettingsMaxTextLength,
                      detailText: l10n.saSettingsMaxTextLengthChars(_maxTextLength),
                      enabled: _enabled,
                      onTap: () => _showMaxTextLengthSheet(context),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  String _langDisplayName(String code) {
    for (final (c, name) in _langs) {
      if (c == code) return name;
    }
    return code.toUpperCase();
  }

  Widget _sectionHeader(String text, {bool first = false}) => Padding(
    padding: EdgeInsets.fromLTRB(12, first ? 2 : 0, 12, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      ),
    ),
  );

  Future<void> _showLanguageSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l10n.saSettingsTranslateLanguage,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _langs.map((lang) {
                    final (code, name) = lang;
                    final isSelected = code == _translateLang;
                    return _sheetOption(
                      ctx,
                      label: name,
                      isSelected: isSelected,
                      onTap: () => Navigator.of(ctx).pop(code),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != _translateLang) {
      setState(() => _translateLang = selected);
      await _saveString('sa_translateTargetLanguage', selected);
    }
  }

  Future<void> _showDismissDelaySheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    int tempDelay = _dismissDelay;

    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.saSettingsDismissDelay,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '1000ms',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: tempDelay.toDouble(),
                        min: 1000,
                        max: 10000,
                        divisions: 18,
                        activeColor: cs.primary,
                        inactiveColor: cs.onSurface.withValues(alpha: 0.2),
                        onChanged: (v) {
                          setSheetState(() => tempDelay = v.round());
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.saSettingsDismissDelayMs(tempDelay),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.settingsPageTitle),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tempDelay != _dismissDelay) {
      setState(() => _dismissDelay = tempDelay);
      await _saveInt('sa_dismissDelay', tempDelay);
    }
  }

  Future<void> _showMaxTextLengthSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    int tempLength = _maxTextLength;

    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.saSettingsMaxTextLength,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '100',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: tempLength.toDouble(),
                        min: 100,
                        max: 20000,
                        divisions: 199,
                        activeColor: cs.primary,
                        inactiveColor: cs.onSurface.withValues(alpha: 0.2),
                        onChanged: (v) {
                          setSheetState(() => tempLength = v.round());
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.saSettingsMaxTextLengthChars(tempLength),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.settingsPageTitle),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tempLength != _maxTextLength) {
      setState(() => _maxTextLength = tempLength);
      await _saveInt('sa_maxTextLength', tempLength);
    }
  }
}

// --- iOS-style widgets (matching settings_page.dart style) ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed
        ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.00,
    this.haptics = true,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
  bool enabled = true,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null && enabled;
  return _TactileRow(
    onTap: interactive ? onTap : null,
    pressedScale: 1.00,
    haptics: false,
    builder: (pressed) {
      final baseColor = enabled
          ? cs.onSurface.withValues(alpha: 0.9)
          : cs.onSurface.withValues(alpha: 0.4);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: c,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: enabled ? 0.6 : 0.3),
                      ),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: enabled ? 0.6 : 0.3),
                      ),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _iosSwitchRow(
  BuildContext context, {
  IconData? icon,
  required String label,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
  bool enabled = true,
}) {
  final cs = Theme.of(context).colorScheme;
  return _TactileRow(
    onTap: enabled ? () => onChanged(!value) : null,
    builder: (pressed) {
      final baseColor = enabled
          ? cs.onSurface.withValues(alpha: 0.9)
          : cs.onSurface.withValues(alpha: 0.4);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: subtitle != null ? 8 : 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox(width: 48),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 15, color: c)),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: enabled ? 0.6 : 0.3),
                          ),
                        ),
                    ],
                  ),
                ),
                IosSwitch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetOption(
  BuildContext context, {
  IconData? icon,
  required String label,
  bool isSelected = false,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _TactileRow(
    onTap: onTap,
    builder: (pressed) {
      final base = cs.onSurface;
      final target = pressed
          ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ??
                base)
          : base;
      final bgTarget = pressed
          ? (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05))
          : Colors.transparent;
      return TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, color, _) {
          final c = color ?? base;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  SizedBox(width: 24, child: Icon(icon, size: 20, color: c)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
                if (isSelected)
                  Icon(Lucide.Check, size: 18, color: cs.primary),
              ],
            ),
          );
        },
      );
    },
  );
}
