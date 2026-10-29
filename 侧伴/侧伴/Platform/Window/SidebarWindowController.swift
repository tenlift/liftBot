import SidebarCore
import SwiftUI
import AppKit
import Observation
import QuartzCore

/// Own-window management only: no Accessibility permission or global event monitoring.
@MainActor @Observable final class SidebarWindowController: NSObject {
    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: "sidebarWindowPinned"); applyWindowLevel() }
    }
    var autoCollapse: Bool {
        didSet { defaults.set(autoCollapse, forKey: "sidebarAutoCollapse") }
    }
    private(set) var dockedEdge: SidebarEdge?
    private(set) var isCollapsed = false
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var handle: NSPanel?
    @ObservationIgnored private var screenNumber: NSNumber?
    @ObservationIgnored private var moveTask: Task<Void, Never>?
    @ObservationIgnored private var resignTask: Task<Void, Never>?
    @ObservationIgnored private var adjustingFrame = false
    @ObservationIgnored private var originalBehavior: NSWindow.CollectionBehavior?
    @ObservationIgnored private var lastFrame: CGRect?
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private weak var workspace: WorkspaceStore?
    @ObservationIgnored private var timer: PomodoroTimer?
    @ObservationIgnored private var audio: RecordingStore?
    @ObservationIgnored private var timerIcon: NSImageView?
    @ObservationIgnored private var recordingIcon: NSImageView?
    @ObservationIgnored private var tabButton: NSButton?
    @ObservationIgnored private var quickPanel: NSPanel?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var handleHovered = false
    @ObservationIgnored private var controlsHovered = false
    @ObservationIgnored private var manualControls = false
    @ObservationIgnored private var isTransitioning = false
    @ObservationIgnored private var pendingExpansion = false
    @ObservationIgnored private var transitionID = UUID()
    @ObservationIgnored private var quickTransitionID = UUID()

    func refreshLanguage() {
        window?.title = L10n.text("侧伴")
        handle?.title = L10n.text("展开侧伴")
        quickPanel?.title = L10n.text("侧伴快捷控制")
        if isCollapsed, let screen = targetScreen, let edge = dockedEdge {
            if !showHandle(on: screen, edge: edge) { expand() }
        }
        refreshIndicators()
    }

    func connect(store: WorkspaceStore) {
        workspace = store
        self.timer = store.timer
        self.audio = store.audio
        refreshIndicators()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: "sidebarWindowPinned")
        autoCollapse = defaults.object(forKey: "sidebarAutoCollapse") as? Bool ?? true
        super.init()
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        if let screen = window.screen ?? NSScreen.main {
            fitHeight(to: screen)
        }
        lastFrame = window.frame
        originalBehavior = window.collectionBehavior
        // Only the native title bar moves the window; content gestures resize panes.
        window.isMovableByWindowBackground = false
        applyWindowLevel()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowMoved), name: NSWindow.didMoveNotification, object: window)
        center.addObserver(self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(expandRequested), name: .showSidebarRequested, object: nil)
    }

    func detach() {
        transitionID = UUID()
        isTransitioning = false
        pendingExpansion = false
        statusTask?.cancel(); statusTask = nil
        hoverTask?.cancel(); dismissTask?.cancel()
        quickPanel?.orderOut(nil); quickPanel?.close(); quickPanel = nil
        moveTask?.cancel(); moveTask = nil
        resignTask?.cancel(); resignTask = nil
        NotificationCenter.default.removeObserver(self)
        handle?.orderOut(nil)
        handle?.close()
        handle = nil
        if let window {
            window.level = .normal
            if let originalBehavior { window.collectionBehavior = originalBehavior }
        }
        originalBehavior = nil
        window = nil
        dockedEdge = nil
        screenNumber = nil
        isCollapsed = false
    }

    func collapse(toward edge: SidebarEdge? = nil) {
        guard !isTransitioning, let window, window.isVisible, canCollapse, let screen = window.screen ?? targetScreen else { return }
        moveTask?.cancel(); resignTask?.cancel()
        let edge = edge ?? SidebarGeometry.nearestEdge(frame: window.frame, screen: screen.visibleFrame)
        dockedEdge = edge
        screenNumber = Self.number(screen)
        setFrame(SidebarGeometry.dockedFrame(window.frame, screen: screen.visibleFrame, edge: edge))
        // Never hide the primary window unless the native recovery tab is actually on screen.
        guard showHandle(on: screen, edge: edge) else { return }
        isCollapsed = true
        beginStatusRefresh()
        isTransitioning = true
        let token = UUID()
        transitionID = token
        let restingFrame = window.frame
        var target = restingFrame
        target.origin.x += edge == .left ? -32 : 32
        animate(window, frame: target, alpha: 0, duration: 0.20) { [weak self, weak window] in
            guard let self, let window, self.transitionID == token else { return }
            window.orderOut(nil)
            self.setFrame(restingFrame)
            window.alphaValue = 1
            self.isTransitioning = false
            self.handle?.orderFrontRegardless()
            if self.handle?.isVisible != true || self.pendingExpansion {
                self.pendingExpansion = false
                self.expand()
            } else if self.handleHovered { self.showQuickControls() }
        }
    }

    func expand() {
        guard let window else { return }
        if isTransitioning { pendingExpansion = true; return }
        guard isCollapsed else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        moveTask?.cancel(); resignTask?.cancel()
        statusTask?.cancel(); statusTask = nil
        hideQuickControls(animated: false)
        let screen = targetScreen
        let edge = dockedEdge ?? .right
        let target = screen.map { SidebarGeometry.dockedFrame(window.frame, screen: $0.visibleFrame, edge: edge) } ?? window.frame
        var origin = target
        origin.origin.x += edge == .left ? -32 : 32
        isTransitioning = true
        isCollapsed = false
        let token = UUID()
        transitionID = token
        setFrame(origin)
        window.alphaValue = reducedMotion ? 1 : 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        handle?.orderOut(nil)
        animate(window, frame: target, alpha: 1, duration: 0.22) { [weak self, weak window] in
            guard let self, let window, self.transitionID == token else { return }
            self.lastFrame = window.frame
            self.isTransitioning = false
            self.pendingExpansion = false
        }
    }

    func undock() {
        guard let window else { return }
        let edge = dockedEdge
        expand()
        dockedEdge = nil
        screenNumber = nil
        if let screen = window.screen {
            var frame = window.frame
            if edge == .left { frame.origin.x = screen.visibleFrame.minX + 48 }
            else { frame.origin.x = screen.visibleFrame.maxX - frame.width - 48 }
            setFrame(frame)
        }
    }

    private var canCollapse: Bool {
        guard let window else { return false }
        return window.attachedSheet == nil && NSApp.modalWindow == nil && !window.inLiveResize && !window.styleMask.contains(.fullScreen)
    }

    private var targetScreen: NSScreen? {
        if let screenNumber, let screen = NSScreen.screens.first(where: { Self.number($0) == screenNumber }) { return screen }
        return window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func number(_ screen: NSScreen) -> NSNumber? { screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }

    private func applyWindowLevel() {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal
        var behavior = originalBehavior ?? window.collectionBehavior
        if isPinned { behavior.remove(.moveToActiveSpace); behavior.insert(.canJoinAllSpaces) }
        window.collectionBehavior = behavior
    }

    /// Use the desktop work area so the menu bar and Dock stay clear.
    private func fitHeight(to screen: NSScreen) {
        guard let window else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.height = visible.height
        frame.origin.y = visible.minY
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        setFrame(frame)
    }

    private func setFrame(_ frame: CGRect) {
        guard let window else { return }
        adjustingFrame = true
        lastFrame = frame
        window.setFrame(frame, display: true)
        lastFrame = window.frame
        adjustingFrame = false
    }

    @objc private func windowMoved() {
        guard let window, !isTransitioning, !adjustingFrame, !isCollapsed, !window.inLiveResize, window.frame != lastFrame else { return }
        lastFrame = window.frame
        moveTask?.cancel()
        moveTask = Task { [weak self] in
            do {
                // AppKit moves title bars in its tracking loop. Wait until the drag has actually ended.
                repeat { try await Task.sleep(for: .milliseconds(150)) }
                while NSEvent.pressedMouseButtons & 1 != 0
                guard !Task.isCancelled else { return }
                self?.snapAfterMove()
            } catch { }
        }
    }

    private func snapAfterMove() {
        guard let window, window.isVisible, canCollapse, let screen = window.screen else { return }
        fitHeight(to: screen)
        guard let edge = SidebarGeometry.nearbyEdge(frame: window.frame, screen: screen.visibleFrame) else {
            dockedEdge = nil; screenNumber = nil
            return
        }
        dockedEdge = edge
        screenNumber = Self.number(screen)
        if autoCollapse && !isPinned { collapse(toward: edge) }
        else { setFrame(SidebarGeometry.dockedFrame(window.frame, screen: screen.visibleFrame, edge: edge)) }
    }

    @objc private func windowResignedKey() {
        guard !isCollapsed, dockedEdge != nil, autoCollapse, !isPinned else { return }
        resignTask?.cancel()
        resignTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard let self, let window = self.window, !window.isKeyWindow,
                      self.autoCollapse, !self.isPinned, self.canCollapse else { return }
                self.collapse(toward: self.dockedEdge)
            } catch { }
        }
    }

    @objc private func expandRequested() { expand() }
    @objc private func undockRequested() { undock() }
    @objc private func quickControlsRequested() {
        manualControls = true
        showQuickControls()
        quickPanel?.makeKeyAndOrderFront(nil)
    }
    @objc private func quickControlsResigned() {
        manualControls = false
        scheduleDismiss()
    }

    @objc private func screensChanged() {
        guard let window, let screen = targetScreen else { return }
        fitHeight(to: screen)
        guard let edge = dockedEdge else { return }
        screenNumber = Self.number(screen)
        setFrame(SidebarGeometry.dockedFrame(window.frame, screen: screen.visibleFrame, edge: edge))
        if isCollapsed, !showHandle(on: screen, edge: edge) { expand() }
    }

    @objc private func windowWillClose() { detach() }

    @discardableResult
    private func showHandle(on screen: NSScreen, edge: SidebarEdge) -> Bool {
        guard let window else { return false }
        let frame = SidebarGeometry.handleFrame(window: window.frame, screen: screen.visibleFrame, edge: edge)
        let panel: NSPanel
        if let handle { panel = handle }
        else {
            panel = EdgeRecoveryPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = L10n.text("展开侧伴")
            panel.isReleasedWhenClosed = false
            // Do not use AppKit's floating-panel lifecycle: it may hide utility panels with their app windows.
            panel.isFloatingPanel = false
            panel.hidesOnDeactivate = false
            panel.canHide = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = false
            handle = panel
        }
        let background = SidebarTrackingView(frame: CGRect(origin: .zero, size: frame.size))
        background.hoverChanged = { [weak self] inside in self?.handleHover(inside) }
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.roundedCornerRadius = 14
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        let button = RecoveryTabButton(frame: background.bounds)
        button.registerForDraggedTypes([.fileURL])
        button.receiveFiles = { [weak self] urls in
            guard let self, let workspace = self.workspace else { return false }
            let accepted = workspace.receiveFileURLs(urls)
            if accepted { self.expand() }
            return accepted
        }
        button.autoresizingMask = [.width, .height]
        button.title = ""
        button.imagePosition = .imageOnly
        button.contentTintColor = .controlAccentColor
        button.isBordered = false
        button.isTransparent = true
        button.target = self
        button.action = #selector(expandRequested)
        button.toolTip = L10n.text("点击展开侧伴")
        button.setAccessibilityLabel(L10n.text("展开侧伴侧栏"))
        let menu = NSMenu()
        for (title, action) in [(L10n.text("快捷控制"), #selector(quickControlsRequested)), (L10n.text("展开侧伴"), #selector(expandRequested)), (L10n.text("取消吸附"), #selector(undockRequested))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        button.menu = menu
        background.addSubview(button)
        // Labels remain visible even when neither timer nor recording is active.
        for (title, symbol, y, tint) in [
            (L10n.text("番茄钟"), "timer", CGFloat(110), NSColor.systemOrange),
            (L10n.text("录音"), "waveform", CGFloat(60), NSColor.systemRed),
            (L10n.text("笔记"), "square.and.pencil", CGFloat(10), NSColor.systemBlue)
        ] {
            let icon = SidebarStatusImage(frame: CGRect(x: 18, y: y + 20, width: 16, height: 16))
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            icon.contentTintColor = tint
            background.addSubview(icon)
            let label = SidebarTabLabel(labelWithString: title)
            label.frame = CGRect(x: 2, y: y + 2, width: 48, height: 14)
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            background.addSubview(label)
        }
        let timerImage = SidebarStatusImage(frame: CGRect(x: 39, y: 141, width: 9, height: 9))
        let recordingImage = SidebarStatusImage(frame: CGRect(x: 39, y: 91, width: 9, height: 9))
        background.addSubview(timerImage)
        background.addSubview(recordingImage)
        timerIcon = timerImage
        recordingIcon = recordingImage
        tabButton = button
        refreshIndicators()
        panel.contentView = background
        panel.minSize = frame.size
        panel.maxSize = frame.size
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        return panel.isVisible && !panel.frame.intersection(screen.visibleFrame).isEmpty
    }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func animate(_ window: NSWindow, frame: CGRect, alpha: CGFloat, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        if reducedMotion {
            window.setFrame(frame, display: true)
            window.alphaValue = alpha
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in completion() }
        }
    }

    private func beginStatusRefresh() {
        statusTask?.cancel()
        refreshIndicators()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.isCollapsed else { return }
                self.timer?.finishIfNeeded()
                self.refreshIndicators()
                if !self.manualControls && self.quickPanel?.isVisible == true && !self.pointerWithinControls { self.scheduleDismiss() }
            }
        }
    }

    private func refreshIndicators() {
        var description = [L10n.text("点击展开侧伴，悬浮显示快捷控制")]
        if let timer, timer.hasStarted, timer.seconds() > 0 {
            timerIcon?.isHidden = false
            let symbol = timer.isRunning ? (timer.isBreak ? "cup.and.saucer.fill" : "flame.fill") : "pause.circle.fill"
            timerIcon?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: timer.isBreak ? L10n.text("休息") : L10n.text("专注"))
            timerIcon?.contentTintColor = timer.isBreak ? .systemGreen : .systemOrange
            description.append(L10n.text("{0}{1} {2}", String(describing: timer.isBreak ? L10n.text("休息") : L10n.text("专注")), String(describing: timer.isRunning ? L10n.text("中") : L10n.text("已暂停")), String(describing: time(timer.seconds()))))
        } else { timerIcon?.isHidden = true }
        if let audio, audio.isRecording {
            recordingIcon?.isHidden = false
            recordingIcon?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: L10n.text("正在录音"))
            recordingIcon?.contentTintColor = .systemRed
            description.append(L10n.text("录音中 {0}", String(describing: time(Int(audio.elapsed)))))
            recordingIcon?.wantsLayer = true
            if reducedMotion { recordingIcon?.layer?.removeAnimation(forKey: "recordingPulse") }
            else if recordingIcon?.layer?.animation(forKey: "recordingPulse") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1; pulse.toValue = 0.35
                pulse.duration = 0.85; pulse.autoreverses = true; pulse.repeatCount = .infinity
                recordingIcon?.layer?.add(pulse, forKey: "recordingPulse")
            }
        } else {
            recordingIcon?.isHidden = true
            recordingIcon?.layer?.removeAllAnimations()
        }
        tabButton?.toolTip = description.joined(separator: "\n")
        tabButton?.setAccessibilityLabel(description.joined(separator: "，"))
    }

    private func time(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    private func handleHover(_ inside: Bool) {
        handleHovered = inside
        if inside {
            dismissTask?.cancel()
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, self.handleHovered else { return }
                self.showQuickControls()
            }
        } else { scheduleDismiss() }
    }

    private var pointerWithinControls: Bool {
        let point = NSEvent.mouseLocation
        return [handle, quickPanel].compactMap { $0 }.contains { panel in
            panel.isVisible && panel.frame.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, !self.manualControls, !self.pointerWithinControls else { return }
            self.hideQuickControls(animated: true)
        }
    }

    private func showQuickControls() {
        guard isCollapsed, !isTransitioning, let handle, let timer, let audio, let screen = targetScreen else { return }
        dismissTask?.cancel()
        let frame = SidebarGeometry.quickControlsFrame(handle: handle.frame, screen: screen.visibleFrame, edge: dockedEdge ?? .right)
        let panel: NSPanel
        if let quickPanel { panel = quickPanel }
        else {
            panel = QuickControlsPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = L10n.text("侧伴快捷控制")
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = false; panel.hidesOnDeactivate = false; panel.canHide = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            let background = SidebarTrackingView(frame: CGRect(origin: .zero, size: frame.size))
            background.material = .hudWindow; background.blendingMode = .withinWindow; background.state = .active
            background.wantsLayer = true; background.roundedCornerRadius = 14
            background.layer?.cornerRadius = 14; background.layer?.masksToBounds = true
            background.hoverChanged = { [weak self] inside in
                self?.controlsHovered = inside
                if inside { self?.manualControls = false }
                if inside { self?.dismissTask?.cancel() } else { self?.scheduleDismiss() }
            }
            let hosting = QuickControlsHostingView(rootView: SidebarQuickControls(timer: timer, audio: audio, didAct: { [weak self] in self?.refreshIndicators() }, expand: { [weak self] in self?.expand() }, dismiss: { [weak self] in self?.hideQuickControls(animated: true) }))
            hosting.frame = background.bounds
            hosting.autoresizingMask = [.width, .height]
            background.addSubview(hosting)
            panel.contentView = background
            panel.minSize = frame.size; panel.maxSize = frame.size
            quickPanel = panel
            NotificationCenter.default.addObserver(self, selector: #selector(quickControlsResigned), name: NSWindow.didResignKeyNotification, object: panel)
        }
        let token = UUID()
        quickTransitionID = token
        if !panel.isVisible {
            var origin = frame
            origin.origin.x += dockedEdge == .left ? -8 : 8
            panel.setFrame(origin, display: true)
            panel.alphaValue = reducedMotion ? 1 : 0
            panel.orderFrontRegardless()
            animate(panel, frame: frame, alpha: 1, duration: 0.16) { }
        } else {
            panel.orderFrontRegardless()
            animate(panel, frame: frame, alpha: 1, duration: 0.12) { }
        }
    }

    private func hideQuickControls(animated: Bool) {
        hoverTask?.cancel(); dismissTask?.cancel()
        handleHovered = false; controlsHovered = false; manualControls = false
        guard let panel = quickPanel else { return }
        let token = UUID()
        quickTransitionID = token
        guard animated, panel.isVisible else { panel.orderOut(nil); return }
        var target = panel.frame
        target.origin.x += dockedEdge == .left ? -8 : 8
        animate(panel, frame: target, alpha: 0, duration: 0.12) { [weak self, weak panel] in
            guard let self, self.quickTransitionID == token else { return }
            panel?.orderOut(nil)
        }
    }

}

