import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    private var saEnabled: Bool = false
    private var defaultsObserver: NSObjectProtocol?
    private var mainChannel: FlutterMethodChannel?
    private var axCheckTimer: Timer?
    private var axPollStartTime: Date?

    override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
        setupMainChannel()
        setupDefaultsObserver()
        // Read initial sa_enabled state
        let enabled = UserDefaults.standard.bool(forKey: "flutter.sa_enabled")
        if enabled {
            startSelectionAssistant()
        }
    }

    private func setupMainChannel() {
        // mainFlutterWindow is provided by FlutterAppDelegate
        guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
        let messenger = controller.engine.binaryMessenger
        mainChannel = FlutterMethodChannel(name: "app.selectionAssistant/main", binaryMessenger: messenger)
        // No incoming calls from Dart for now — this channel is used to send focusAndSetText TO Dart
    }

    private func setupDefaultsObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let enabled = UserDefaults.standard.bool(forKey: "flutter.sa_enabled")
            guard enabled != self?.saEnabled else { return }
            if enabled {
                self?.startSelectionAssistant()
            } else {
                self?.stopSelectionAssistant()
            }
        }
    }

    private func startSelectionAssistant() {
        saEnabled = true

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            // Request via system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            // Start polling until granted
            startAXMonitoring()
            return
        }

        // Create engines lazily
        ToolbarWindowManager.shared.createEngine()
        ResultWindowManager.shared.createEngine()

        // Wire up toolbar actions
        ToolbarWindowManager.shared.onAction = { [weak self] action, text in
            self?.handleToolbarAction(action: action, text: text)
        }

        // Start watcher
        SelectionWatcher.shared.onSelection = { text, mouseLocation in
            // Close any open result panel
            ResultWindowManager.shared.hide()
            // Show/update toolbar
            ToolbarWindowManager.shared.show(text: text, mouseLocation: mouseLocation)
        }
        SelectionWatcher.shared.start()
    }

    private func startAXMonitoring() {
        axCheckTimer?.invalidate()
        axPollStartTime = Date()
        axCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Stop polling after 60 seconds to avoid zombie loops
            if let start = self.axPollStartTime, Date().timeIntervalSince(start) > 60 {
                self.axCheckTimer?.invalidate()
                self.axCheckTimer = nil
                self.axPollStartTime = nil
                return
            }
            if AXIsProcessTrusted() {
                self.axCheckTimer?.invalidate()
                self.axCheckTimer = nil
                self.axPollStartTime = nil
                // Now actually start the selection assistant
                ToolbarWindowManager.shared.createEngine()
                ResultWindowManager.shared.createEngine()
                ToolbarWindowManager.shared.onAction = { [weak self] action, text in
                    self?.handleToolbarAction(action: action, text: text)
                }
                SelectionWatcher.shared.onSelection = { [weak self] text, mouseLocation in
                    ResultWindowManager.shared.hide()
                    ToolbarWindowManager.shared.show(text: text, mouseLocation: mouseLocation)
                }
                SelectionWatcher.shared.start()
                // Notify Dart that permission was granted
                self.mainChannel?.invokeMethod("axPermissionGranted", arguments: nil)
            }
        }
    }

    private func stopSelectionAssistant() {
        saEnabled = false
        SelectionWatcher.shared.stop()
        ToolbarWindowManager.shared.hide()
        ResultWindowManager.shared.hide()
        ToolbarWindowManager.shared.destroyEngine()
        ResultWindowManager.shared.destroyEngine()
    }

    private func handleToolbarAction(action: String, text: String) {
        switch action {
        case "tts":
            // TTS is handled in Dart toolbar engine directly — nothing to do in Swift
            break
        case "chat":
            // Show main window and send text
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                break
            }
            mainChannel?.invokeMethod("focusAndSetText", arguments: ["text": text])
        case "translate":
            if let toolbarFrame = ToolbarWindowManager.shared.panelFrame {
                ResultWindowManager.shared.show(
                    near: toolbarFrame,
                    title: "Translate",
                    type: "translation",
                    sourceText: text,
                    targetLang: UserDefaults.standard.string(forKey: "flutter.sa_translateTargetLanguage") ?? "pl"
                )
            }
        default:
            // preset:xxx
            if action.hasPrefix("preset:") {
                if let toolbarFrame = ToolbarWindowManager.shared.panelFrame {
                    let presetKey = String(action.dropFirst("preset:".count))
                    if presetKey == "translateAndRead" {
                        // Orchestrate: translate first, then TTS in Dart result panel
                        let targetLang = UserDefaults.standard.string(forKey: "flutter.sa_translateTargetLanguage") ?? "pl"
                        ResultWindowManager.shared.show(
                            near: toolbarFrame,
                            title: presetKey,
                            type: "translateAndRead",
                            sourceText: text,
                            targetLang: targetLang
                        )
                    } else {
                        ResultWindowManager.shared.show(
                            near: toolbarFrame,
                            title: presetKey,
                            type: "standard",
                            sourceText: text
                        )
                    }
                }
            }
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
