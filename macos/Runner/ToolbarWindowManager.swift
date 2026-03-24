import Cocoa
import FlutterMacOS

class ToolbarWindowManager {
    static let shared = ToolbarWindowManager()
    private init() {}

    private var panel: NSPanel?
    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var dismissTimer: Timer?
    private var globalMonitor: Any?
    private var resultIsVisible: Bool = false

    var onAction: ((String, String) -> Void)?

    // Called when result panel shows/hides — affects dismiss timer
    func setResultVisible(_ visible: Bool) {
        resultIsVisible = visible
        if visible {
            dismissTimer?.invalidate()
            dismissTimer = nil
        } else {
            startDismissTimer()
        }
    }

    func createEngine() {
        guard engine == nil else { return }
        let flutterEngine = FlutterEngine(name: "toolbar", project: nil, allowHeadlessExecution: false)
        flutterEngine.run(withEntrypoint: "toolbarOverlay")
        RegisterGeneratedPlugins(registry: flutterEngine)
        engine = flutterEngine

        let messenger = flutterEngine.binaryMessenger
        channel = FlutterMethodChannel(name: "app.selectionAssistant/toolbar", binaryMessenger: messenger)
        channel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "onAction":
                if let args = call.arguments as? [String: Any],
                   let action = args["action"] as? String,
                   let text = args["text"] as? String {
                    self?.onAction?(action, text)
                }
                result(nil)
            case "dismiss":
                self?.hide()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func destroyEngine() {
        hide()
        channel?.setMethodCallHandler(nil)
        channel = nil
        engine = nil
    }

    func show(text: String, mouseLocation: NSPoint) {
        guard engine != nil else { return }

        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 60

        // Find screen under cursor
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        let vf = screen.visibleFrame

        var panelX = mouseLocation.x + 12
        var panelY = mouseLocation.y + 8

        // Clamp to visible frame
        if panelX + panelWidth > vf.maxX { panelX = vf.maxX - panelWidth - 8 }
        if panelX < vf.minX { panelX = vf.minX + 8 }
        if panelY + panelHeight > vf.maxY { panelY = mouseLocation.y - panelHeight - 8 }
        if panelY < vf.minY { panelY = vf.minY + 8 }

        let frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        if panel == nil {
            let newPanel = NSPanel(
                contentRect: frame,
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .floating
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            if let eng = engine {
                let vc = FlutterViewController(engine: eng, nibName: nil, bundle: nil)
                newPanel.contentViewController = vc
            }
            panel = newPanel
            setupGlobalMonitor()
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFront(nil)

        // Send text to Dart
        channel?.invokeMethod("setText", arguments: ["text": text])

        startDismissTimer()
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeGlobalMonitor()
        panel?.orderOut(nil)
    }

    func updateText(_ text: String, at mouseLocation: NSPoint) {
        // Called on new selection — move panel, close result, update text
        show(text: text, mouseLocation: mouseLocation)
    }

    /// Exposed for AppDelegate to obtain toolbar frame when routing actions.
    var panelFrame: NSRect? { panel?.frame }

    private func startDismissTimer() {
        guard !resultIsVisible else { return }
        dismissTimer?.invalidate()
        let delay = UserDefaults.standard.integer(forKey: "flutter.sa_dismissDelay")
        let ms = delay > 0 ? delay : 4000
        dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(ms) / 1000.0, repeats: false) { [weak self] _ in
            self?.hide()
            ResultWindowManager.shared.hide()
        }
    }

    private func setupGlobalMonitor() {
        removeGlobalMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let loc = NSEvent.mouseLocation
            let inToolbar = self.panel.map { NSPointInRect(loc, $0.frame) } ?? false
            let inResult = ResultWindowManager.shared.containsPoint(loc)
            if !inToolbar && !inResult {
                self.hide()
                ResultWindowManager.shared.hide()
            }
        }
    }

    private func removeGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
