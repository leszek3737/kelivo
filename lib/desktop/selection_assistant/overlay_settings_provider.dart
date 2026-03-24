import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/providers/settings_provider.dart' show ProviderConfig;
import '../../shared/interfaces/markdown_settings.dart';

class OverlaySettingsProvider extends ChangeNotifier implements MarkdownSettings {
  // MarkdownSettings fields
  bool _enableMathRendering = true;
  bool _enableDollarLatex = true;
  String? _codeFontFamily;
  bool _codeFontIsGoogle = false;
  String? _appFontFamily;
  bool _appFontIsGoogle = false;
  bool _mobileCodeBlockWrap = false;
  bool _autoCollapseCodeBlock = false;
  int _autoCollapseCodeBlockLines = 20;

  // SA-specific fields
  List<ProviderConfig> _providerConfigs = [];
  String? _selectedModelId;
  String _translateTargetLanguage = 'pl';
  ThemeMode _themeMode = ThemeMode.system;
  bool _initialized = false;

  // SA button visibility fields
  bool _showTranslateButton = true;
  bool _showTtsButton = true;
  bool _showChatButton = true;
  bool _showPresets = true;

  @override
  bool get enableMathRendering => _enableMathRendering;
  @override
  bool get enableDollarLatex => _enableDollarLatex;
  @override
  String? get codeFontFamily => _codeFontFamily;
  @override
  bool get codeFontIsGoogle => _codeFontIsGoogle;
  @override
  String? get appFontFamily => _appFontFamily;
  @override
  bool get appFontIsGoogle => _appFontIsGoogle;
  @override
  bool get mobileCodeBlockWrap => _mobileCodeBlockWrap;
  @override
  bool get autoCollapseCodeBlock => _autoCollapseCodeBlock;
  @override
  int get autoCollapseCodeBlockLines => _autoCollapseCodeBlockLines;

  List<ProviderConfig> get providerConfigs => _providerConfigs;
  String? get selectedModelId => _selectedModelId;
  String get translateTargetLanguage => _translateTargetLanguage;
  ThemeMode get themeMode => _themeMode;
  bool get initialized => _initialized;

  // SA button visibility getters
  bool get showTranslateButton => _showTranslateButton;
  bool get showTtsButton => _showTtsButton;
  bool get showChatButton => _showChatButton;
  bool get showPresets => _showPresets;

  /// Returns the ProviderConfig that owns [_selectedModelId], or the first one.
  /// [_selectedModelId] is stored as 'providerKey::modelId' in SharedPreferences.
  ProviderConfig? get activeProviderConfig {
    if (_providerConfigs.isEmpty) return null;
    if (_selectedModelId != null) {
      // Format: 'providerKey::modelId' – match by provider key prefix
      final parts = _selectedModelId!.split('::');
      if (parts.length == 2) {
        final providerKey = parts[0];
        for (final cfg in _providerConfigs) {
          if (cfg.id == providerKey || cfg.models.contains(providerKey)) {
            return cfg;
          }
        }
      }
    }
    return _providerConfigs.first;
  }

  String? get activeModelId {
    if (_selectedModelId != null) {
      final parts = _selectedModelId!.split('::');
      if (parts.length == 2) return parts[1];
    }
    return activeProviderConfig?.models.firstOrNull;
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      _enableMathRendering =
          prefs.getBool('display_enable_math_rendering_v1') ?? true;
      _enableDollarLatex =
          prefs.getBool('display_enable_dollar_latex_v1') ?? true;
      _codeFontFamily = prefs.getString('display_code_font_family_v1');
      if (_codeFontFamily?.isEmpty == true) _codeFontFamily = null;
      _codeFontIsGoogle =
          prefs.getBool('display_code_font_is_google_v1') ?? false;
      _appFontFamily = prefs.getString('display_app_font_family_v1');
      if (_appFontFamily?.isEmpty == true) _appFontFamily = null;
      _appFontIsGoogle =
          prefs.getBool('display_app_font_is_google_v1') ?? false;
      _mobileCodeBlockWrap =
          prefs.getBool('display_mobile_code_block_wrap_v1') ?? false;
      _autoCollapseCodeBlock =
          prefs.getBool('display_auto_collapse_code_block_v1') ?? false;
      _autoCollapseCodeBlockLines =
          prefs.getInt('display_auto_collapse_code_block_lines_v1') ?? 20;

      // Provider configs
      final configsJson = prefs.getString('provider_configs_v1');
      if (configsJson != null) {
        try {
          final list = jsonDecode(configsJson) as List<dynamic>;
          _providerConfigs = list
              .map((e) => ProviderConfig.fromJson(e as Map<String, dynamic>))
              .where((c) => c.enabled && c.apiKey.isNotEmpty)
              .toList();
        } catch (_) {}
      }

      _selectedModelId = prefs.getString('selected_model_v1');
      _translateTargetLanguage =
          prefs.getString('sa_translateTargetLanguage') ?? 'pl';

      _showTranslateButton = prefs.getBool('sa_showTranslateButton') ?? true;
      _showTtsButton = prefs.getBool('sa_showTtsButton') ?? true;
      _showChatButton = prefs.getBool('sa_showChatButton') ?? true;
      _showPresets = prefs.getBool('sa_showPresets') ?? true;

      final themeStr = prefs.getString('theme_mode_v1') ?? 'system';
      _themeMode = themeStr == 'dark'
          ? ThemeMode.dark
          : themeStr == 'light'
              ? ThemeMode.light
              : ThemeMode.system;

      _initialized = true;
      notifyListeners();
    } catch (_) {
      _initialized = true;
    }
  }
}
