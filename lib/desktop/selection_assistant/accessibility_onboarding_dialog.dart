import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';

class AccessibilityOnboardingDialog extends StatefulWidget {
  const AccessibilityOnboardingDialog({super.key});

  @override
  State<AccessibilityOnboardingDialog> createState() => _AccessibilityOnboardingDialogState();

  /// Shows the dialog. Resolves when dismissed (either by user or after permission is granted).
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AccessibilityOnboardingDialog(),
    );
  }
}

class _AccessibilityOnboardingDialogState extends State<AccessibilityOnboardingDialog> {
  // Use a dedicated channel to avoid conflicts with DesktopHomePage which
  // also registers a handler on 'app.selectionAssistant/main'.
  static const _channel = MethodChannel('app.selectionAssistant/onboarding');
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    // Listen for permission-granted signal from Swift
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'axPermissionGranted') {
      if (mounted) setState(() => _granted = true);
      // Brief delay to show the success state before closing
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _openAccessibilitySettings() async {
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.accessibility_new, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.saAccessibilityTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.saAccessibilityMessage),
          const SizedBox(height: 16),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState:
                _granted ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(l10n.saAccessibilityWaiting),
              ],
            ),
            secondChild: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  l10n.saAccessibilityGranted,
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(l10n.saAccessibilityOpenSettings),
          onPressed: _openAccessibilitySettings,
        ),
      ],
    );
  }
}
