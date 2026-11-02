import AppKit

/// Check for Updates, the half with windows in it. The decisions are all in Updater.swift;
/// this asks GitHub, shows the answer, and runs the installer.
final class UpdateController: NSObject {
    static let shared = UpdateController()

    var preferences = UpdatePreferences(defaults: .standard)
    private let fetcher: UpdateFetching = URLSessionFetcher()

    private var checking = false
    private var installing = false
    private var quietPrompt: NSPanel?

    /// Set when the user chose "Relaunch Now"; acted on in `applicationWillTerminate`, so
    /// that a quit cancelled over unsaved work never leaves a relaunch armed for later.
    private(set) var pendingRelaunch: URL?

    // MARK: Checking

    @objc func checkForUpdates(_ sender: Any?) {
        check(userInitiated: true)
    }

    @objc func toggleAutomaticChecks(_ sender: Any?) {
        preferences.checksAutomatically.toggle()
    }

    /// Called once at launch. Late on purpose: the first seconds belong to whatever the
    /// user opened the app to do, and an answer that arrives then is the interruption this
    /// is meant not to be.
    func scheduleAutomaticCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, self.preferences.automaticCheckDue(now: Date()) else { return }
            // Recorded when tried, not when answered, so being offline means one attempt a
            // day rather than one every launch.
            self.preferences.lastCheck = Date()
            self.check(userInitiated: false)
        }
    }

    private func check(userInitiated: Bool) {
        guard !checking, !installing else { return }
        checking = true
        UpdateCheck.run(installed: BuildStamp.current.commit, fetcher: fetcher) { [weak self] result in
            guard let self = self else { return }
            self.checking = false
            switch result {
            case .success(.upToDate(let latest)):
                guard userInitiated else { return }
                let alert = NSAlert()
                alert.messageText = "Swash Paint is up to date"
                alert.informativeText = "This copy (\(BuildStamp.current.aboutVersion())) is the latest on GitHub"
                    + (latest.date.map { ", from \(BuildStamp.display($0))." } ?? ".")
                alert.runModal()
            case .success(let verdict):
                if userInitiated {
                    self.offer(verdict)
                } else {
                    self.offerQuietly(verdict)
                }
            case .failure(let error):
                // An automatic check that fails says nothing: it was never asked for.
                guard userInitiated else { return }
                let alert = NSAlert()
                alert.messageText = "Could not check for updates"
                alert.informativeText = error.message
                alert.runModal()
            }
        }
    }

    /// The change list as a dialog can hold it: the newest few, and a count of the rest.
    static func describe(_ verdict: UpdateVerdict) -> String {
        guard case let .available(latest, installedKnown, changes, total) = verdict else { return "" }
        var text = installedKnown ? "" : "This copy does not record which version it is, so it cannot say what changed.\n\n"
        if changes.isEmpty {
            if installedKnown { text += "Latest change: \(latest.subject)" }
            else { text += "Latest: \(latest.subject)" }
        } else {
            let shown = changes.prefix(12)
            text += "What changed:\n" + shown.map { "•  \($0)" }.joined(separator: "\n")
            let more = max(total, changes.count) - shown.count
            if more > 0 { text += "\n…and \(more) more" }
        }
        text += "\n\nUpdating builds the new version on this Mac, which takes a minute or two."
        return text
    }

    private func offer(_ verdict: UpdateVerdict) {
        guard case .available = verdict else { return }
        let alert = NSAlert()
        alert.messageText = "A new version of Swash Paint is available"
        alert.informativeText = UpdateController.describe(verdict)
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { beginUpdate() }
    }

    /// The automatic check's way of saying so: a small panel that never takes the focus,
    /// put up only when no button is held down and nothing modal is open, so it cannot
    /// land in the middle of a stroke or on top of a dialog.
    private func offerQuietly(_ verdict: UpdateVerdict, attempt: Int = 0) {
        let busy = NSEvent.pressedMouseButtons != 0 || NSApp.modalWindow != nil
            || NSApp.windows.contains { $0.attachedSheet != nil }
        if busy {
            // Give up after a few minutes of continuous busyness; tomorrow will ask again.
            guard attempt < 90 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.offerQuietly(verdict, attempt: attempt + 1)
            }
            return
        }
        quietPrompt?.close()
        let panel = QuietUpdatePanel(verdict: verdict) { [weak self] wantsUpdate in
            self?.quietPrompt?.close()
            self?.quietPrompt = nil
            if wantsUpdate { self?.offer(verdict) }
        }
        quietPrompt = panel
        panel.orderFront(nil)
    }

    // MARK: Updating

    private func beginUpdate() {
        guard !installing else { return }
        guard let destination = UpdateInstall.destination(forBundle: Bundle.main.bundleURL) else {
            return failNow("Swash Paint cannot tell which folder it was installed in, so it cannot update itself. "
                           + "Run the install command in Terminal instead:\n\n    \(GitHub.installCommand)",
                           title: "Swash Paint cannot update itself here")
        }
        if let problem = UpdateInstall.destinationProblem(destination: destination,
                                                          isWritable: FileManager.default.isWritableFile(atPath:)) {
            return failNow(problem, title: "Swash Paint cannot be replaced where it is")
        }
        guard UpdateController.commandLineToolsPresent() else {
            let alert = NSAlert()
            alert.messageText = "The command line tools are needed"
            alert.informativeText = UpdateInstall.commandLineToolsMessage
            alert.addButton(withTitle: "Install the Tools…")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                // Apple's own installer dialog; it asks the user itself.
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["--install"])
            }
            return
        }

        installing = true
        let progress = UpdateProgressWindow()
        let host = NSApp.mainWindow ?? NSApp.keyWindow
        if let host = host, host.attachedSheet == nil {
            host.beginSheet(progress)
        } else {
            progress.center()
            progress.makeKeyAndOrderFront(nil)
        }
        progress.show(.fetching)

        fetchInstaller { [weak self] script, error in
            guard let self = self else { return }
            guard let script = script else {
                self.finish(progress: progress, host: host)
                self.failNow(error ?? "The installer could not be downloaded.", title: "The update did not install")
                return
            }
            self.runInstaller(script, destination: destination, progress: progress, host: host)
        }
    }

    /// `xcode-select -p` fails, quietly, when there are no developer tools at all. Asking
    /// `swiftc` instead would be wrong: /usr/bin/swiftc exists either way, as a stub that
    /// puts up Apple's install dialog.
    static func commandLineToolsPresent() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// The same install.sh the README's one-line command runs, fetched the same way.
    /// SWASHPAINT_INSTALLER, a local path, stands in for it when testing an installer that is
    /// not on GitHub yet; nothing in the app sets it.
    private func fetchInstaller(_ done: @escaping (URL?, String?) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swashpaint-update-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("install.sh")
        try? FileManager.default.removeItem(at: target)
        if let local = ProcessInfo.processInfo.environment["SWASHPAINT_INSTALLER"], !local.isEmpty {
            do {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: local), to: target)
                done(target, nil)
            } catch {
                done(nil, "SWASHPAINT_INSTALLER could not be read: \(error.localizedDescription)")
            }
            return
        }
        fetcher.fetch(GitHub.installerURL) { result in
            switch result {
            case .ok(let data) where (try? data.write(to: target)) != nil:
                done(target, nil)
            case .ok:
                done(nil, "The installer could not be saved to \(dir.path).")
            case .status(let code):
                done(nil, "GitHub answered with an error (HTTP \(code)) for the installer. Try again later.")
            case .failed(let why):
                done(nil, "GitHub could not be reached (\(why)). Check the connection and try again.")
            }
        }
    }

    private func runInstaller(_ script: URL, destination: URL, progress: UpdateProgressWindow, host: NSWindow?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = UpdateInstall.environment(base: ProcessInfo.processInfo.environment,
                                                        destination: destination)
        process.currentDirectoryURL = script.deletingLastPathComponent()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        var log = ""
        var pending = ""
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                log += chunk
                pending += chunk
                while let nl = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<nl])
                    pending = String(pending[pending.index(after: nl)...])
                    if let phase = UpdateInstall.phase(forLine: line) { progress.show(phase) }
                }
            }
        }
        process.terminationHandler = { p in
            // Whatever is still in the pipe, then the verdict, both on the main queue so
            // they arrive after every chunk the handler already queued.
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { [weak self] in
                log += String(decoding: rest, as: UTF8.self)
                self?.installerFinished(status: p.terminationStatus, log: log, destination: destination,
                                        progress: progress, host: host)
            }
        }
        do {
            try process.run()
        } catch {
            finish(progress: progress, host: host)
            failNow("The installer could not be started: \(error.localizedDescription)",
                    title: "The update did not install")
        }
    }

    private func installerFinished(status: Int32, log: String, destination: URL,
                                   progress: UpdateProgressWindow, host: NSWindow?) {
        finish(progress: progress, host: host)
        let logURL = UpdateInstall.logURL
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? log.write(to: logURL, atomically: true, encoding: .utf8)

        if UpdateInstall.succeeded(status: status, log: log) {
            let app = UpdateInstall.installedApp(in: destination)
            let tests = log.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasSuffix("failed") && $0.contains("passed") }
            let alert = NSAlert()
            alert.messageText = "Swash Paint is updated"
            alert.informativeText = "The new version was built on this Mac"
                + (tests.map { ", passed its self-test (\($0))," } ?? "")
                + " and installed in \(destination.path). It takes over when Swash Paint next opens."
            alert.addButton(withTitle: "Relaunch Now")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                pendingRelaunch = app
                NSApp.terminate(nil)
                // Only reached when the quit was cancelled, over unsaved work: the
                // relaunch must not fire at some later, unrelated quit.
                pendingRelaunch = nil
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The update did not install"
        alert.informativeText = UpdateInstall.failureMessage(log: log, status: status)
            + "\n\nThe copy of Swash Paint you are using has not been changed."
        alert.addButton(withTitle: "Show Log")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(logURL)
        }
    }

    private func finish(progress: UpdateProgressWindow, host: NSWindow?) {
        installing = false
        if let parent = progress.sheetParent { parent.endSheet(progress) } else { progress.orderOut(nil) }
    }

    private func failNow(_ message: String, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Install Command")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(GitHub.installCommand, forType: .string)
        }
    }

    /// From `applicationWillTerminate`: hand the relaunch to a shell that outlives us.
    func relaunchIfPending() {
        guard let app = pendingRelaunch else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = UpdateInstall.relaunchArguments(pid: getpid(), app: app)
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// The progress sheet: four steps, the current one named, and a bar that moves by step.
/// The installer cannot report finer progress than that, and a bar that pretended to
/// would be lying about a build that might take twenty seconds or three minutes.
final class UpdateProgressWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let spinner = NSProgressIndicator()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 132),
                   styleMask: [.titled], backing: .buffered, defer: false)
        title = "Updating Swash Paint"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 132))
        let heading = NSTextField(labelWithString: "Updating Swash Paint")
        heading.font = .boldSystemFont(ofSize: 13)
        heading.frame = NSRect(x: 20, y: 96, width: 360, height: 18)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.frame = NSRect(x: 20, y: 68, width: 16, height: 16)
        spinner.startAnimation(nil)
        label.frame = NSRect(x: 44, y: 67, width: 336, height: 18)
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(UpdateInstall.Phase.allCases.count)
        bar.frame = NSRect(x: 20, y: 42, width: 360, height: 16)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.stringValue = "Building on this Mac takes a minute or two. You can keep drawing in other windows."
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        detail.frame = NSRect(x: 20, y: 6, width: 360, height: 30)
        for v in [heading, spinner, label, bar, detail] { content.addSubview(v) }
        contentView = content
    }

    func show(_ phase: UpdateInstall.Phase) {
        let n = UpdateInstall.Phase.allCases.count
        label.stringValue = "\(phase.title)…  (step \(phase.rawValue + 1) of \(n))"
        bar.doubleValue = Double(phase.rawValue) + 0.5
    }
}

