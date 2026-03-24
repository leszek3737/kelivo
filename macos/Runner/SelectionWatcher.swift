import Cocoa
import ApplicationServices

/// Monitors text selection changes across all apps using AXObserver.
/// Calls ToolbarWindowManager.shared.show(text:mouseLocation:) when valid selection detected.
class SelectionWatcher {
    static let shared = SelectionWatcher()
    private init() {}

    private var axObserver: AXObserver?
    private var observedPid: pid_t = 0
    private var debounceWork: DispatchWorkItem?
    private var workspaceObserver: NSObjectProtocol?

    var onSelection: ((String, NSPoint) -> Void)?

    func start() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.switchObservedApp(pid: app.processIdentifier)
        }
        // Observe the currently active app immediately
        if let front = NSWorkspace.shared.frontmostApplication {
            switchObservedApp(pid: front.processIdentifier)
        }
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        removeCurrentObserver()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }

    private func switchObservedApp(pid: pid_t) {
        // Cancel pending debounce to avoid reading text from old app
        debounceWork?.cancel()
        debounceWork = nil
        removeCurrentObserver()
        guard pid != 0 else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon = refcon else { return }
            let watcher = Unmanaged<SelectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handleSelectionChange(on: element)
        }
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let obs = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(obs, appElement, kAXSelectedTextChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        self.axObserver = obs
        self.observedPid = pid
    }

    private func removeCurrentObserver() {
        guard let obs = axObserver, observedPid != 0 else { return }
        let appElement = AXUIElementCreateApplication(observedPid)
        AXObserverRemoveNotification(obs, appElement, kAXSelectedTextChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        axObserver = nil
        observedPid = 0
    }

    private func handleSelectionChange(on element: AXUIElement) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.readSelection(from: element)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func readSelection(from element: AXUIElement) {
        // Check enabled flag from UserDefaults
        let enabled = UserDefaults.standard.bool(forKey: "flutter.sa_enabled")
        guard enabled else { return }

        // Get focused element (the one with actual selection)
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        let targetElement: AXUIElement
        if focusedResult == .success, let fe = focusedRef {
            targetElement = (fe as! AXUIElement)
        } else {
            targetElement = element
        }

        // Read selected text
        var textRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(targetElement, kAXSelectedTextAttribute as CFString, &textRef)
        guard textResult == .success, let text = textRef as? String else { return }

        // Filter
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }

        let maxLength = UserDefaults.standard.integer(forKey: "flutter.sa_maxTextLength")
        let limit = maxLength > 0 ? maxLength : 5000
        guard trimmed.count <= limit else { return }

        // Get mouse position
        let mouseLocation = NSEvent.mouseLocation

        // Notify on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onSelection?(trimmed, mouseLocation)
        }
    }
}