private final class SidebarTabLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SidebarStatusImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class QuickControlsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class SidebarTrackingView: NSVisualEffectView {
    // The compositor draws the material separately from ordinary layer contents.
    // A layer cornerRadius alone can leave the material visible outside the corners.
    var roundedCornerRadius: CGFloat = 14 { didSet { needsLayout = true } }
    private var maskedSize: NSSize = .zero
    private var maskedRadius: CGFloat = -1
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0,
              maskedSize != bounds.size || maskedRadius != roundedCornerRadius else { return }
        maskedSize = bounds.size
        maskedRadius = roundedCornerRadius
        let radius = roundedCornerRadius
        maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
    }

    var hoverChanged: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
}

private final class QuickControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class EdgeRecoveryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RecoveryTabButton: NSButton {
    var receiveFiles: (([URL]) -> Bool)?
    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.cornerRadius = 14
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        return receiveFiles?(fileURLs(sender)) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Notification.Name {
    static let showSidebarRequested = Notification.Name("Sidebar.showWindowRequested")
}

struct SidebarWindowAccessor: NSViewRepresentable {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    let controller: SidebarWindowController
    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.controller = controller
        return view
    }
    func updateNSView(_ view: AccessorView, context: Context) {
        view.controller = controller
        if let window = view.window { controller.attach(window) }
    }
    // The controller belongs to the app. A SwiftUI view being detached must not close its recovery tab.
    // Actual cleanup is tied to NSWindow.willCloseNotification.

    final class AccessorView: NSView {
        weak var controller: SidebarWindowController?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { controller?.attach(window) }
        }
    }
}