/// What the automatic check puts up: a floating panel that does not take the focus, so a
/// key press meant for the canvas still reaches the canvas.
final class QuietUpdatePanel: NSPanel {
    private let decide: (Bool) -> Void

    init(verdict: UpdateVerdict, decide: @escaping (Bool) -> Void) {
        self.decide = decide
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
                   styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Swash Paint"
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        let heading = NSTextField(labelWithString: "A new version of Swash Paint is available.")
        heading.font = .boldSystemFont(ofSize: 12)
        heading.frame = NSRect(x: 16, y: 64, width: 290, height: 18)
        var line = ""
        if case let .available(latest, _, changes, total) = verdict {
            let count = max(total, changes.count)
            line = count > 1 ? "\(count) changes, the latest: \(changes.first ?? latest.subject)"
                             : (changes.first ?? latest.subject)
        }
        let sub = NSTextField(labelWithString: line)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: 16, y: 44, width: 290, height: 16)
        let later = NSButton(title: "Later", target: self, action: #selector(laterPressed))
        later.frame = NSRect(x: 128, y: 8, width: 80, height: 28)
        let more = NSButton(title: "Update…", target: self, action: #selector(updatePressed))
        more.frame = NSRect(x: 214, y: 8, width: 94, height: 28)
        for v in [heading, sub, later, more] { content.addSubview(v) }
        contentView = content
        // Top right of the screen the user is on, out of the way of the canvas's centre.
        if let screen = NSScreen.main?.visibleFrame {
            setFrameTopLeftPoint(NSPoint(x: screen.maxX - frame.width - 20, y: screen.maxY - 20))
        }
    }

    @objc private func laterPressed() { decide(false) }
    @objc private func updatePressed() { decide(true) }
}

/// The toggle carries a tick that has to match the saved setting every time the menu
/// opens, and Check for Updates greys out while a check or an install is running rather
/// than starting a second one.
extension UpdateController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleAutomaticChecks(_:)):
            item.state = preferences.checksAutomatically ? .on : .off
            return true
        case #selector(checkForUpdates(_:)):
            return !checking && !installing
        default:
            return true
        }
    }
}
