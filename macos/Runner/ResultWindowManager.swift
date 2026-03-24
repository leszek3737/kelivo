import Cocoa
import FlutterMacOS

class ResultWindowManager {
    static let shared = ResultWindowManager()
    private init() {}

    private var panel: NSPanel?
    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?

    func containsPoint(_ point: NSPoint) -> Bool {
        guard let p = panel, p.isVisible else { return false }
        return NSPointInRect(point, p.frame)
    }

    func createEngine() {
        guard engine == nil else { return }
        let flutterEngine = FlutterEngine(name: "result", project: nil, allowHeadlessExecution: false)
        flutterEngine.run(withEntrypoint: "resultOverlay")
        RegisterGeneratedPlugins(registry: flutterEngine)
        engine = flutterEngine

        let messenger = flutterEngine.binaryMessenger
        channel = FlutterMethodChannel(name: "app.selectionAssistant/result", binaryMessenger: messenger)
        channel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "reportHeight":
                if let args = call.arguments as? [String: Any],
                   let height = args["height"] as? Double {
                    self?.resizePanel(height: CGFloat(height))
                }
                result(nil)
            case "dismiss":
                self?.hide()
                ToolbarWindowManager.shared.setResultVisible(false)
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

    func show(near toolbarFrame: NSRect, title: String, type: String, sourceText: String, targetLang: String? = nil) {
        guard engine != nil else { return }

        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 200  // initial, will be updated by reportHeight

        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: toolbarFrame.midX, y: toolbarFrame.midY))
        }) ?? NSScreen.main!
        let vf = screen.visibleFrame

        var panelX = toolbarFrame.origin.x
        var panelY = toolbarFrame.origin.y - panelHeight - 8

        // If goes below visibleFrame, place above toolbar
        if panelY < vf.minY {
            panelY = toolbarFrame.maxY + 8
        }
        if panelX + panelWidth > vf.maxX {
            panelX = vf.maxX - panelWidth - 8
        }
        if panelX < vf.minX {
            panelX = vf.minX + 8
        }

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
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFront(nil)

        var args: [String: Any] = ["title": title, "type": type, "sourceText": sourceText]
        if let lang = targetLang { args["targetLang"] = lang }
        channel?.invokeMethod("showResult", arguments: args)

        ToolbarWindowManager.shared.setResultVisible(true)
    }

    func hide() {
        panel?.orderOut(nil)
        ToolbarWindowManager.shared.setResultVisible(false)
    }

    private func resizePanel(height: CGFloat) {
        guard let p = panel else { return }
        let maxH: CGFloat = 500
        let clampedH = min(max(height, 100), maxH)
        var frame = p.frame
        let delta = clampedH - frame.height
        frame.origin.y -= delta  // macOS Y grows up, so adjust origin
        frame.size.height = clampedH

        // Clamp to screen
        let screen = NSScreen.screens.first(where: { $0.frame.contains(frame.origin) }) ?? NSScreen.main!
        let vf = screen.visibleFrame
        if frame.minY < vf.minY {
            frame.origin.y = vf.minY + 8
        }

        p.setFrame(frame, display: true, animate: false)
    }

    var currentFrame: NSRect? { panel?.frame }
}
