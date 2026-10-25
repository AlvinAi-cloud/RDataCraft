// RDataCraft's macOS host. Application code is GPL-3.0.
// AppKit owns the window, menus, document dialogs, and the bundled R process.
import Cocoa
import WebKit
import UniformTypeIdentifiers
import Darwin
import PDFKit

enum HostError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let text) = self { return text }; return nil }
}

@MainActor
final class RDataCraftApp: NSObject, NSApplicationDelegate {
    var windows: [RDataCraftWindow] = []
    var launched = false
    var pendingFiles: [URL] = []
    var quitting = false
    var quitQueue: [RDataCraftWindow] = []
    var testQuitReply: ((Bool) -> Void)?
    var testFolder: URL? {
        let prefixes=["--multiwindow-test=","--studio-test=","--workflow-test=","--smoke-test=","--navigator-test=","--paste-test=","--graph-test="]
        guard let flag=CommandLine.arguments.first(where:{value in prefixes.contains(where:{value.hasPrefix($0)})}) else {return nil}
        return URL(fileURLWithPath:String(flag.split(separator:"=",maxSplits:1)[1]),isDirectory:true)
    }
    var activeWindow: RDataCraftWindow? { (NSApp.keyWindow?.delegate as? RDataCraftWindow) ?? windows.last }
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular);NSApp.appearance=NSAppearance(named:.aqua)
        launched=true
        if pendingFiles.isEmpty {_ = openWindow(runChecks:true)}
        else {let files=pendingFiles;pendingFiles=[];for file in files {_ = openProjectFile(file)}}
    }
    @discardableResult
    func openWindow(newStudy:Bool=false,file:URL?=nil,runChecks:Bool=false) -> RDataCraftWindow {
        if quitting {cancelQuit()}
        let previous=activeWindow?.window?.frame
        let controller=RDataCraftWindow();controller.coordinator=self
        controller.startsNewStudy=newStudy;controller.runsAutomatedChecks=runChecks
        if let file=file {controller.pendingFiles=[file];controller.requestedProject=file}
        windows.append(controller);controller.start()
        if testFolder == nil,let frame=previous {
            _ = controller.window.cascadeTopLeft(from:NSPoint(x:frame.minX+24,y:frame.maxY-24))
        }
        return controller
    }
    @discardableResult
    func openProjectFile(_ file:URL) -> RDataCraftWindow {
        let path=file.standardizedFileURL.path
        if let existing=windows.first(where:{($0.currentProject ?? $0.requestedProject)?.standardizedFileURL.path==path && !$0.stopping}) {
            if testFolder == nil {existing.window.makeKeyAndOrderFront(nil)}
            return existing
        }
        if let welcome=windows.first(where:{!$0.hasDocument && !$0.startsNewStudy && $0.requestedProject==nil && $0.pendingFiles.isEmpty && !$0.stopping}) {
            welcome.handleFile(file)
            if testFolder == nil {welcome.window.makeKeyAndOrderFront(nil)}
            return welcome
        }
        return openWindow(file:file)
    }
    func removeWindow(_ controller:RDataCraftWindow) {
        windows.removeAll(where:{$0 === controller})
        if let survivor=windows.last {
            survivor.makeMenus()
            if testFolder == nil {survivor.window.makeKeyAndOrderFront(nil)}
        }
    }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        let files=filenames.map{URL(fileURLWithPath:$0)}
        if !launched {pendingFiles.append(contentsOf:files)}
        else {
            for file in files {
                if ["json","rdatacraft","plotcraft"].contains(file.pathExtension.lowercased()) {_ = openProjectFile(file)}
                else if let active=activeWindow {active.handleFile(file)}
                else {_ = openWindow(file:file)}
            }
        }
        sender.reply(toOpenOrPrint:.success)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        if let current=activeWindow {current.window.makeKeyAndOrderFront(nil)} else {_ = openWindow()}
        return true
    }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if quitting {return .terminateLater}
        if !windows.contains(where:{$0.window.isDocumentEdited}) {return .terminateNow}
        quitting=true;quitQueue=windows
        Task {@MainActor in self.reviewNextQuitWindow()}
        return .terminateLater
    }
    func finishQuit(_ allow:Bool) {
        quitting=false;quitQueue=[]
        for controller in windows {controller.waitingToQuit=false}
        if testFolder != nil,let reply=testQuitReply {reply(allow)}
        else {NSApp.reply(toApplicationShouldTerminate:allow)}
    }
    func cancelQuit() {if quitting {finishQuit(false)}}
    func reviewNextQuitWindow() {
        guard quitting else {return}
        while !quitQueue.isEmpty {
            let controller=quitQueue.removeFirst()
            if controller.stopping || !controller.window.isDocumentEdited {continue}
            if testFolder == nil {controller.window.makeKeyAndOrderFront(nil)}
            switch controller.saveAlert() {
            case .alertFirstButtonReturn:controller.waitingToQuit=true;controller.saveProject();return
            case .alertSecondButtonReturn:continue
            default:finishQuit(false);return
            }
        }
        finishQuit(true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {windows.isEmpty}
    func stopAll() {for controller in windows {controller.stopEngine()}}
    func applicationWillTerminate(_ notification:Notification) {stopAll()}
}

@MainActor
final class RDataCraftWindow: NSObject, NSWindowDelegate,
    WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, NSMenuItemValidation {
    var window: NSWindow!
    var webView: WKWebView!
    var loading: NSView!
    var process: Process?
    var pipe: Pipe?
    var logHandle: FileHandle?
    var endpoint: URL!
    var hasDocument = false
    weak var coordinator: RDataCraftApp?
    let identifier = UUID().uuidString
    var startsNewStudy = false
    var runsAutomatedChecks = true
    var requestedProject: URL?
    var testAlertResponses: [NSApplication.ModalResponse] = []
    var ready = false
    var stopping = false
    var allowClose = false
    var waitingToQuit = false
    var studyName = "RDataCraft"
    var currentProject: URL?
    var pendingFiles: [URL] = []
    var forceSaveAs = false
    var afterSaving: (() -> Void)?
    var downloads: [ObjectIdentifier: (download: WKDownload, temporary: URL, target: URL, project: Bool)] = [:]
    var nextTestDestination: URL?
    var testClipboard: [[(NSPasteboard.PasteboardType,Data)]]?
    let fm = FileManager.default
    let started = Date()
    var testFolder: URL? {
        runsAutomatedChecks ? coordinator?.testFolder : nil
    }
    var isAutomatedSession: Bool { coordinator?.testFolder != nil }
    var backend: URL { Bundle.main.resourceURL!.appendingPathComponent("RDataCraft", isDirectory: true) }
    var temporaryFolder: URL { fm.temporaryDirectory.appendingPathComponent("RDataCraft-\(ProcessInfo.processInfo.processIdentifier)-\(identifier)", isDirectory: true) }

    func start() {
        makeWindow()
        makeMenus()
        do { try startEngine() } catch { fail(error.localizedDescription) }
    }

    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 870),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "RDataCraft"
        window.minSize = NSSize(width: 980, height: 680)
        window.backgroundColor = NSColor(red: 0.945, green: 0.96, blue: 0.95, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !isAutomatedSession {
            window.setFrameAutosaveName("RDataCraft.workspace")
            if !window.setFrameUsingName("RDataCraft.workspace") { window.center() }
        } else { window.center() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "rdatacraft")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.isHidden = true
        window.contentView!.addSubview(webView)
        loading = NSView(frame: window.contentView!.bounds)
        loading.autoresizingMask = [.width, .height]
        let title = NSTextField(labelWithString: "RDataCraft")
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.textColor = NSColor(red: 0.14, green: 0.47, blue: 0.39, alpha: 1)
        let subtitle = NSTextField(labelWithString: "Starting your local scientific workspace…")
        subtitle.textColor = .secondaryLabelColor
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let stack = NSStackView(views: [title, subtitle, spinner])
        stack.orientation = .vertical; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        loading.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: loading.centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: loading.centerYAnchor)])
        window.contentView!.addSubview(loading)
        if !isAutomatedSession {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.ignoresMouseEvents = true
            window.orderBack(nil)
        }
    }

    func makeMenus() {
        let bar = NSMenu()
        func menu(_ name: String) -> NSMenu { let item = NSMenuItem(); item.submenu = NSMenu(title: name); bar.addItem(item); return item.submenu! }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        let app = menu("RDataCraft")
        add(app, "About RDataCraft", #selector(about))
        app.addItem(.separator())
        add(app, "Hide RDataCraft", #selector(NSApplication.hide(_:)), "h")
        app.items.last?.target = NSApp
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.items.last?.target = NSApp
        app.addItem(.separator())
        add(app, "Quit RDataCraft", #selector(NSApplication.terminate(_:)), "q")
        app.items.last?.target = NSApp
        let file = menu("File")
        add(file, "New Study…", #selector(newProject), "n")
        add(file, "Open Project…", #selector(openProject), "o")
        add(file, "Import Data…", #selector(importData), "i")
        add(file, "Import Prism File…", #selector(importPrism))
        file.addItem(.separator())
        add(file, "Save", #selector(saveProject), "s")
        add(file, "Save As…", #selector(saveAs), "s", [.command, .shift])
        file.addItem(.separator())
        add(file, "Export Figure as SVG…", #selector(exportSVG), "e")
        add(file, "Export Figure as PDF…", #selector(exportPDF))
        add(file, "Export Figure as PNG…", #selector(exportPNG))
        add(file, "Export Layout as PDF…", #selector(exportLayoutPDF))
        file.addItem(.separator())
        add(file, "Close Window", #selector(closeWindow), "w")
        let edit = menu("Edit")
        add(edit, "Undo", #selector(undoEdit), "z")
        add(edit, "Redo", #selector(redoEdit), "z", [.command, .shift])
        for (name, selector, key) in [("Cut", "cut:", "x")] {
            let item = NSMenuItem(title: name, action: Selector(selector), keyEquivalent: key)
            item.keyEquivalentModifierMask = name == "Redo" ? [.command, .shift] : .command
            edit.addItem(item)
        }
        add(edit, "Copy", #selector(copyEdit), "c")
        add(edit, "Paste", #selector(pasteEdit), "v")
        let selectAll=NSMenuItem(title:"Select All",action:Selector(("selectAll:")),keyEquivalent:"a")
        selectAll.keyEquivalentModifierMask = .command; edit.addItem(selectAll)
        edit.addItem(.separator())
        add(edit, "Copy Graph as Vector", #selector(copyVector), "c", [.command,.shift])
        let view = menu("View")
        add(view, "Data Table", #selector(showData), "1")
        add(view, "Analysis", #selector(showAnalysis), "2")
        add(view, "Graph", #selector(showFigure), "3")
        add(view, "Project Information", #selector(showProject), "4")
        add(view, "Figure Layout", #selector(showLayout), "5")
        view.addItem(.separator())
        add(view, "Figure Settings", #selector(toggleInspector), "i", [.command, .option])
        let ai = menu("AI")
        add(ai,"AI Assistant",#selector(toggleAssistant),"a",[.command,.option])
        add(ai,"Accounts and Models…",#selector(showAIAccounts))
        let win = menu("Window")
        add(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"); win.items.last?.target = nil
        add(win, "Zoom", #selector(NSWindow.performZoom(_:))); win.items.last?.target = nil
        NSApp.windowsMenu = win
        let help = menu("Help")
        add(help, "Examples & Analysis Guide…", #selector(showExamples))
        add(help, "RDataCraft Help…", #selector(showHelp), "?")
        add(help, "Show Engine Log", #selector(showLog))
        NSApp.mainMenu = bar
    }

    func unusedPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw HostError.failed("Could not create a local engine socket.") }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw HostError.failed("Could not reserve a local engine port.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard result == 0 else { throw HostError.failed("Could not determine the engine port.") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    func startEngine() throws {
        try fm.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        let log = logURL()
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: log.path, contents: nil)
        logHandle = try FileHandle(forWritingTo: log)
        endpoint = URL(string: "http://127.0.0.1:\(try unusedPort())/")!
        let worker = Process()
        worker.executableURL = backend.appendingPathComponent("scripts/rscript.sh")
        worker.arguments = ["scripts/run.R", "--no-browser", "--port=\(endpoint.port!)"]
        worker.currentDirectoryURL = backend
        var environment = ProcessInfo.processInfo.environment
        environment["RDATACRAFT_DESKTOP"] = "1"
        environment["RDATACRAFT_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        if isAutomatedSession { environment["RDATACRAFT_USER_LIBRARY"] = coordinator!.testFolder!.appendingPathComponent("optional-R-library").path }
        worker.environment = environment
        let output = Pipe()
        worker.standardOutput = output; worker.standardError = output
        worker.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { try? self?.logHandle?.write(contentsOf: data) }
        }
        worker.terminationHandler = { [weak self] worker in
            DispatchQueue.main.async {
                guard let self = self, !self.stopping else { return }
                self.fail("The local R engine stopped (exit \(worker.terminationStatus)). See Help → Show Engine Log.")
            }
        }
        pipe = output; process = worker
        try worker.run()
        Task { await waitForEngine() }
    }

    func waitForEngine() async {
        let deadline = Date().addingTimeInterval(60)
        while !stopping && Date() < deadline {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                webView.load(URLRequest(url: endpoint))
                Task {
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    if !ready && !stopping { fail("The interface did not finish connecting to the R engine.") }
                }
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if !stopping { fail("The bundled R engine did not become ready within 60 seconds.") }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.host == "127.0.0.1", origin.port == endpoint?.port,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            guard !ready else { return }
            ready = true; loading.isHidden = true; webView.isHidden = false
            window.makeFirstResponder(webView)
            if let first = pendingFiles.first { pendingFiles.removeAll(); handleFile(first) }
            else if startsNewStudy { startsNewStudy = false; send(["type":"new"]) }
            if testFolder != nil {
                testClipboard=(NSPasteboard.general.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } }
                Task { await smokeTest() }
            }
        case "document":
            hasDocument = body["open"] as? Bool ?? true
            if hasDocument { requestedProject = nil }
            window.isDocumentEdited = body["dirty"] as? Bool ?? false
            if let path = body["path"] as? String { currentProject = path.isEmpty ? nil : URL(fileURLWithPath: path) }
            window.representedURL = currentProject
            studyName = body["name"] as? String ?? "Untitled study"
            window.title = (hasDocument ? "\(studyName) — RDataCraft" : "RDataCraft") + (isAutomatedSession ? " [Automated checks]" : "")
            if !window.isDocumentEdited, let action = afterSaving { afterSaving = nil; action() }
            if !window.isDocumentEdited && waitingToQuit { waitingToQuit = false; coordinator?.reviewNextQuitWindow() }
        case "command":
            switch body["name"] as? String {
            case "new": newProject()
            case "open": openProject()
            case "import": importData()
            default: break
            }
        case "vector": copyVectorPayload(body)
        case "error": logText("Interface: \(body["message"] ?? "unknown error")\n")
        default: break
        }
    }

    func send(_ message: [String: Any]) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: message), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.RDataCraftDesktop.receive(\(json))") { [weak self] _, error in
            if let error = error { self?.logText("Command failed: \(error.localizedDescription)\n") }
        }
    }
    func command(_ name: String) { send(["type": "command", "name": name]) }
    @objc func undoEdit() { command("undo") }
    @objc func redoEdit() { command("redo") }
    @objc func copyVector() { command("copy-vector") }
    @objc func copyEdit() {
        Task { @MainActor in
            if (try? await webView.evaluateJavaScript("window.RDataCraftGraph?.copyIfGraph() === true")) as? Bool == true {return}
            if window.firstResponder?.tryToPerform(#selector(NSText.copy(_:)),with:self) != true {NSApp.sendAction(#selector(NSText.copy(_:)),to:nil,from:self)}
        }
    }
    func copyVectorPayload(_ payload: [String:Any]) {
        guard let encoded = payload["pdf"] as? String, encoded.utf8.count < 60_000_000,
              let pdf = Data(base64Encoded:encoded,options:.ignoreUnknownCharacters), pdf.starts(with:Array("%PDF".utf8)),
              let document = PDFDocument(data:pdf), document.pageCount == 1,
              let svg = payload["svg"] as? String, svg.utf8.count < 40_000_000, svg.contains("<svg"),
              let svgData = svg.data(using:.utf8) else {
            send(["type":"vector-result","ok":false,"message":"The graph could not be copied as vector data."]);return
        }
        let item = NSPasteboardItem()
        item.setData(pdf,forType:.pdf)
        item.setData(svgData,forType:NSPasteboard.PasteboardType("public.svg-image"))
        NSPasteboard.general.clearContents()
        let ok = NSPasteboard.general.writeObjects([item])
        send(["type":"vector-result","ok":ok,"message":ok ? "Vector graph copied." : "The clipboard could not be updated."])
    }
    @objc func pasteEdit() {
        // Read the system clipboard only in response to the user's Paste action.
        // Text fields elsewhere continue through the native responder chain.
        Task { @MainActor in
            let inGrid = try? await webView.evaluateJavaScript("!!document.activeElement?.closest('#data_grid') && !!document.querySelector('#nav_data.active')")
            if inGrid as? Bool == true, let text = NSPasteboard.general.string(forType: .string),
               let data = try? JSONSerialization.data(withJSONObject: [text]), let json = String(data: data, encoding: .utf8),
               let consumed = try? await webView.evaluateJavaScript("window.RDataCraftGrid.pasteNative((\(json))[0])"), consumed as? Bool == true { return }
            if window.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: self) != true {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            }
        }
    }
    @objc func showData() { command("data") }
    @objc func showAnalysis() { command("analysis") }
    @objc func showFigure() { command("figure") }
    @objc func showLayout() { command("layout") }
    @objc func exportLayoutPDF() { command("export-layout-pdf") }
    @objc func showProject() { command("project") }
    @objc func showAIAccounts() { command("ai-accounts") }
    @objc func toggleAssistant() { command("assistant") }
    @objc func toggleInspector() { command("inspector") }
    @objc func exportSVG() { command("export-svg") }
    @objc func exportPDF() { command("export-pdf") }
    @objc func exportPNG() { command("export-png") }
    @objc func closeWindow() { window.performClose(nil) }
    @objc func saveProject() { forceSaveAs = false; command("save") }
    @objc func saveAs() { forceSaveAs = true; command("save") }
    @objc func newProject() { _ = coordinator?.openWindow(newStudy:true) }
    @objc func openProject() {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.json, UTType(filenameExtension: "rdatacraft") ?? .json, UTType(filenameExtension: "plotcraft") ?? .json]
            panel.message = "Open a RDataCraft project"
            panel.beginSheetModal(for: self.window) { result in
                if result == .OK { for url in panel.urls { _ = self.coordinator?.openProjectFile(url) } }
            }
    }
    @objc func importData() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["csv", "tsv", "txt", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Import data into the active worksheet"
        panel.beginSheetModal(for: window) { [weak self] result in
            if result == .OK, let url = panel.url { self?.send(["type": "import", "path": url.path]); self?.showData() }
        }
    }
    @objc func importPrism() {
        let panel=NSOpenPanel();panel.allowsMultipleSelection=false
        panel.allowedContentTypes=["prism","pzfx","pzf"].compactMap{UTType(filenameExtension:$0)}
        panel.message="Import supported Prism source tables with a preview"
        panel.beginSheetModal(for:window) { [weak self] result in
            if result == .OK,let file=panel.url {self?.send(["type":"prism","path":file.path])}
        }
    }
    func handleFile(_ url: URL) {
        if ["json","rdatacraft","plotcraft"].contains(url.pathExtension.lowercased()) { requestedProject = url }
        guard ready else { pendingFiles.append(url); return }
        if ["csv", "tsv", "txt", "xlsx"].contains(url.pathExtension.lowercased()) {
            send(["type": "import", "path": url.path]); showData()
        } else if ["prism","pzfx","pzf"].contains(url.pathExtension.lowercased()) {
            send(["type":"prism","path":url.path])
        } else { send(["type": "open", "path": url.path]) }
    }
    func windowDidBecomeKey(_ notification: Notification) { makeMenus() }
    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName:"rdatacraft")
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        stopEngine()
        coordinator?.removeWindow(self)
    }

    func confirmChanges(_ action: @escaping () -> Void) {
        guard window.isDocumentEdited else { action(); return }
        switch saveAlert() {
        case .alertFirstButtonReturn: afterSaving = action; saveProject()
        case .alertSecondButtonReturn: action()
        default: break
        }
    }
    func saveAlert() -> NSApplication.ModalResponse {
        if isAutomatedSession && !testAlertResponses.isEmpty { return testAlertResponses.removeFirst() }
        let alert = NSAlert()
        alert.messageText = "Save changes to this RDataCraft project?"
        alert.informativeText = "\(studyName) has unsaved data, analysis options, or figure settings."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Don't Save"); alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if coordinator?.quitting == true { return false }
        if allowClose || !sender.isDocumentEdited { return true }
        switch saveAlert() {
        case .alertFirstButtonReturn: afterSaving = { [weak self] in self?.allowClose = true; self?.window.close() }; saveProject(); return false
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
    func stopEngine() {
        guard !stopping else { return }
        if let saved=testClipboard {
            NSPasteboard.general.clearContents()
            let items=saved.map { entries -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in entries {item.setData(data,forType:type)};return item }
            NSPasteboard.general.writeObjects(items);testClipboard=nil
        }
        stopping = true
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let process = process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        try? logHandle?.close()
        try? fm.removeItem(at: temporaryFolder)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.host == "127.0.0.1" && url.port == endpoint.port {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else {
            if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let headers = (response.response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        let attachment = headers.contains { "\($0.key)".lowercased() == "content-disposition" && "\($0.value)".lowercased().contains("attachment") }
        decisionHandler(attachment || !response.canShowMIMEType ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { result in completionHandler(result == .OK ? panel.urls : nil) }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename name: String, completionHandler: @escaping (URL?) -> Void) {
        let project = name.hasSuffix(".rdatacraft") || name.hasSuffix(".rdatacraft.json")
        func destination(_ target: URL?) {
            guard let target = target else {
                forceSaveAs = false; afterSaving = nil
                if waitingToQuit { waitingToQuit = false; coordinator?.cancelQuit() }
                completionHandler(nil); return
            }
            if project, coordinator?.windows.contains(where:{other in other !== self && other.currentProject?.standardizedFileURL == target.standardizedFileURL}) == true {
                cancelSave();completionHandler(nil)
                fail("That project is already open in another window. Switch to that window, or save this study with a different name.")
                return
            }
            let temporary = temporaryFolder.appendingPathComponent(UUID().uuidString)
            downloads[ObjectIdentifier(download)] = (download, temporary, target, project)
            forceSaveAs = false; completionHandler(temporary)
        }
        if let target = nextTestDestination { nextTestDestination = nil; destination(target); return }
        if project, !forceSaveAs, let current = currentProject { destination(current); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project ? (currentProject?.lastPathComponent ?? name) : name
        panel.canCreateDirectories = true
        panel.allowedContentTypes = project ? [UTType(filenameExtension: "rdatacraft") ?? .json, .json] : [UTType(filenameExtension: (name as NSString).pathExtension) ?? .data]
        panel.message = project ? "Save all worksheets, analyses, and figure settings together" : "Export the selected output"
        panel.beginSheetModal(for: window) { result in destination(result == .OK ? panel.url : nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        do {
            let data = try Data(contentsOf: transfer.temporary)
            try data.write(to: transfer.target, options: .atomic)
            try? fm.removeItem(at: transfer.temporary)
            if transfer.project {
                currentProject = transfer.target
                send(["type": "saved", "path": transfer.target.path])
            }
            logText("Saved \(transfer.target.lastPathComponent)\n")
        } catch { cancelSave(); fail("Could not save the file: \(error.localizedDescription)") }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let transfer = downloads.removeValue(forKey: ObjectIdentifier(download)) { try? fm.removeItem(at: transfer.temporary) }
        cancelSave()
        if (error as NSError).code != NSURLErrorCancelled { fail("The file could not be exported. Check the analysis and figure settings.\n\(error.localizedDescription)") }
    }
    func cancelSave() { forceSaveAs = false; afterSaving = nil; if waitingToQuit { waitingToQuit = false; coordinator?.cancelQuit() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("The interface process stopped. Reopen RDataCraft to start a new session.") }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if [#selector(about),#selector(showHelp),#selector(showLog)].contains(menuItem.action) { return true }
        if [#selector(saveProject),#selector(saveAs),#selector(exportSVG),#selector(exportPDF),#selector(exportPNG),#selector(exportLayoutPDF),#selector(showData),#selector(showAnalysis),#selector(showFigure),#selector(showLayout),#selector(toggleInspector),#selector(copyVector)].contains(menuItem.action) { return ready && hasDocument }
        return ready
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RDataCraft", .applicationVersion: "v0.32 · Development preview", .credits: NSAttributedString(string: "Scientific plotting and statistics\nR-powered data analysis and publication-ready figures.\nAvailable for Mac and Windows.")])
    }
    @objc func showExamples() { send(["type":"examples"]) }
    @objc func showHelp() {
        if ready { send(["type":"command","name":"help"]) }
        else { NSWorkspace.shared.open(backend.appendingPathComponent("examples/RDataCraft help.html")) }
    }
    @objc func showLog() { NSWorkspace.shared.open(logURL()) }
    func logURL() -> URL { fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/RDataCraft/engine-\(ProcessInfo.processInfo.processIdentifier)-\(identifier).log") }
    func logText(_ text: String) { if let data = text.data(using: .utf8) { try? logHandle?.write(contentsOf: data) } }
    func fail(_ message: String) {
        logText("Error: \(message)\n")
        if let folder = coordinator?.testFolder {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? message.write(to: folder.appendingPathComponent("FAILURE.txt"), atomically: true, encoding: .utf8)
            try? logHandle?.synchronize()
            try? fm.copyItem(at: logURL(), to: folder.appendingPathComponent("engine.log"))
            coordinator?.stopAll(); Darwin.exit(1)
        }
        let alert = NSAlert(); alert.messageText = "RDataCraft"; alert.informativeText = message
        alert.runModal()
    }

    // Tests run inside this application's own WKWebView and private R instance.
    // No browser automation, user browser tabs, or Prism documents are accessed.
    func waitUntil(_ expression: String, timeout: TimeInterval = 25) async throws {
        logText("Checking: \(expression)\n")
        if let folder = testFolder {
            try? expression.write(to: folder.appendingPathComponent("current-check.txt"), atomically: true, encoding: .utf8)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = try? await webView.evaluateJavaScript(expression), let passed = value as? Bool, passed { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if let folder = testFolder {
            let diagnostic = try? await webView.evaluateJavaScript("JSON.stringify({graph:JSON.parse(document.querySelector('#rdatacraft-interaction')?.textContent || 'null'),currentToken:document.getElementById('figure')?.dataset.currentToken,inputs:Object.fromEntries(['layout','graph','method','worksheet','graph_view','y_min','y_max','group1','group2','series_styles'].map(id=>[id,document.getElementById(id)?.value])),errors:Array.from(document.querySelectorAll('.shiny-output-error')).map(e=>({id:e.id,text:e.textContent})),busy:document.documentElement.classList.contains('shiny-busy'),images:Array.from(document.querySelectorAll('#figure img,#layout_figure img')).map(i=>({src:i.getAttribute('src')?.slice(0,180),complete:i.complete,width:i.naturalWidth,height:i.naturalHeight}))})")
            if let text = diagnostic as? String { try? text.write(to: folder.appendingPathComponent("timeout-state.json"), atomically: true, encoding: .utf8) }
            if let snapshot = try? await webView.takeSnapshot(configuration: nil), let png = try? imageData(snapshot) { try? png.write(to: folder.appendingPathComponent("timeout.png")) }
        }
        throw HostError.failed("Timed out: \(expression)")
    }
    func waitForFile(_ file: URL) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if fm.fileExists(atPath: file.path), ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 100 { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw HostError.failed("Download did not finish: \(file.lastPathComponent)")
    }
    func navigatorTest(_ folder: URL) async throws {
        try await waitUntil("document.querySelector('#data_grid table') !== null")
        send(["type":"open", "path":backend.appendingPathComponent("examples/RDataCraft examples.rdatacraft").path])
        try await waitUntil("document.querySelectorAll('#project_navigator .navigator-family').length === 6")
        _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator button[data-sheet=D6][data-view=V1][data-page=figure]').click()")
        try await waitUntil("document.getElementById('worksheet').value === 'D6' && document.querySelector('#nav_figure').classList.contains('active') && !document.documentElement.classList.contains('shiny-busy')")
        let diagnostic = try await webView.evaluateJavaScript("JSON.stringify((()=>{const n=document.getElementById('project_navigator'),e=n.querySelector('[aria-current=page]');return {nav:n.getBoundingClientRect().toJSON(),client:n.clientHeight,height:n.scrollHeight,top:n.scrollTop,selected:e?.outerHTML,rect:e?.getBoundingClientRect().toJSON()};})())")
        if let json = diagnostic as? String {try json.write(to:folder.appendingPathComponent("navigator-state.json"),atomically:true,encoding:.utf8)}
        try await waitUntil("(()=>{const n=document.getElementById('project_navigator'),e=n.querySelector('[aria-current=page]');if(!e)return false;const a=n.getBoundingClientRect(),b=e.getBoundingClientRect();return b.top>=a.top&&b.bottom<=a.bottom+1;})()", timeout: 3)
        let capture = try await webView.takeSnapshot(configuration:nil)
        try imageData(capture).write(to:folder.appendingPathComponent("navigator.png"))
        try "passed".write(to:folder.appendingPathComponent("status.txt"),atomically:true,encoding:.utf8)
    }
    func pasteTest(_ folder: URL) async throws -> [String] {
        send(["type": "new"])
        try await waitUntil("document.getElementById('title').value === 'Untitled figure' && document.querySelector('#nav_data').classList.contains('active') && document.querySelector('#data_grid tbody td') !== null && !document.documentElement.classList.contains('shiny-busy')")
        // Preserve the user's clipboard, and restore only if no newer copy occurred.
        let clipboard = NSPasteboard.general
        let savedItems = clipboard.pasteboardItems?.map { original -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { item.setData(data, forType: type) } }
            return item
        } ?? []
        var lastClipboardChange = clipboard.changeCount
        defer { if clipboard.changeCount == lastClipboardChange { clipboard.clearContents(); if !savedItems.isEmpty { clipboard.writeObjects(savedItems) } } }
        func nativePaste(_ text: String) throws {
            clipboard.clearContents(); clipboard.setString(text, forType: .string); lastClipboardChange = clipboard.changeCount
            guard let menu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Edit" })?.submenu,
                  let item = menu.items.first(where: { $0.title == "Paste" }), let action = item.action,
                  NSApp.sendAction(action, to: item.target, from: item) else { throw HostError.failed("Native Paste menu failed.") }
        }
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').click()")
        try await waitUntil("document.activeElement?.matches('#data_grid td.grid-anchor') === true")
        try nativePaste("10\t20\r\n30\t40\r\n")
        try await waitUntil("document.querySelector('#data_grid tbody tr:nth-child(2) td:nth-child(2)')?.textContent === '40' && !document.getElementById('undo_data').disabled")
        undoEdit()
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '' && !document.getElementById('redo_data').disabled")
        redoEdit()
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '10'")
        _ = try await webView.evaluateJavaScript("document.getElementById('grid_paste_headers').checked=true; document.querySelector('#data_grid tbody td').click()")
        try nativePaste("Vehicle\tDrug\n" + (1...30).map { "\($0)\t\($0 * 2)" }.joined(separator: "\n"))
        try await waitUntil("document.querySelector('#data_grid .dataTables_scrollHead th')?.textContent.trim() === 'Vehicle' && document.querySelector('#data_grid .dataTables_info')?.textContent.includes('30 entries') === true")
        _ = try await webView.evaluateJavaScript("document.getElementById('grid_paste_headers').checked=false; document.querySelector('#data_grid tbody tr:nth-child(14) td:nth-child(2)').scrollIntoView({block:'nearest'}); null")
        try await waitUntil("document.querySelectorAll('#data_grid tbody tr').length === 30 && document.querySelector('#data_grid .dataTables_paginate') === null")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody tr:nth-child(14) td:nth-child(2)').click()")
        try await waitUntil("document.getElementById('grid_selection').textContent.includes('Row 14 · Column 2')")
        try nativePaste("999")
        try await waitUntil("document.querySelector('#data_grid tbody tr:nth-child(14) td:nth-child(2)')?.textContent === '999' && document.querySelector('#data_grid tbody td')?.textContent === '1'")
        try await waitUntil("document.querySelector('#data_grid .dataTables_scrollBody').scrollTop > 0")
        // Arrow navigation follows observations across the former page boundary.
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody tr:nth-child(12) td:nth-child(2)').click();document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true,cancelable:true}))")
        try await waitUntil("document.getElementById('grid_selection').textContent.includes('Row 13 · Column 2') && document.activeElement === document.querySelector('#data_grid tbody tr:nth-child(13) td:nth-child(2)')")
        // Exercise the browser paste event as well as the native clipboard path.
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').click(); var clip=new DataTransfer(); clip.setData('text/plain','777\\t888\\n555\\t666'); document.activeElement.dispatchEvent(new ClipboardEvent('paste',{clipboardData:clip,bubbles:true,cancelable:true}))")
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '777' && document.querySelector('#data_grid tbody tr:nth-child(2) td:nth-child(2)')?.textContent === '666'")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}))")
        try await waitUntil("document.activeElement?.matches('#data_grid td input') === true")
        try nativePaste("321\t654\n111\t222")
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '321' && document.querySelector('#data_grid tbody tr:nth-child(2) td:nth-child(2)')?.textContent === '222'")
        undoEdit()
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '777' && document.querySelector('#data_grid tbody tr:nth-child(2) td:nth-child(2)')?.textContent === '666'")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').click()")
        try nativePaste("123\tinvalid")
        try await waitUntil("document.getElementById('grid_selection').textContent.startsWith('Paste rejected:')")
        try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '777' && document.querySelector('#data_grid tbody td:nth-child(2)')?.textContent === '888'")
        // Paste outside the table continues to edit the ordinary focused field.
        _ = try await webView.evaluateJavaScript("document.getElementById('navigator_search').focus(); document.getElementById('navigator_search').select()")
        try nativePaste("Vehicle")
        try await waitUntil("document.getElementById('navigator_search').value === 'Vehicle'")
        _ = try await webView.evaluateJavaScript("document.getElementById('navigator_search').value=''; document.getElementById('navigator_search').dispatchEvent(new Event('input',{bubbles:true})); document.activeElement.blur(); document.querySelector('#data_grid tbody td').click(); document.querySelectorAll('.shiny-notification').forEach(el=>el.remove()); document.querySelector('.data-card').scrollIntoView({block:'center'})")
        try await waitUntil("document.querySelector('.example-buttons') === null && document.querySelector('#example_guide') === null")
        let capture = try await webView.takeSnapshot(configuration: nil)
        try imageData(capture).write(to: folder.appendingPathComponent("direct-grid-paste.png"))
        _ = try await webView.evaluateJavaScript("document.querySelector('.transform-card').scrollIntoView({block:'center'})")
        try await waitUntil("(()=>{const button=document.getElementById('apply_transform').getBoundingClientRect(),first=document.getElementById('transform_kind').selectize.$control[0].getBoundingClientRect(),second=document.getElementById('transform_control').selectize.$control[0].getBoundingClientRect();return Math.abs(button.bottom-first.bottom)<2 && Math.abs(button.bottom-second.bottom)<2 && button.left>second.right;})()")
        let transformCapture = try await webView.takeSnapshot(configuration:nil)
        try imageData(transformCapture).write(to:folder.appendingPathComponent("transform-controls.png"))
        _ = try await webView.evaluateJavaScript("document.getElementById('nav_analysis').click()")
        try await waitUntil("document.querySelector('#nav_analysis.active') !== null && document.getElementById('method').selectize.$control[0].getBoundingClientRect().width > 0")
        _ = try await webView.evaluateJavaScript("document.getElementById('method').selectize.open()")
        try await waitUntil("Math.abs(document.querySelector('.analysis-method-menu').getBoundingClientRect().left-document.getElementById('method').selectize.$control[0].getBoundingClientRect().left) < 2 && document.querySelector('.analysis-method-menu').getBoundingClientRect().top >= 0 && document.querySelector('.analysis-method-menu')?.getBoundingClientRect().height > 240 && document.querySelector('.analysis-method-menu').getBoundingClientRect().bottom <= window.innerHeight && document.getElementById('method').selectize.$control[0].getBoundingClientRect().height < 60")
        let analysisCapture = try await webView.takeSnapshot(configuration: nil)
        try imageData(analysisCapture).write(to: folder.appendingPathComponent("analysis-methods.png"))
        _ = try await webView.evaluateJavaScript("document.getElementById('method').selectize.setValue('anova');document.getElementById('method').selectize.close()")
        try await waitUntil("document.getElementById('analysis_status').textContent.includes('ANOVA') && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('nav_data').click()")
        let file = folder.appendingPathComponent("Pasted study.rdatacraft")
        nextTestDestination = file; saveAs(); try await waitForFile(file)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        guard let tsv = saved?["data_tsv"] as? String, tsv.contains("Vehicle"), tsv.contains("777"), tsv.contains("666"), !tsv.contains("invalid") else { throw HostError.failed("Pasted observations or headers were not saved correctly.") }
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_heading .table-name').click(); var renameField=document.querySelector('#data_heading .table-name-editor'); renameField.value='Clipboard experiment'; renameField.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}))")
        try await waitUntil("document.querySelector('#data_heading .table-name')?.textContent === 'Clipboard experiment' && document.querySelector('#project_navigator .table-name')?.textContent === 'Clipboard experiment'")
        _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator .table-name').click(); var renameField=document.querySelector('#project_navigator .table-name-editor'); renameField.value='Cancelled'; renameField.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")
        try await waitUntil("document.querySelector('#project_navigator .table-name')?.textContent === 'Clipboard experiment'")
        _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator .table-name').click(); var renameField=document.querySelector('#project_navigator .table-name-editor'); renameField.value='Pasted observations'; renameField.blur()")
        try await waitUntil("document.querySelector('#data_heading .table-name')?.textContent === 'Pasted observations'")
        _ = try await webView.evaluateJavaScript("document.getElementById('new_worksheet').click()")
        try await waitUntil("document.getElementById('worksheet_xy_replicates') !== null")
        _ = try await webView.evaluateJavaScript("document.getElementById('worksheet_layout').selectize.setValue('xy'); Shiny.setInputValue('worksheet_xy_replicates',3,{priority:'event'}); Shiny.setInputValue('worksheet_name','Triplicate time course',{priority:'event'}); Shiny.setInputValue('worksheet_example',false,{priority:'event'})")
        try await waitUntil("document.querySelectorAll('#worksheet_template .template-table th').length === 7 && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('confirm_worksheet').click()")
        try await waitUntil("document.getElementById('worksheet').value === 'D2' && document.querySelector('#data_grid .dataTables_scrollHead th[colspan=\"3\"]') !== null && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').click()")
        try nativePaste("0\t2\t3\t4\t3\t4\t5\n1\t4\t5\t6\t5\t6\t7\n2\t6\t7\t8\t8\t9\t10")
        try await waitUntil("document.querySelector('#data_grid tbody tr:nth-child(3) td:nth-child(7)')?.textContent === '10'")
        let replicatedTable = try await webView.takeSnapshot(configuration: nil)
        try imageData(replicatedTable).write(to:folder.appendingPathComponent("xy-replicate-table.png"))
        showFigure()
        try await waitUntil("document.getElementById('graph').value === 'xymean' && document.querySelector('#figure img')?.complete && document.querySelector('#figure img')?.naturalWidth > 0 && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("for(const [id,value] of [['figure_width_in',5],['figure_height_in',3]]) {var f=document.getElementById(id);f.value=value;f.dispatchEvent(new Event('change',{bubbles:true}))}")
        _ = try await webView.evaluateJavaScript("document.getElementById('figure_zoom').value='actual';document.getElementById('figure_zoom').dispatchEvent(new Event('change'))")
        try await waitUntil("Math.abs(Number(document.getElementById('width').value)-127)<0.001 && Math.abs(Number(document.getElementById('height').value)-76.2)<0.001 && document.getElementById('figure_dimensions').textContent === '5.00 × 3.00 in · 100%' && !document.documentElement.classList.contains('shiny-busy')")
        try await waitUntil("Math.abs(document.getElementById('figure').getBoundingClientRect().width-480)<1 && Math.abs(document.getElementById('figure').getBoundingClientRect().height-288)<1")
        let actual = try await webView.takeSnapshot(configuration:nil)
        try imageData(actual).write(to:folder.appendingPathComponent("graph-actual-size.png"))
        _ = try await webView.evaluateJavaScript("var f=document.getElementById('figure_width_in');f.value=10;f.dispatchEvent(new Event('change',{bubbles:true}));var z=document.getElementById('figure_zoom');z.value='fit';z.dispatchEvent(new Event('change',{bubbles:true}))")
        try await waitUntil("document.getElementById('figure_stage').dataset.widthIn === '10' && Number(document.getElementById('figure_stage').dataset.scale) < 1 && !document.documentElement.classList.contains('shiny-busy')")
        try await waitUntil("document.getElementById('figure').getBoundingClientRect().width <= document.getElementById('figure_viewport').clientWidth-47")
        let fitted = try await webView.takeSnapshot(configuration:nil)
        try imageData(fitted).write(to:folder.appendingPathComponent("graph-fit-window.png"))
        _ = try await webView.evaluateJavaScript("var z=document.getElementById('figure_zoom');z.value='actual';z.dispatchEvent(new Event('change',{bubbles:true}))")
        try await waitUntil("document.getElementById('figure_dimensions').textContent === '10.00 × 3.00 in · 100%' && Math.abs(document.getElementById('figure').getBoundingClientRect().width-960)<1")
        let finalFile = folder.appendingPathComponent("Replicated experiment.rdatacraft")
        nextTestDestination = finalFile; saveAs(); try await waitForFile(finalFile)
        let final = try JSONSerialization.jsonObject(with: Data(contentsOf: finalFile)) as? [String:Any]
        let worksheets = final?["worksheets"] as? [String:[String:Any]], settings = final?["settings"] as? [String:Any]
        guard worksheets?["D1"]?["name"] as? String == "Pasted observations", (worksheets?["D2"]?["data_tsv"] as? String)?.contains("[rep 3]") == true,
              abs((settings?["width"] as? Double ?? 0) - 254) < 0.001 else {throw HostError.failed("Table names, replicate grouping or figure size did not persist.")}
        let svg = folder.appendingPathComponent("replicated-10x3.svg")
        nextTestDestination = svg; exportSVG(); try await waitForFile(svg)
        let svgText = try String(contentsOf:svg)
        guard svgText.contains("width='720.00pt'"), svgText.contains("height='216.00pt'") else {throw HostError.failed("SVG export does not match the requested ten by three inch canvas.")}
        send(["type":"open", "path":backend.appendingPathComponent("examples/XY curve fitting review.rdatacraft").path])
        try await waitUntil("document.getElementById('graph').value === 'xymean' && document.getElementById('fit_scope').value === 'all' && document.getElementById('xy_connections').value === 'none' && !document.documentElement.classList.contains('shiny-busy')")
        showFigure()
        let fitLineCount = "Array.from(document.querySelectorAll('#figure svg.graph-interactive polyline')).filter(p => p.getAttribute('points').trim().split(/\\s+/).length > 100).length"
        try await waitUntil("\(fitLineCount) === 2 && document.getElementById('xy_fit_scope_note').textContent.includes('All Y series')")
        _ = try await webView.evaluateJavaScript("document.getElementById('fit_scope').selectize.setValue('selected')")
        try await waitUntil("\(fitLineCount) === 1 && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('xy_fit_all').click()")
        try await waitUntil("\(fitLineCount) === 2 && document.getElementById('fit_scope').value === 'all' && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('xy_show_fit').click()")
        try await waitUntil("\(fitLineCount) === 0 && !document.getElementById('xy_show_fit').checked && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('xy_show_fit').click();document.getElementById('graph').selectize.setValue('scatter')")
        try await waitUntil("\(fitLineCount) === 2 && document.getElementById('graph').value === 'scatter' && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('graph').selectize.setValue('xymean')")
        try await waitUntil("\(fitLineCount) === 2 && document.getElementById('graph').value === 'xymean' && !document.documentElement.classList.contains('shiny-busy')")
        let xyCapture = try await webView.takeSnapshot(configuration:nil)
        try imageData(xyCapture).write(to:folder.appendingPathComponent("xy-independent-fits.png"))
        let xyStudy = folder.appendingPathComponent("Independent fitted curves.rdatacraft")
        nextTestDestination = xyStudy;saveAs();try await waitForFile(xyStudy)
        let xySaved = try JSONSerialization.jsonObject(with:Data(contentsOf:xyStudy)) as? [String:Any]
        guard let xySettings = xySaved?["settings"] as? [String:Any],xySettings["fit_scope"] as? String == "all",xySettings["xy_connections"] as? String == "none" else {throw HostError.failed("XY fitting controls were not saved.")}
        return ["native Paste into selected grid cell", "rectangular paste CRLF", "whole-block undo and redo", "header paste and row expansion", "all 30 rows in one scrolling sheet", "absolute row 14 paste and preserved scroll", "arrow navigation across former page boundary", "redundant example sections removed", "transform action aligns with selection fields", "compact method selector opens a large visible dropdown and changes analysis", "browser clipboard event", "bulk paste from inline editor", "inline bulk paste is one undo action", "atomic invalid paste rejection", "ordinary text-field paste", "pasted headers and observations saved", "inline table heading rename", "navigator rename cancellation", "navigator rename on blur", "XY triplicate creation and grouped headers", "clipboard entry into replicate subcolumns", "replicate mean/error graph", "inch canvas controls", "actual-size pixel dimensions", "fit to window scales without changing export size", "restore actual size", "table names and replicates saved", "exact inch SVG export", "two independent fitted curves on mean/error graph", "graph shortcut fits every series", "fitted curves toggle independently of connections", "two fitted series on scatter graph", "XY fitting controls saved"]
    }
    func graphTest(_ folder:URL) async throws -> [String] {
        func js(_ code:String) async throws {_ = try await webView.evaluateJavaScript("(()=>{\(code);return null;})()")}
        try await waitUntil("document.body.dataset.runtime === 'desktop' && !document.documentElement.classList.contains('shiny-busy')")
        send(["type":"new"])
        try await waitUntil("document.querySelector('#data_grid tbody td') !== null")
        send(["type":"open","path":backend.appendingPathComponent("examples/XY replicates example.rdatacraft").path])
        try await waitUntil("document.getElementById('layout').value === 'xy'")
        showFigure()
        try await waitUntil("document.querySelector('#figure svg.graph-interactive [data-graph-kind=\"label:title\"]')?.textContent === 'Response over time'")
        try await js(#"document.querySelector('[data-graph-kind="label:title"]').dispatchEvent(new MouseEvent('click',{bubbles:true}));var f=document.querySelector('.graph-label-editor');f.value='Cancelled';f.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))"#)
        try await waitUntil("document.querySelector('.graph-label-editor') === null && document.getElementById('title').value === 'Response over time'")
        try await js(#"document.querySelector('[data-graph-kind="label:title"]').dispatchEvent(new MouseEvent('click',{bubbles:true}));var f=document.querySelector('.graph-label-editor');f.value='Publication graph';f.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}))"#)
        try await waitUntil("document.querySelector('[data-graph-kind=\"label:title\"]')?.textContent === 'Publication graph'")
        try await js(#"document.querySelector('[data-graph-kind="label:x_label"]').dispatchEvent(new MouseEvent('click',{bubbles:true}));var f=document.querySelector('.graph-label-editor');f.value='Hours after treatment';f.blur()"#)
        try await waitUntil("document.querySelector('[data-graph-kind=\"label:x_label\"]')?.textContent === 'Hours after treatment'")
        try await js(#"document.querySelector('[data-graph-kind="label:y_label"]').dispatchEvent(new MouseEvent('click',{bubbles:true}));var f=document.querySelector('.graph-label-editor');f.value='Signal (a.u.)';f.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}))"#)
        try await waitUntil("document.querySelector('[data-graph-kind=\"label:y_label\"]')?.textContent === 'Signal (a.u.)'")
        try await js(#"document.querySelector('.graph-axis-target[data-axis=x]').dispatchEvent(new MouseEvent('click',{bubbles:true}))"#)
        try await waitUntil("document.getElementById('graph_format_dialog').open && document.querySelector('[data-setting=axis_color]') !== null")
        try await js(#"document.querySelector('[data-setting=y_min]').value='0';document.querySelector('[data-setting=y_max]').value='12';document.querySelector('[data-setting=axis_color]').value='#334455';document.getElementById('graph_format_form').requestSubmit()"#)
        try await waitUntil("!document.getElementById('graph_format_dialog').open && document.querySelector('#figure svg metadata')?.textContent.includes('#334455') === true")
        try await js(#"document.querySelector('#figure svg [data-graph-kind=data]').dispatchEvent(new MouseEvent('click',{bubbles:true}))"#)
        try await waitUntil("document.getElementById('graph_format_dialog').open && document.querySelector('[data-setting=point_shape]') !== null")
        try await js(#"if(document.getElementById('graph_series_scope')){document.getElementById('graph_series_scope').value='';document.getElementById('graph_series_scope').dispatchEvent(new Event('change'));}document.querySelector('[data-setting=palette]').value='monochrome';document.querySelector('[data-setting=point_shape]').value='17';document.querySelector('[data-setting=error]').value='sd';document.getElementById('graph_format_form').requestSubmit()"#)
        try await waitUntil("!document.getElementById('graph_format_dialog').open && document.querySelector('#figure svg metadata')?.textContent.includes('monochrome') === true")
        try await js(#"document.querySelector('[data-graph-format=text]').click();document.querySelector('[data-setting=title_size]').value=18;document.querySelector('[data-setting=axis_title_size]').value=15;document.querySelector('[data-setting=text_color]').value='#112233';document.getElementById('graph_format_form').requestSubmit()"#)
        try await waitUntil("!document.getElementById('graph_format_dialog').open && document.querySelector('#figure svg metadata')?.textContent.includes('#112233') === true")
        try await js(#"document.querySelector('[data-graph-format=canvas]').click();document.querySelector('[data-setting=width]').value=5;document.querySelector('[data-setting=height]').value=3;document.getElementById('graph_format_form').requestSubmit()"#)
        try await waitUntil("!document.getElementById('graph_format_dialog').open && document.getElementById('figure_dimensions').textContent.includes('5.00 × 3.00') && document.querySelector('#figure svg.graph-interactive') !== null")
        try await waitUntil("!document.documentElement.classList.contains('shiny-busy') && document.querySelector('#figure.recalculating,#project_navigator.recalculating') === null")
        let capture=try await webView.takeSnapshot(configuration:nil)
        try imageData(capture).write(to:folder.appendingPathComponent("direct-graph-editing.png"))
        let clipboard=NSPasteboard.general
        let saved=clipboard.pasteboardItems?.map { original -> NSPasteboardItem in let item=NSPasteboardItem();for type in original.types {if let data=original.data(forType:type){item.setData(data,forType:type)}};return item } ?? []
        copyVector()
        try await waitUntil("document.getElementById('graph_edit_status').textContent.includes('Vector PDF and SVG copied')")
        let copiedChange=clipboard.changeCount
        defer {if clipboard.changeCount==copiedChange {clipboard.clearContents();if !saved.isEmpty {clipboard.writeObjects(saved)}}}
        guard let pdf=clipboard.data(forType:.pdf),let svg=clipboard.data(forType:NSPasteboard.PasteboardType("public.svg-image")),
              let document=PDFDocument(data:pdf),let page=document.page(at:0),document.pageCount==1,
              abs(page.bounds(for:.mediaBox).width-360)<0.1,abs(page.bounds(for:.mediaBox).height-216)<0.1,
              document.string?.contains("Publication graph")==true,
              let svgText=String(data:svg,encoding:.utf8),svgText.contains("<svg"),!svgText.contains("<image"),!svgText.contains("rdatacraft-interaction") else {throw HostError.failed("Vector clipboard formats, dimensions or text are invalid.")}
        try pdf.write(to:folder.appendingPathComponent("clipboard.pdf"));try svg.write(to:folder.appendingPathComponent("clipboard.svg"))
        try await js("document.getElementById('new_view').click()")
        try await waitUntil("document.getElementById('confirm_new_view') !== null")
        try await js("var f=document.getElementById('new_view_name');f.value='Quadratic fit';f.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('confirm_new_view').click()")
        try await waitUntil("document.getElementById('graph_view').value === 'V2'")
        try await js("document.getElementById('method').selectize.setValue('quadratic');document.getElementById('graph').selectize.setValue('scatter')")
        showAnalysis()
        try await waitUntil("document.querySelector('#parameters_table tbody tr') !== null && !document.documentElement.classList.contains('shiny-busy')")
        try await waitUntil("document.querySelector('#analysis_metrics').textContent.includes('SSE') && document.getElementById('export_residuals').getAttribute('href')?.includes('/download/') === true")
        nextTestDestination=folder.appendingPathComponent("residuals.csv")
        try await js("document.getElementById('export_residuals').click()")
        try await waitForFile(folder.appendingPathComponent("residuals.csv"))
        showFigure()
        try await waitUntil("document.querySelector('#figure svg.graph-interactive') !== null && document.getElementById('method').value === 'quadratic'")
        try await js("Shiny.setInputValue('layout_views',['D1:V1','D1:V2'],{priority:'event'});document.querySelector('[data-graph-action=delete_view]').click()")
        try await waitUntil("document.getElementById('confirm_delete_view') !== null")
        try await js("document.getElementById('confirm_delete_view').click()")
        try await waitUntil("document.getElementById('graph_view').value === 'V1' && document.querySelectorAll('#graph_view option').length === 1 && document.querySelector('#layout_views input[value=\"D1:V2\"]') === null")
        try await js("document.getElementById('delete_view').click()")
        try await waitUntil("document.getElementById('confirm_delete_view') === null && document.querySelector('.shiny-notification')?.textContent.includes('at least one') === true")
        send(["type":"prism","path":backend.appendingPathComponent("tests/fixtures/source-tables.prism").path])
        try await waitUntil("document.getElementById('confirm_prism_import') !== null && document.querySelector('#prism_preview table') !== null")
        try await waitUntil("document.querySelector('#shiny-modal.show') !== null && getComputedStyle(document.getElementById('shiny-modal')).opacity === '1'")
        let preview=try await webView.takeSnapshot(configuration:nil)
        try imageData(preview).write(to:folder.appendingPathComponent("prism-import-preview.png"))
        try await js("var f=document.getElementById('prism_all');f.checked=true;f.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('confirm_prism_import').click()")
        try await waitUntil("document.getElementById('worksheet').value === 'D3' && document.getElementById('layout').value === 'grouped' && document.querySelectorAll('#project_navigator .navigator-family').length === 3")
        send(["type":"prism","path":backend.appendingPathComponent("tests/fixtures/source-tables.pzfx").path])
        try await waitUntil("document.getElementById('confirm_prism_import') !== null && document.querySelector('#prism_preview table') !== null")
        try await js("var f=document.getElementById('prism_all');f.checked=false;f.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('confirm_prism_import').click()")
        try await waitUntil("document.getElementById('worksheet').value === 'D4' && document.getElementById('layout').value === 'xy' && document.querySelector('#data_grid th[colspan=\"3\"]') !== null")
        let file=folder.appendingPathComponent("Edited graphs and import.rdatacraft")
        nextTestDestination=file;saveAs();try await waitForFile(file)
        let savedProject=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any]
        let book=savedProject?["worksheets"] as? [String:[String:Any]], settings=book?["D1"]?["settings"] as? [String:Any]
        guard (book?["D1"]?["views"] as? [String:Any])?.count==1,settings?["title"] as? String=="Publication graph",settings?["axis_color"] as? String=="#334455" else {throw HostError.failed("Edited graph settings or deleted views were not saved.")}
        return ["inline SVG graph interaction", "title edit cancellation", "title edit commit", "X title edit on blur", "Y title edit", "click axis opens formatting", "axis formatting applies", "click data opens appearance", "symbol palette and error-bar controls", "text formatting toolbar", "canvas formatting toolbar", "PDF clipboard flavor", "SVG clipboard flavor", "clipboard contains vector text", "clipboard preserves exact inch size", "clipboard contains no raster screenshot", "new linked regression view", "quadratic parameters and fit statistics", "residual CSV export", "delete alternative view", "delete removes layout references", "last-view protection", "Prism import preview", "multi-table Prism import", "bundled PZFX decoder", "PZFX replicate import", "save edited graph and imported tables"]
    }
    func studioChecks(_ folder: URL) async throws -> [String] {
        showData()
        try await waitUntil("document.querySelector('#data_grid [data-rename-column=\"2\"]') !== null")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid [data-rename-column=\"2\"]').click()")
        try await waitUntil("document.querySelector('.column-name-editor') !== null")
        _ = try await webView.evaluateJavaScript("var f=document.querySelector('.column-name-editor');f.value='Canceled';f.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")
        try await waitUntil("document.querySelector('.column-name-editor') === null && document.querySelector('#data_grid [data-rename-column=\"2\"]').textContent.includes('Control')")
        _ = try await webView.evaluateJavaScript("document.querySelector('#data_grid [data-rename-column=\"2\"]').click();var f=document.querySelector('.column-name-editor');f.value='Vehicle α';f.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}))")
        try await waitUntil("document.querySelector('#data_grid [data-rename-column=\"2\"]').textContent.includes('Vehicle α') && document.getElementById('group1').textContent.includes('Vehicle α')")
        undoEdit()
        try await waitUntil("document.querySelector('#data_grid [data-rename-column=\"2\"]').textContent.includes('Control')")
        redoEdit()
        try await waitUntil("document.querySelector('#data_grid [data-rename-column=\"2\"]').textContent.includes('Vehicle α')")
        undoEdit()
        try await waitUntil("document.querySelector('#data_grid [data-rename-column=\"2\"]').textContent.includes('Control')")
        let dataImage=try await webView.takeSnapshot(configuration:nil)
        try imageData(dataImage).write(to:folder.appendingPathComponent("editable-headers.png"))
        showFigure()
        try await waitUntil("document.querySelector('#figure svg.graph-interactive text[data-series=Drug]') !== null && window.RDataCraftGraph.ready()")
        _ = try await webView.evaluateJavaScript("document.querySelector('#figure svg.graph-interactive text[data-series=Drug]').dispatchEvent(new MouseEvent('click',{bubbles:true}))")
        try await waitUntil("document.getElementById('graph_format_dialog').open && document.getElementById('graph_series_scope').value==='Drug'")
        _ = try await webView.evaluateJavaScript("document.querySelector('#graph_format_dialog .dialog-actions button[type=button]').click();window.RDataCraftGraph.format('axes')")
        try await waitUntil("document.querySelector('[data-setting=y_tick_step]') !== null")
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-setting=y_tick_step]').value='2';document.querySelector('[data-setting=ref_y]').value='10';document.getElementById('graph_format_form').requestSubmit()")
        try await waitUntil("!document.getElementById('graph_format_dialog').open && document.getElementById('y_tick_step').value==='2' && document.getElementById('ref_y').value==='10'")
        _ = try await webView.evaluateJavaScript("document.getElementById('undo_graph').click()")
        try await waitUntil("document.getElementById('y_tick_step').value===''")
        _ = try await webView.evaluateJavaScript("document.getElementById('redo_graph').click()")
        try await waitUntil("document.getElementById('y_tick_step').value==='2'")
        _ = try await webView.evaluateJavaScript("document.getElementById('graph_gallery').click()")
        try await waitUntil("document.querySelectorAll('.graph-choice img').length>=5")
        let galleryImage=try await webView.takeSnapshot(configuration:nil)
        try imageData(galleryImage).write(to:folder.appendingPathComponent("graph-gallery.png"))
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-gallery-graph=step]').click()")
        try await waitUntil("document.querySelector('.modal.show')===null && document.getElementById('graph').value==='step' && document.querySelector('#figure svg.graph-interactive')?.textContent.includes('Mean response at each X') === true")
        _ = try await webView.evaluateJavaScript("document.getElementById('nav_layout').click()")
        try await waitUntil("document.querySelectorAll('.layout-panel-hit').length===4")
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-layout-template=hero]').click()")
        try await waitUntil("document.querySelector('.layout-panel-hit').style.width==='95.5556%' || Number.parseFloat(document.querySelector('.layout-panel-hit').style.width)>95")
        _ = try await webView.evaluateJavaScript("document.querySelectorAll('.layout-panel-hit')[1].click();document.getElementById('panel_label').value='B2';document.getElementById('panel_label').dispatchEvent(new Event('change',{bubbles:true}))")
        try await waitUntil("document.querySelectorAll('.panel-drag-label')[1].textContent.includes('B2')")
        _ = try await webView.evaluateJavaScript("for(const [k,v] of Object.entries({x:20,y:125,w:70,h:70}))document.getElementById('panel_'+k).value=v;document.getElementById('layout_panel_form').requestSubmit()")
        try await waitUntil("Math.abs(Number.parseFloat(document.querySelectorAll('.layout-panel-hit')[1].style.left)-20/180*100)<0.001 && !document.documentElement.classList.contains('shiny-busy')")
        // Exercise the pointer handler, including page-coordinate conversion and snapping.
        _ = try await webView.evaluateJavaScript("(()=>{const hit=document.querySelectorAll('.layout-panel-hit')[1],box=hit.getBoundingClientRect(),stage=document.getElementById('layout_stage').getBoundingClientRect();hit.setPointerCapture=()=>{};hit.dispatchEvent(new PointerEvent('pointerdown',{pointerId:42,button:0,clientX:box.x+20,clientY:box.y+20,bubbles:true}));hit.dispatchEvent(new PointerEvent('pointermove',{pointerId:42,clientX:box.x+20+stage.width/180*3,clientY:box.y+20,bubbles:true}));hit.dispatchEvent(new PointerEvent('pointerup',{pointerId:42,clientX:box.x+20+stage.width/180*3,clientY:box.y+20,bubbles:true}));})()")
        try await waitUntil("Math.abs(Number.parseFloat(document.querySelectorAll('.layout-panel-hit')[1].style.left)-23/180*100)<0.001 && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("document.getElementById('undo_layout').click()")
        try await waitUntil("Number(document.getElementById('panel_x').value)===20")
        _ = try await webView.evaluateJavaScript("document.getElementById('redo_layout').click()")
        try await waitUntil("Number(document.getElementById('panel_x').value)===23")
        let layoutImage=try await webView.takeSnapshot(configuration:nil)
        try imageData(layoutImage).write(to:folder.appendingPathComponent("figure-layout.png"))
        for format in ["svg","pdf","png"] {
            let file=folder.appendingPathComponent("custom-layout.\(format)")
            nextTestDestination=file;command("export-layout-\(format)");try await waitForFile(file)
            let data=try Data(contentsOf:file)
            if format=="svg" {guard String(data:data,encoding:.utf8)?.contains(">B2</text>")==true else {throw HostError.failed("Custom panel label missing from SVG export.")}}
            if format=="pdf" {guard let page=PDFDocument(data:data)?.page(at:0),abs(page.bounds(for:.mediaBox).width-180/25.4*72)<0.1 else {throw HostError.failed("Custom layout PDF dimensions are incorrect.")}}
            if format=="png" {guard let image=NSBitmapImageRep(data:data),abs(Double(image.pixelsWide)-180/25.4*300)<2 else {throw HostError.failed("Custom layout PNG dimensions are incorrect.")}}
        }
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-delete-table=D3]').click()")
        try await waitUntil("document.querySelector('.modal.show')?.textContent.includes('Delete data table')===true && document.querySelector('.modal.show')?.textContent.includes('panel')===true")
        try await Task.sleep(nanoseconds:400_000_000) // Allow Bootstrap’s opening transition to finish.
        _ = try await webView.evaluateJavaScript("document.querySelector('.modal.show [data-dismiss=modal],.modal.show [data-bs-dismiss=modal]').click()")
        try await waitUntil("document.querySelector('.modal.show')===null && document.querySelector('[data-delete-table=D3]')!==null")
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-delete-table=D3]').click()")
        try await waitUntil("document.getElementById('confirm_delete_table')!==null")
        try await Task.sleep(nanoseconds:400_000_000)
        _ = try await webView.evaluateJavaScript("document.getElementById('confirm_delete_table').click()")
        try await waitUntil("document.querySelector('[data-delete-table=D3]')===null && document.querySelectorAll('[data-delete-table]').length===2 && document.querySelectorAll('.layout-panel-hit').length===3")
        let project=folder.appendingPathComponent("Studio edits.rdatacraft")
        nextTestDestination=project;saveAs();try await waitForFile(project)
        let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:project)) as? [String:Any]
        guard saved?["schema_version"] as? Int == 6,let layout=saved?["figure_layout"] as? [String:Any],layout["arrangement"] as? String == "manual",(layout["labels"] as? String)?.contains("B2")==true,(saved?["worksheets"] as? [String:Any])?.count==2 else {throw HostError.failed("Studio edits were not saved correctly.")}
        send(["type":"open","path":project.path])
        try await waitUntil("document.querySelectorAll('.layout-panel-hit').length===3 && document.querySelectorAll('[data-delete-table]').length===2 && document.getElementById('graph').value==='step'")
        return ["inline header cancel", "inline shared header rename", "header Undo", "header Redo", "click legend selects series", "tick interval and reference line", "format Undo", "format Redo", "graph gallery previews", "gallery changes graph", "interactive layout panels", "large-top template", "custom panel label", "numeric physical panel geometry", "pointer drag and snap", "layout Undo", "layout Redo", "custom layout SVG label", "custom layout PDF dimensions", "custom layout PNG dimensions", "table delete confirmation", "table delete cancellation", "confirmed table delete removes dependent panel", "schema 6 save/reopen"]
    }
    func pcaGuideChecks(_ folder:URL) async throws -> [String] {
        showExamples()
        try await waitUntil("document.getElementById('tutorial_choice')?.selectize!==undefined")
        _ = try await webView.evaluateJavaScript("document.getElementById('tutorial_choice').selectize.setValue('pca')")
        try await waitUntil("document.getElementById('tutorial_choice')?.value==='pca' && document.querySelector('#tutorial_preview')?.textContent.includes('Step-by-step analysis')===true")
        try await waitUntil("document.querySelector('#shiny-modal.show')!==null && getComputedStyle(document.getElementById('shiny-modal')).opacity==='1'")
        try imageData(try await webView.takeSnapshot(configuration:nil)).write(to:folder.appendingPathComponent("pca-guide.png"))
        _ = try await webView.evaluateJavaScript("document.getElementById('add_tutorial').click()")
        try await waitUntil("document.getElementById('layout').value==='multiple' && document.getElementById('method').value==='pca' && document.querySelector('#pca_scree tbody tr')!==null && !document.documentElement.classList.contains('shiny-busy')")
        try await waitUntil("document.getElementById('pca_variable_pick').selectize.items.length===5 && !document.getElementById('pca_variable_pick').selectize.items.includes('SampleID') && document.querySelector('#pca_scores .dataTables_info')?.textContent.includes('12 entries')===true")
        try await waitUntil("document.querySelector('.version-label')?.textContent.includes('v0.32')===true && Object.keys(document.getElementById('graph_view').selectize.options).length===3")
        try imageData(try await webView.takeSnapshot(configuration:nil)).write(to:folder.appendingPathComponent("pca-analysis.png"))
        for key in ["scores","loadings","scree","preprocessing"] {
            let file=folder.appendingPathComponent("pca-\(key).csv")
            nextTestDestination=file
            _ = try await webView.evaluateJavaScript("document.getElementById('export_pca_\(key)').click()")
            try await waitForFile(file)
            guard (try Data(contentsOf:file)).count>50 else {throw HostError.failed("PCA CSV export was empty.")}
        }
        showFigure()
        try await waitUntil("document.querySelector('#figure svg.graph-interactive')?.textContent.includes('PC1')===true && !document.querySelector('#figure.recalculating') && !document.documentElement.classList.contains('shiny-busy')")
        try imageData(try await webView.takeSnapshot(configuration:nil)).write(to:folder.appendingPathComponent("pca-scores.png"))
        let file=folder.appendingPathComponent("PCA teaching workflow.rdatacraft")
        nextTestDestination=file;saveAs();try await waitForFile(file)
        let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any]
        guard saved?["app_version"] as? String == "0.32",let settings=saved?["settings"] as? [String:Any],let selected=settings["pca_variables"] as? String,!selected.contains("SampleID"),selected.contains("CellArea") else {throw HostError.failed("PCA example settings or release version were not saved correctly.")}
        return ["PCA in the shared Help example selector", "PCA walkthrough visible", "PCA example adds 12 observations", "PCA selects measurements without numeric IDs", "three linked PCA views", "four PCA CSV exports", "PCA scores graph", "PCA settings and version saved"]
    }
    func workflowTest() async {
        guard let folder = testFolder else { return }
        let savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType:type).map { (type,$0) } }
        }
        defer {
            NSPasteboard.general.clearContents()
            let items = savedClipboard.map { representations -> NSPasteboardItem in
                let item=NSPasteboardItem();for (type,data) in representations {item.setData(data,forType:type)};return item
            }
            NSPasteboard.general.writeObjects(items)
        }
        do {
            if fm.fileExists(atPath: folder.path), !(try fm.contentsOfDirectory(atPath: folder.path)).isEmpty {
                throw HostError.failed("Use a new empty folder for each native smoke test.")
            }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard NSApp.mainMenu?.items.contains(where: { $0.submenu?.title == "File" }) == true else { throw HostError.failed("The native File menu is missing.") }
            try await waitUntil("document.body.dataset.runtime === 'desktop' && !document.documentElement.classList.contains('shiny-busy')")
            guard !hasDocument else { throw HostError.failed("Cold startup unexpectedly opened a study.") }
            send(["type":"open", "path":backend.appendingPathComponent("examples/RDataCraft examples.rdatacraft").path])
            try await waitUntil("document.body.dataset.runtime === 'desktop' && document.querySelector('#data_grid table') !== null")
            try await waitUntil("getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() === '#247763'")
            let dataImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(dataImage).write(to: folder.appendingPathComponent("data.png"))
            showFigure()
            try await waitUntil("document.querySelector('#figure img')?.getAttribute('src')?.length > 100 && document.querySelector('#nav_figure').classList.contains('active')")
            let navColor = try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('nav_figure')).backgroundColor")
            logText("Navigation selection color: \(navColor ?? "unknown")\n")
            _ = try await webView.evaluateJavaScript("document.getElementById('title').value = 'Desktop test figure'; document.getElementById('title').dispatchEvent(new Event('change', {bubbles:true}));")
            let dirtyDeadline = Date().addingTimeInterval(10)
            while !window.isDocumentEdited && Date() < dirtyDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard window.isDocumentEdited else { throw HostError.failed("Changing a figure did not mark the native document edited.") }
            let project = folder.appendingPathComponent("Desktop test.rdatacraft")
            nextTestDestination = project; saveAs()
            try await waitForFile(project)
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: project)) as? [String: Any]
            guard saved?["format"] as? String == "rdatacraft" else { throw HostError.failed("The saved document is not a RDataCraft project.") }
            let savedDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < savedDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("Saving did not clear the native edited state.") }
            for format in ["svg", "pdf", "png"] {
                let file = folder.appendingPathComponent("figure.\(format)")
                nextTestDestination = file; command("export-\(format)")
                try await waitForFile(file)
                let data = try Data(contentsOf: file)
                let valid = format == "svg" ? String(data: data, encoding: .utf8)?.contains("<svg") == true : format == "pdf" ? data.starts(with: Array("%PDF".utf8)) : data.starts(with: [137,80,78,71])
                guard valid else { throw HostError.failed("Invalid \(format) export.") }
            }
            send(["type":"new"])
            try await waitUntil("document.getElementById('title').value === 'Untitled figure' && document.querySelector('#nav_data').classList.contains('active')")
            let cleanDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < cleanDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("A newly created project is unexpectedly dirty.") }
            let blankProject = folder.appendingPathComponent("Blank study.rdatacraft")
            nextTestDestination = blankProject; saveAs()
            try await waitForFile(blankProject)
            let blank = try JSONSerialization.jsonObject(with: Data(contentsOf: blankProject)) as? [String: Any]
            guard (blank?["data_tsv"] as? String)?.contains("Control") == true else { throw HostError.failed("The blank project did not save its table headers.") }
            send(["type": "open", "path": project.path])
            try await waitUntil("document.getElementById('title').value === 'Desktop test figure'")
            guard window.representedURL == project else { throw HostError.failed("The native window does not represent the saved project.") }
            showFigure()
            try await waitUntil("document.querySelector('#figure img')?.getAttribute('src')?.length > 100 && !document.querySelector('#figure').classList.contains('shiny-output-error')")
            let graphImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(graphImage).write(to: folder.appendingPathComponent("graph.png"))
            // Exercise new controls in the actual embedded interface, using only
            // the bundled original example and this run's disposable project files.
            let example = backend.appendingPathComponent("examples/Prism workflow improvements.rdatacraft")
            send(["type":"open", "path":example.path])
            try await waitUntil("document.getElementById('fit_scope').value === 'all' && document.getElementById('title').value === 'Independent fits for each series'")
            showFigure()
            try await waitUntil("document.querySelector('#figure svg.graph-interactive')?.textContent.includes('Independent fits for each series') === true")
            _ = try await webView.evaluateJavaScript("window.RDataCraftGraph.format('data'); document.getElementById('graph_series_scope').value='Drug'; document.getElementById('graph_series_scope').dispatchEvent(new Event('change'))")
            try await waitUntil("document.querySelector('#graph_format_dialog[open] input[data-setting=color]') !== null")
            let formatImage = try await webView.takeSnapshot(configuration:nil)
            try imageData(formatImage).write(to:folder.appendingPathComponent("series-controls.png"))
            _ = try await webView.evaluateJavaScript("document.querySelector('#graph_format_form input[data-setting=color]').value='#8844AA'; document.getElementById('graph_format_form').requestSubmit()")
            try await waitUntil("!document.getElementById('graph_format_dialog').open && document.getElementById('series_styles').value.toLowerCase().includes('#8844aa')")
            try await waitUntil("document.querySelector('#figure svg.graph-interactive')?.innerHTML.toLowerCase().includes('#8844aa') === true")
            showData()
            try await waitUntil("document.querySelector('#nav_data.active') !== null && document.querySelector('#data_grid .dataTables_info')?.textContent.includes('11 entries') === true")
            _ = try await webView.evaluateJavaScript("document.getElementById('manage_table').click()")
            try await waitUntil("document.getElementById('row_edit_first') !== null")
            _ = try await webView.evaluateJavaScript("for (const [id,value] of [['row_edit_first',2],['row_edit_count',2]]) {const el=document.getElementById(id);el.value=value;el.dispatchEvent(new Event('change',{bubbles:true}));} document.getElementById('confirm_table_edit').click()")
            try await waitUntil("document.querySelector('#data_grid .dataTables_info')?.textContent.includes('13 entries') === true")
            undoEdit()
            try await waitUntil("document.querySelector('#data_grid .dataTables_info')?.textContent.includes('11 entries') === true")
            redoEdit()
            try await waitUntil("document.querySelector('#data_grid .dataTables_info')?.textContent.includes('13 entries') === true")
            undoEdit()
            try await waitUntil("document.querySelector('#data_grid .dataTables_info')?.textContent.includes('11 entries') === true")
            let workflowProject = folder.appendingPathComponent("Workflow edits.rdatacraft")
            nextTestDestination=workflowProject;saveAs();try await waitForFile(workflowProject)
            let workflow = try JSONSerialization.jsonObject(with:Data(contentsOf:workflowProject)) as? [String:Any]
            guard workflow?["schema_version"] as? Int == 5, let settings=workflow?["settings"] as? [String:Any], settings["fit_scope"] as? String == "all", (settings["series_styles"] as? String)?.lowercased().contains("#8844aa") == true else {throw HostError.failed("New graph and fit settings did not persist in the project.")}
            send(["type":"open", "path":workflowProject.path])
            try await waitUntil("document.getElementById('series_styles').value.toLowerCase().includes('#8844aa') && document.getElementById('fit_scope').value === 'all'")
            showAnalysis()
            try await waitUntil("document.getElementById('fit_status_table')?.textContent.includes('Fitted') === true && document.getElementById('parameters_table')?.textContent.includes('Drug') === true")
            try await waitUntil("document.getElementById('null_mean').getClientRects().length === 0 && document.getElementById('group2').closest('.shiny-input-container').getClientRects().length === 0 && document.getElementById('correction').closest('.shiny-input-container').getClientRects().length === 0")
            let resultsImage=try await webView.takeSnapshot(configuration:nil)
            try imageData(resultsImage).write(to:folder.appendingPathComponent("fit-results.png"))
            showFigure()
            try await waitUntil("document.querySelector('#figure svg.graph-interactive')?.innerHTML.toLowerCase().includes('#8844aa') === true")
            let vectorDeadline=Date().addingTimeInterval(15)
            let clipboardChange=NSPasteboard.general.changeCount
            copyVector()
            while NSPasteboard.general.changeCount == clipboardChange && Date()<vectorDeadline {try await Task.sleep(nanoseconds:200_000_000)}
            guard let vectorPDF=NSPasteboard.general.data(forType:.pdf), let vectorSVG=NSPasteboard.general.data(forType:NSPasteboard.PasteboardType("public.svg-image")), PDFDocument(data:vectorPDF)?.pageCount == 1, String(data:vectorSVG,encoding:.utf8)?.contains("<svg") == true else {throw HostError.failed("The native vector clipboard did not contain PDF and SVG.")}
            let workflowImage=try await webView.takeSnapshot(configuration:nil)
            try imageData(workflowImage).write(to:folder.appendingPathComponent("workflow-graph.png"))
            let studio = CommandLine.arguments.contains(where:{$0.hasPrefix("--studio-test=")}) ? try await studioChecks(folder) : []
            let advanced = CommandLine.arguments.contains(where:{$0.hasPrefix("--studio-test=")}) ? try await advancedRChecks(folder) : []
            let pca = CommandLine.arguments.contains(where:{$0.hasPrefix("--studio-test=")}) ? try await pcaGuideChecks(folder) : []
            let report: [String: Any] = ["status": "passed", "native_window": true, "craft_color": "#247763", "bundled_engine_pid": process?.processIdentifier ?? 0, "endpoint": endpoint.absoluteString, "checks": ["native bridge connected", "data grid rendered", "RDataCraft color token", "graph rendered", "native dirty state", "native project save", "saved state cleared", "SVG download", "PDF download", "PNG download", "new blank project", "blank project is clean", "blank project save", "project reopen", "represented project URL", "per-series format dialog", "per-series color renders", "structural row insertion", "native Undo and Redo", "schema 5 save/reopen", "multi-series fit results", "irrelevant analysis controls stay hidden", "vector PDF/SVG clipboard"] + studio + advanced + pca]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("report.json"))
            NSPasteboard.general.clearContents()
            let restoredClipboard=savedClipboard.map { entries -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in entries {item.setData(data,forType:type)};return item }
            NSPasteboard.general.writeObjects(restoredClipboard)
            stopEngine(); Darwin.exit(0)
        } catch { fail(error.localizedDescription) }
    }
    func advancedRChecks(_ folder:URL) async throws -> [String] {
        var checks:[String]=[]
        showHelp()
        try await waitUntil("document.querySelector('.help-center')!==null && document.querySelector('#help_content')?.textContent.includes('Getting started')===true")
        checks.append("native Help opens the offline in-app help center")
        _ = try await webView.evaluateJavaScript("var search=document.getElementById('help_search');search.value='vector';search.dispatchEvent(new Event('input',{bubbles:true}));search.dispatchEvent(new Event('change',{bubbles:true}));")
        try await waitUntil("document.querySelector('#help_content')?.textContent.includes('200%')===true && document.querySelector('#help_content')?.textContent.includes('SVG or PDF')===true")
        checks.append("Help search opens matching figure-size and vector-export instructions")
        guard try await webView.evaluateJavaScript("(()=>{const b=document.querySelector('.modal.show .modal-footer button').getBoundingClientRect();return b.bottom<=innerHeight-8 && b.top>=0})()") as? Bool == true else {throw HostError.failed("Help close button is outside the visible window.")}
        checks.append("Help keeps Close visible while long instructions scroll")
        try imageData(try await webView.takeSnapshot(configuration:nil)).write(to:folder.appendingPathComponent("help-center.png"))
        _ = try await webView.evaluateJavaScript("document.querySelector('.modal.show .modal-footer button').click()")
        try await waitUntil("document.querySelector('.modal.show')===null")
        send(["type":"open","path":backend.appendingPathComponent("examples/RDataCraft examples.rdatacraft").path])
        try await waitUntil("document.querySelector('#data_grid tbody td')!==null && !document.documentElement.classList.contains('shiny-busy')")
        _ = try await webView.evaluateJavaScript("Shiny.setInputValue('advanced_open',1,{priority:'event'})")
        try await waitUntil("document.getElementById('nav_advanced').classList.contains('active') && document.getElementById('r_run')!==null")
        checks.append("Advanced R is available from Analysis and the workspace")
        _ = try await webView.evaluateJavaScript("document.getElementById('r_load_template').click()")
        try await waitUntil("document.getElementById('r_code').value.includes('summary_table')")
        _ = try await webView.evaluateJavaScript("document.getElementById('r_run').click()")
        try await waitUntil("document.getElementById('r_status').textContent.includes('R success') && document.querySelector('#r_results img.r-result-figure')?.complete===true",timeout:45)
        checks.append("reviewed R script returns a table and vector figure")
        _ = try await webView.evaluateJavaScript("document.getElementById('r_help').click()")
        try await waitUntil("document.querySelector('.modal.show')?.textContent.includes('not an operating-system security sandbox')===true")
        checks.append("Advanced R help explains input, output, packages and review")
        _ = try await webView.evaluateJavaScript("document.querySelector('.modal.show .modal-footer button').click()")
        try await waitUntil("document.querySelector('.modal.show')===null")
        let file=folder.appendingPathComponent("Advanced R integration.rdatacraft")
        nextTestDestination=file;saveAs();try await waitForFile(file)
        let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any]
        guard saved?["schema_version"] as? Int==11,let runs=saved?["r_analyses"] as? [[String:Any]],runs.count==1,let result=runs[0]["result"] as? [String:Any],result["status"] as? String=="success" else {throw HostError.failed("Advanced R results did not persist in the study.")}
        checks.append("Advanced R code, input and results save in schema eleven")
        let capture=try await webView.takeSnapshot(configuration:nil);try imageData(capture).write(to:folder.appendingPathComponent("advanced-r-analysis.png"))
        send(["type":"open","path":file.path])
        try await waitUntil("document.getElementById('r_saved').selectize.items.length===1 && document.getElementById('r_status').textContent.includes('have not been executed')")
        checks.append("reopening stored custom analyses does not run code")
        _ = try await webView.evaluateJavaScript("var code=document.getElementById('r_code');code.value='result <- list(text=praise::praise())';code.dispatchEvent(new Event('change',{bubbles:true}));var pkgs=document.getElementById('r_packages');pkgs.value='praise';pkgs.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('r_pkg_check').click()")
        try await waitUntil("document.getElementById('r_pkg_approve')!==null && document.querySelector('.r-package-review')?.textContent.includes('praise')===true",timeout:90)
        guard !fm.fileExists(atPath:coordinator!.testFolder!.appendingPathComponent("optional-R-library").path) else {throw HostError.failed("Package checking wrote to the optional library before approval.")}
        checks.append("missing-package review lists exact versions before any installation")
        let approvalImage=try await webView.takeSnapshot(configuration:nil);try imageData(approvalImage).write(to:folder.appendingPathComponent("package-installation-approval.png"))
        _ = try await webView.evaluateJavaScript("document.getElementById('r_pkg_decline').click()")
        try await waitUntil("document.querySelector('.modal.show')===null && document.getElementById('r_status').textContent.includes('No packages were installed')")
        guard !fm.fileExists(atPath:coordinator!.testFolder!.appendingPathComponent("optional-R-library").path) else {throw HostError.failed("Cancel installed an optional package.")}
        checks.append("cancelling package approval leaves the personal library untouched")
        return checks
    }

    func multiwindowTest() async {
        guard let folder=testFolder,let app=coordinator else {return}
        var checks:[String]=[]
        func check(_ value:Bool,_ label:String) throws {if !value {throw HostError.failed(label)};checks.append(label)}
        func waitHost(_ condition:() -> Bool) async throws {
            let deadline=Date().addingTimeInterval(40)
            while !condition() && Date()<deadline {try await Task.sleep(nanoseconds:100_000_000)}
            if !condition() {throw HostError.failed("Timed out waiting for native window state.")}
        }
        func rename(_ controller:RDataCraftWindow,_ name:String) async throws {
            let json=String(data:try JSONSerialization.data(withJSONObject:[name]),encoding:.utf8)!
            _ = try await controller.webView.evaluateJavaScript("var s=document.getElementById('study_name');s.focus();s.value=(\(json))[0];s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));")
            try await waitHost {controller.studyName==name && controller.window.isDocumentEdited}
        }
        do {
            if fm.fileExists(atPath:folder.path),!(try fm.contentsOfDirectory(atPath:folder.path)).isEmpty {throw HostError.failed("Use a new empty native test folder.")}
            try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            try await waitUntil("document.body.dataset.runtime==='desktop' && !document.documentElement.classList.contains('shiny-busy')")
            try check(!hasDocument && app.windows.count==1,"empty startup has one welcome window")
            send(["type":"open","path":backend.appendingPathComponent("examples/PCA teaching example.rdatacraft").path])
            try await waitUntil("document.getElementById('layout').value==='multiple' && document.querySelector('#data_grid .dataTables_info')?.textContent.includes('12 entries')===true")
            try await rename(self,"Study A")
            newProject()
            try await waitHost {app.windows.count==2}
            let second=app.windows.last!
            try await second.waitUntil("document.body.dataset.runtime==='desktop' && document.querySelector('#data_grid tbody td')!==null && !document.documentElement.classList.contains('shiny-busy')")
            try await waitHost {second.hasDocument}
            try check(window.isDocumentEdited && studyName=="Study A","New Study preserves the first unsaved study")
            try check(second.studyName=="Untitled study" && !second.window.isDocumentEdited,"New Study opens a clean blank study in another window")
            try await second.waitUntil("Number(document.getElementById('width').value)===76.2 && Number(document.getElementById('height').value)===76.2 && Number(document.getElementById('font_size').value)===7 && document.getElementById('figure_zoom').value==='200'")
            try check(true,"new figures default to three by three inches, seven-point text and 200 percent display")
            try await second.waitUntil("Math.abs(parseFloat(getComputedStyle(document.body).fontSize)-14.52)<0.01 && Math.abs(parseFloat(getComputedStyle(document.querySelector('.toolbar-button')).fontSize)-13.552)<0.01 && Math.abs(parseFloat(getComputedStyle(document.querySelector('.control-label')).fontSize)-12.584)<0.01")
            try check(true,"interface body, toolbar and labels are ten percent larger")
            try await rename(second,"Study B")
            _ = try await second.webView.evaluateJavaScript("document.querySelector('#data_grid tbody td').click();window.RDataCraftGrid.pasteNative('123\\t456')")
            try await second.waitUntil("document.querySelector('#data_grid tbody td')?.textContent==='123'")
            try await waitUntil("document.getElementById('layout').value==='multiple' && document.querySelector('#data_grid .dataTables_info')?.textContent.includes('12 entries')===true")
            try check(studyName=="Study A" && second.studyName=="Study B","data and study names remain isolated")
            _ = try await second.webView.evaluateJavaScript("document.getElementById('method').selectize.setValue('descriptive')")
            second.showFigure()
            try await second.waitUntil("document.querySelector('#figure svg.graph-interactive')!==null && document.getElementById('figure_dimensions').textContent==='3.00 × 3.00 in · 200%' && !document.documentElement.classList.contains('shiny-busy')")
            try await second.waitUntil("Math.abs(document.getElementById('figure').getBoundingClientRect().width-576)<1 && Math.abs(document.getElementById('figure').getBoundingClientRect().height-576)<1")
            try check(true,"200 percent display doubles the preview while retaining the three-inch canvas")
            let defaultsImage=try await second.webView.takeSnapshot(configuration:nil)
            try imageData(defaultsImage).write(to:folder.appendingPathComponent("new-figure-defaults.png"))
            second.command("create")
            try await second.waitUntil("document.getElementById('create_dialog').open")
            _ = try await second.webView.evaluateJavaScript("document.querySelector('[data-create=study]').click()")
            try await waitHost {app.windows.count==3}
            let third=app.windows.last!
            try await third.waitUntil("document.querySelector('#data_grid tbody td')!==null && !document.documentElement.classList.contains('shiny-busy')")
            try await waitHost {third.hasDocument}
            try check(Set(app.windows.compactMap{$0.endpoint?.port}).count==3,"three windows use different local ports")
            try check(Set(app.windows.compactMap{$0.process?.processIdentifier}).count==3,"three windows use independent R engines")
            try check(Set(app.windows.map{$0.temporaryFolder.path}).count==3 && Set(app.windows.map{$0.logURL().path}).count==3,"scratch files and engine logs are isolated")
            second.windowDidBecomeKey(Notification(name:NSWindow.didBecomeKeyNotification,object:second.window))
            let fileMenu=NSApp.mainMenu?.items.first(where:{$0.submenu?.title=="File"})?.submenu
            try check(fileMenu?.items.first(where:{$0.title=="Save"})?.target === second,"menu Save targets the selected window")
            windowDidBecomeKey(Notification(name:NSWindow.didBecomeKeyNotification,object:window))
            try check(NSApp.mainMenu?.items.first(where:{$0.submenu?.title=="File"})?.submenu?.items.first(where:{$0.title=="Save"})?.target === self,"switching windows retargets menu commands")
            let fileA=folder.appendingPathComponent("Study A.rdatacraft"),fileB=folder.appendingPathComponent("Study B.rdatacraft")
            nextTestDestination=fileA;saveAs();try await waitForFile(fileA)
            second.nextTestDestination=fileB;second.saveAs();try await second.waitForFile(fileB)
            try await waitHost {!self.window.isDocumentEdited && !second.window.isDocumentEdited}
            let a=try JSONSerialization.jsonObject(with:Data(contentsOf:fileA)) as? [String:Any]
            let b=try JSONSerialization.jsonObject(with:Data(contentsOf:fileB)) as? [String:Any]
            try check(a?["study_name"] as? String=="Study A" && b?["study_name"] as? String=="Study B" && (b?["data_tsv"] as? String)?.contains("123")==true,"each window saves its own study and observations")
            try check(app.openProjectFile(fileA) === self && app.windows.count==3,"opening an existing project selects its existing window")
            let copied=folder.appendingPathComponent("Opened copy.rdatacraft");try fm.copyItem(at:fileA,to:copied)
            let opened=app.openProjectFile(copied)
            try await opened.waitUntil("document.getElementById('layout').value==='multiple' && document.querySelector('#data_grid .dataTables_info')?.textContent.includes('12 entries')===true")
            try await waitHost {opened.hasDocument && !opened.window.isDocumentEdited}
            try check(app.windows.count==4 && currentProject==fileA && second.currentProject==fileB,"opening another project preserves other windows")
            opened.window.performClose(nil)
            try check(app.windows.count==3 && opened.process?.isRunning==false && second.process?.isRunning==true,"closing a clean window stops only its own engine")
            try await rename(third,"Study C")
            third.testAlertResponses=[.alertThirdButtonReturn];third.window.performClose(nil)
            try check(app.windows.count==3 && third.process?.isRunning==true,"Cancel preserves an unsaved window")
            third.testAlertResponses=[.alertSecondButtonReturn];third.window.performClose(nil)
            try check(app.windows.count==2 && process?.isRunning==true && second.process?.isRunning==true,"closing one unsaved study leaves the other studies running")
            try await rename(self,"Study A revised");try await rename(second,"Study B revised")
            var quitReplies:[Bool]=[];app.testQuitReply={quitReplies.append($0)}
            testAlertResponses=[.alertSecondButtonReturn];second.testAlertResponses=[.alertThirdButtonReturn]
            try check(app.applicationShouldTerminate(NSApp) == .terminateLater,"Quit reviews all unsaved studies asynchronously")
            try await waitHost {!quitReplies.isEmpty}
            try check(quitReplies==[false] && window.isDocumentEdited && second.window.isDocumentEdited && app.windows.count==2,"Cancel during Quit preserves every unsaved study")
            quitReplies=[];testAlertResponses=[.alertFirstButtonReturn];second.testAlertResponses=[.alertFirstButtonReturn]
            _ = app.applicationShouldTerminate(NSApp)
            try await waitHost {!quitReplies.isEmpty}
            try check(quitReplies==[true] && !window.isDocumentEdited && !second.window.isDocumentEdited,"Quit waits for every chosen Save to finish")
            let savedA=try JSONSerialization.jsonObject(with:Data(contentsOf:fileA)) as? [String:Any]
            let savedB=try JSONSerialization.jsonObject(with:Data(contentsOf:fileB)) as? [String:Any]
            try check(savedA?["study_name"] as? String=="Study A revised" && savedB?["study_name"] as? String=="Study B revised","Quit saves changes to the correct project files")
            try JSONSerialization.data(withJSONObject:["status":"passed","checks":checks],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
            app.testQuitReply=nil;app.stopAll();Darwin.exit(0)
        } catch {fail(error.localizedDescription)}
    }
    func smokeTest() async {
        if CommandLine.arguments.contains(where:{$0.hasPrefix("--multiwindow-test=")}) {await multiwindowTest();return}
        if CommandLine.arguments.contains(where:{$0.hasPrefix("--workflow-test=") || $0.hasPrefix("--studio-test=")}) {await workflowTest();return}
        guard let folder = testFolder else { return }
        do {
            if fm.fileExists(atPath: folder.path), !(try fm.contentsOfDirectory(atPath: folder.path)).isEmpty {
                throw HostError.failed("Use a new empty folder for each native smoke test.")
            }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if CommandLine.arguments.contains(where:{$0.hasPrefix("--graph-test=")}) {
                let checks=try await graphTest(folder)
                try JSONSerialization.data(withJSONObject:["status":"passed","external_paste_tested":false,"checks":checks],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
                stopEngine();Darwin.exit(0)
            }
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--navigator-test=") }) {
                try await navigatorTest(folder); stopEngine(); Darwin.exit(0)
            }
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--paste-test=") }) {
                let checks = try await pasteTest(folder)
                try JSONSerialization.data(withJSONObject: ["status":"passed", "checks":checks], options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
                stopEngine(); Darwin.exit(0)
            }
            guard NSApp.mainMenu?.items.contains(where: { $0.submenu?.title == "File" }) == true else { throw HostError.failed("The native File menu is missing.") }
            try await waitUntil("document.body.dataset.runtime === 'desktop' && document.querySelector('#data_grid table') !== null")
            try await waitUntil("getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() === '#247763'")
            try await waitUntil("Math.abs(parseFloat(getComputedStyle(document.body).fontSize)-14.52)<0.01 && Math.abs(parseFloat(getComputedStyle(document.querySelector('.toolbar-button')).fontSize)-13.552)<0.01 && Math.abs(parseFloat(getComputedStyle(document.querySelector('.control-label')).fontSize)-12.584)<0.01")
            _ = try await webView.evaluateJavaScript("document.querySelector('[data-command=create]').click()")
            try await waitUntil("document.getElementById('create_dialog').open && document.querySelectorAll('[data-create]').length === 5")
            let chooserImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(chooserImage).write(to: folder.appendingPathComponent("create.png"))
            _ = try await webView.evaluateJavaScript("document.getElementById('close_create').click(); var s=document.getElementById('study_name'); s.focus(); s.value='Cancelled title'; s.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));")
            try await waitUntil("document.getElementById('study_name').value === 'RDataCraft'")
            _ = try await webView.evaluateJavaScript("var s=document.getElementById('study_name'); s.focus(); s.value='Renamed desktop study'; s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));")
            try await waitUntil("document.getElementById('study_name').value === 'Renamed desktop study' && !document.documentElement.classList.contains('shiny-busy')")
            let renameDeadline = Date().addingTimeInterval(10)
            while studyName != "Renamed desktop study" && Date() < renameDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard window.title.hasPrefix("Renamed desktop study — RDataCraft"), window.isDocumentEdited else { throw HostError.failed("Inline study rename did not update the native title and dirty state.") }
            let dataImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(dataImage).write(to: folder.appendingPathComponent("data.png"))
            showFigure()
            try await waitUntil("document.querySelector('#figure img')?.complete && document.querySelector('#figure img')?.naturalWidth > 0 && document.querySelector('#nav_figure').classList.contains('active')")
            let navColor = try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('nav_figure')).backgroundColor")
            logText("Navigation selection color: \(navColor ?? "unknown")\n")
            _ = try await webView.evaluateJavaScript("document.getElementById('title').value = 'Desktop test figure'; document.getElementById('title').dispatchEvent(new Event('change', {bubbles:true}));")
            let dirtyDeadline = Date().addingTimeInterval(10)
            while !window.isDocumentEdited && Date() < dirtyDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard window.isDocumentEdited else { throw HostError.failed("Changing a figure did not mark the native document edited.") }
            let project = folder.appendingPathComponent("Desktop test.rdatacraft")
            nextTestDestination = project; saveAs()
            try await waitForFile(project)
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: project)) as? [String: Any]
            guard saved?["study_name"] as? String == "Renamed desktop study" else { throw HostError.failed("Study name was not saved as project metadata.") }
            guard saved?["format"] as? String == "rdatacraft" else { throw HostError.failed("The saved document is not a RDataCraft project.") }
            let savedDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < savedDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("Saving did not clear the native edited state.") }
            for format in ["svg", "pdf", "png"] {
                let file = folder.appendingPathComponent("figure.\(format)")
                nextTestDestination = file; command("export-\(format)")
                try await waitForFile(file)
                let data = try Data(contentsOf: file)
                let valid = format == "svg" ? String(data: data, encoding: .utf8)?.contains("<svg") == true : format == "pdf" ? data.starts(with: Array("%PDF".utf8)) : data.starts(with: [137,80,78,71])
                guard valid else { throw HostError.failed("Invalid \(format) export.") }
            }
            send(["type":"new"])
            try await waitUntil("document.getElementById('title').value === 'Untitled figure' && document.querySelector('#nav_data').classList.contains('active')")
            let cleanDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < cleanDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("A newly created project is unexpectedly dirty.") }
            let blankProject = folder.appendingPathComponent("Blank study.rdatacraft")
            nextTestDestination = blankProject; saveAs()
            try await waitForFile(blankProject)
            let blank = try JSONSerialization.jsonObject(with: Data(contentsOf: blankProject)) as? [String: Any]
            guard (blank?["data_tsv"] as? String)?.contains("Control") == true else { throw HostError.failed("The blank project did not save its table headers.") }
            send(["type": "open", "path": project.path])
            try await waitUntil("document.getElementById('title').value === 'Desktop test figure'")
            try await waitUntil("document.getElementById('study_name').value === 'Renamed desktop study'")
            guard window.representedURL == project else { throw HostError.failed("The native window does not represent the saved project.") }
            showFigure()
            try await waitUntil("document.querySelector('#figure img')?.complete && document.querySelector('#figure img')?.naturalWidth > 0 && !document.querySelector('#figure').classList.contains('shiny-output-error')")
            let graphImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(graphImage).write(to: folder.appendingPathComponent("graph.png"))
            for layout in ["grouped", "contingency", "survival"] {
                _ = try await webView.evaluateJavaScript("document.querySelector('[data-command=create]').click(); document.querySelector('[data-create=worksheet]').click()")
                try await waitUntil("document.getElementById('confirm_worksheet') !== null")
                _ = try await webView.evaluateJavaScript("document.getElementById('worksheet_layout').selectize.setValue('\(layout)'); document.getElementById('worksheet_name').value='Desktop \(layout)'; document.getElementById('worksheet_name').dispatchEvent(new Event('change',{bubbles:true}));")
                try await waitUntil("document.querySelector('#worksheet_template .template-table table') !== null && !document.documentElement.classList.contains('shiny-busy')")
                let templateImage = try await webView.takeSnapshot(configuration: nil)
                try imageData(templateImage).write(to: folder.appendingPathComponent("template-\(layout).png"))
                _ = try await webView.evaluateJavaScript("document.getElementById('confirm_worksheet').click()")
                try await waitUntil("document.getElementById('layout').value === '\(layout)' && document.getElementById('confirm_worksheet') === null")
                showAnalysis()
                try await waitUntil("document.querySelector('#analysis_status .analysis-success') !== null && document.querySelector('#analysis_metrics table') !== null && !document.documentElement.classList.contains('shiny-busy')")
                showFigure()
                try await waitUntil("document.querySelector('#figure img')?.complete && document.querySelector('#figure img')?.naturalWidth > 0 && !document.querySelector('#figure').classList.contains('shiny-output-error') && !document.documentElement.classList.contains('shiny-busy')")
                _ = try await webView.evaluateJavaScript("document.querySelectorAll('.shiny-notification').forEach(el => el.remove())")
                let image = try await webView.takeSnapshot(configuration: nil)
                try imageData(image).write(to: folder.appendingPathComponent("\(layout).png"))
            }
            let workbook = folder.appendingPathComponent("Multi-table workbook.rdatacraft")
            nextTestDestination = workbook; saveAs()
            try await waitForFile(workbook)
            let book = try JSONSerialization.jsonObject(with: Data(contentsOf: workbook)) as? [String: Any]
            guard (book?["worksheets"] as? [String: Any])?.count == 4 else { throw HostError.failed("Workbook did not save all four data types.") }
            let html = folder.appendingPathComponent("Survival report.html")
            nextTestDestination = html
            showAnalysis()
            try await waitUntil("document.querySelector('#export_report')?.getAttribute('href')?.includes('/download/') === true")
            _ = try await webView.evaluateJavaScript("document.getElementById('export_report').click()")
            try await waitForFile(html)
            let reportText = try String(contentsOf: html, encoding: .utf8)
            guard reportText.contains("<svg"), reportText.contains("Number at risk"), reportText.contains("Log-rank") else { throw HostError.failed("Analysis report is missing its graph, survival analysis, or risk table.") }
            _ = try await webView.evaluateJavaScript("document.getElementById('worksheet').selectize.setValue('D1')")
            try await waitUntil("document.getElementById('title').value === 'Desktop test figure' && document.getElementById('layout').value === 'column'")
            send(["type": "open", "path": workbook.path])
            try await waitUntil("document.getElementById('layout').value === 'survival' && document.getElementById('worksheet').value === 'D4'")
            let workbookDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < workbookDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("Restored multi-table workbook did not return to clean state.") }
            _ = try await webView.evaluateJavaScript("document.getElementById('worksheet').selectize.setValue('D1')")
            try await waitUntil("document.getElementById('layout').value === 'column' && document.getElementById('title').value === 'Desktop test figure'")
            _ = try await webView.evaluateJavaScript("document.getElementById('new_view').click()")
            try await waitUntil("document.getElementById('confirm_new_view') !== null")
            _ = try await webView.evaluateJavaScript("document.getElementById('new_view_name').value='Distribution view'; document.getElementById('new_view_name').dispatchEvent(new Event('change',{bubbles:true}));")
            try await Task.sleep(nanoseconds: 300_000_000)
            _ = try await webView.evaluateJavaScript("document.getElementById('confirm_new_view').click()")
            try await waitUntil("document.getElementById('graph_view').value === 'V2' && document.getElementById('confirm_new_view') === null")
            _ = try await webView.evaluateJavaScript("document.getElementById('graph').selectize.setValue('box'); document.getElementById('method').selectize.setValue('anova'); document.getElementById('title').value='Distribution view'; document.getElementById('title').dispatchEvent(new Event('change',{bubbles:true})); document.getElementById('y_min').value='0'; document.getElementById('y_min').dispatchEvent(new Event('change',{bubbles:true})); document.getElementById('y_max').value='35'; document.getElementById('y_max').dispatchEvent(new Event('change',{bubbles:true}));")
            try await waitUntil("document.getElementById('method').value === 'anova' && document.getElementById('graph').value === 'box' && !document.documentElement.classList.contains('shiny-busy')")
            _ = try await webView.evaluateJavaScript("document.getElementById('graph_view').selectize.setValue('V1')")
            try await waitUntil("document.getElementById('title').value === 'Desktop test figure' && document.getElementById('method').value === 'welch'")
            _ = try await webView.evaluateJavaScript("document.getElementById('graph_view').selectize.setValue('V2')")
            try await waitUntil("document.getElementById('title').value === 'Distribution view' && document.getElementById('graph').value === 'box' && document.getElementById('y_max').value === '35'")
            showLayout()
            try await waitUntil("document.querySelector('#nav_layout').classList.contains('active')")
            _ = try await webView.evaluateJavaScript("document.getElementById('layout_height').value='100'; document.getElementById('layout_height').dispatchEvent(new Event('change',{bubbles:true})); document.getElementById('layout_use_views').click()")
            try await waitUntil("document.querySelectorAll('#layout_views input:checked').length === 2 && document.querySelector('#layout_figure img')?.complete && document.querySelector('#layout_figure img')?.naturalWidth > 0 && !document.querySelector('#layout_figure').classList.contains('shiny-output-error') && !document.documentElement.classList.contains('shiny-busy')")
            try await waitUntil("(() => { const img=document.querySelector('#layout_figure img'); if(!img?.complete || !img.naturalWidth) return false; const c=document.createElement('canvas'); c.width=img.naturalWidth; c.height=img.naturalHeight; const ctx=c.getContext('2d'); ctx.drawImage(img,0,0); const data=ctx.getImageData(0,0,c.width,c.height).data; let ink=0; for(let i=0;i<data.length;i+=4) if(data[i+3]>100 && Math.min(data[i],data[i+1],data[i+2])<180) ink++; return ink>500; })()")
            _ = try await webView.evaluateJavaScript("document.querySelectorAll('.shiny-notification').forEach(el => el.remove())")
            _ = try await webView.evaluateJavaScript("document.getElementById('layout_figure').scrollIntoView({block:'center'});")
            let layoutImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(layoutImage).write(to: folder.appendingPathComponent("layout.png"))
            let layoutPDF = folder.appendingPathComponent("Layout.pdf")
            nextTestDestination = layoutPDF; exportLayoutPDF()
            try await waitForFile(layoutPDF)
            guard try Data(contentsOf: layoutPDF).starts(with: Array("%PDF".utf8)) else { throw HostError.failed("Layout PDF export is invalid.") }
            let linkedFile = folder.appendingPathComponent("Linked views.rdatacraft")
            nextTestDestination = linkedFile; saveAs()
            try await waitForFile(linkedFile)
            let linked = try JSONSerialization.jsonObject(with: Data(contentsOf: linkedFile)) as? [String: Any]
            let linkedSheets = linked?["worksheets"] as? [String: Any]
            let firstSheet = linkedSheets?["D1"] as? [String: Any]
            guard (firstSheet?["views"] as? [String: Any])?.count == 2, linked?["schema_version"] as? Int == 3 else { throw HostError.failed("Linked graph views did not save in schema 3.") }
            _ = try await webView.evaluateJavaScript("document.getElementById('graph_view').selectize.setValue('V1')")
            try await waitUntil("document.getElementById('title').value === 'Desktop test figure'")
            send(["type": "open", "path": linkedFile.path])
            try await waitUntil("document.getElementById('graph_view').value === 'V2' && document.getElementById('title').value === 'Distribution view' && document.querySelectorAll('#layout_views input:checked').length === 2")
            let linkedDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < linkedDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("Reopening linked views did not restore clean state.") }
            _ = try await webView.evaluateJavaScript("document.getElementById('y_min').value='unfinished limit'; document.getElementById('y_min').dispatchEvent(new Event('change',{bubbles:true}));")
            let invalidDeadline = Date().addingTimeInterval(10)
            while !window.isDocumentEdited && Date() < invalidDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard window.isDocumentEdited else { throw HostError.failed("An invalid axis entry was not tracked as unsaved.") }
            _ = try await webView.evaluateJavaScript("document.getElementById('y_min').value='0'; document.getElementById('y_min').dispatchEvent(new Event('change',{bubbles:true}));")
            let correctedDeadline = Date().addingTimeInterval(10)
            while window.isDocumentEdited && Date() < correctedDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
            guard !window.isDocumentEdited else { throw HostError.failed("Restoring the saved axis limit did not clear the edited state.") }
            showData()
            try await waitUntil("document.querySelector('#nav_data').classList.contains('active') && document.querySelector('#data_grid tbody td')?.textContent === '8.4'")
            _ = try await webView.evaluateJavaScript("document.activeElement?.blur(); Shiny.setInputValue('data_grid_cell_edit',{row:1,col:0,value:'100'},{priority:'event'})")
            try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '100' && !document.getElementById('undo_data').disabled")
            undoEdit()
            try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '8.4' && !document.getElementById('redo_data').disabled")
            redoEdit()
            try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '100'")
            undoEdit()
            try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '8.4'")
            _ = try await webView.evaluateJavaScript("var q=document.getElementById('navigator_search'); q.value='Desktop grouped'; q.dispatchEvent(new Event('input',{bubbles:true}))")
            try await waitUntil("document.querySelectorAll('#project_navigator .navigator-family').length === 1 && document.querySelector('#project_navigator button[data-sheet=D2][data-page=figure]') !== null")
            _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator button[data-sheet=D2][data-page=figure]').click()")
            try await waitUntil("document.getElementById('layout').value === 'grouped' && document.querySelector('#nav_figure').classList.contains('active') && document.querySelector('#figure img')?.complete && !document.documentElement.classList.contains('shiny-busy')")
            _ = try await webView.evaluateJavaScript("var q=document.getElementById('navigator_search'); q.value=''; q.dispatchEvent(new Event('input',{bubbles:true}))")
            try await waitUntil("document.querySelectorAll('#project_navigator .navigator-family').length === 4")
            _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator button[data-sheet=D1][data-page=data]').click()")
            try await waitUntil("document.getElementById('layout').value === 'column' && document.querySelector('#data_grid tbody td')?.textContent === '8.4'")
            _ = try await webView.evaluateJavaScript("document.getElementById('duplicate_worksheet').click()")
            try await waitUntil("document.getElementById('confirm_duplicate_sheet') !== null")
            _ = try await webView.evaluateJavaScript("var n=document.getElementById('duplicate_sheet_name'); n.value='Desktop independent copy'; n.dispatchEvent(new Event('change',{bubbles:true})); document.getElementById('confirm_duplicate_sheet').click()")
            try await waitUntil("document.getElementById('worksheet').value === 'D5' && document.getElementById('graph_view').value === 'V2' && document.querySelectorAll('#project_navigator .navigator-family').length === 5")
            _ = try await webView.evaluateJavaScript("Shiny.setInputValue('data_grid_cell_edit',{row:1,col:0,value:'55'},{priority:'event'})")
            try await waitUntil("document.querySelector('#data_grid tbody td')?.textContent === '55'")
            _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator button[data-sheet=D1][data-page=data]').click()")
            try await waitUntil("document.getElementById('worksheet').value === 'D1' && document.querySelector('#data_grid tbody td')?.textContent === '8.4'")
            showFigure()
            _ = try await webView.evaluateJavaScript("document.getElementById('palette').selectize.setValue('monochrome'); var f=document.getElementById('font_size'); f.value='17'; f.dispatchEvent(new Event('change',{bubbles:true}))")
            try await waitUntil("!document.documentElement.classList.contains('shiny-busy')")
            _ = try await webView.evaluateJavaScript("document.getElementById('copy_graph_style').click()")
            try await waitUntil("document.querySelector('#format_targets input[value=\"D5:V2\"]') !== null")
            _ = try await webView.evaluateJavaScript("var target=document.querySelector('#format_targets input[value=\"D5:V2\"]'); target.checked=true; target.dispatchEvent(new Event('change',{bubbles:true})); document.getElementById('confirm_format').click()")
            try await waitUntil("document.getElementById('confirm_format') === null && !document.documentElement.classList.contains('shiny-busy')")
            _ = try await webView.evaluateJavaScript("document.querySelector('#project_navigator button[data-sheet=D5][data-view=V2][data-page=figure]').click()")
            try await waitUntil("document.getElementById('worksheet').value === 'D5' && document.getElementById('palette').value === 'monochrome' && document.getElementById('font_size').value === '17' && document.querySelector('#figure img')?.complete && document.querySelector('#figure img')?.naturalWidth > 0 && !document.documentElement.classList.contains('shiny-busy')")
            _ = try await webView.evaluateJavaScript("document.querySelectorAll('.shiny-notification').forEach(el=>el.remove())")
            try await waitUntil("(() => {const n=document.getElementById('project_navigator'); const e=n.querySelector('[aria-current=page]'); if(!e) return false; const a=n.getBoundingClientRect(), b=e.getBoundingClientRect(); return b.top>=a.top && b.bottom<=a.bottom+1;})()")
            let guideImage = try await webView.takeSnapshot(configuration: nil)
            try imageData(guideImage).write(to: folder.appendingPathComponent("navigator-and-formatting.png"))
            let reusedFile = folder.appendingPathComponent("Reused workflow.rdatacraft")
            nextTestDestination = reusedFile; saveAs()
            try await waitForFile(reusedFile)
            let reused = try JSONSerialization.jsonObject(with: Data(contentsOf: reusedFile)) as? [String: Any]
            guard (reused?["worksheets"] as? [String: Any])?.count == 5 else { throw HostError.failed("Duplicated family was not saved.") }
            send(["type":"open", "path":reusedFile.path])
            try await waitUntil("document.getElementById('worksheet').value === 'D5' && document.getElementById('palette').value === 'monochrome' && document.getElementById('undo_data').disabled")
            let report: [String: Any] = ["status": "passed", "native_window": true, "craft_color": "#247763", "bundled_engine_pid": process?.processIdentifier ?? 0, "endpoint": endpoint.absoluteString, "checks": ["selected navigator sheet stays visible", "native data undo", "native data redo", "searchable table navigator", "navigator selects an inactive graph", "independent family duplication", "duplicate edits preserve source", "graph formatting reuse", "workflow save and reopen", "project reopen clears data history", "interface text sizes", "explicit creation chooser", "rename cancellation", "inline study rename and native title", "study metadata save and reopen", "creation chooser adds worksheet", "native bridge connected", "data grid rendered", "RDataCraft color token", "graph rendered", "native dirty state", "native project save", "saved state cleared", "SVG download", "PDF download", "PNG download", "new blank project", "blank project is clean", "blank project save", "project reopen", "represented project URL", "grouped template and graph", "contingency template and graph", "survival template and graph", "multi-table workbook save", "analysis HTML download with embedded SVG", "number at risk report", "worksheet switch", "multi-table workbook reopen", "restored workbook clean state", "linked view creation", "independent analysis and graph settings", "switch back to original view", "linked view restoration", "layout preview", "layout PDF download", "layout state saved", "schema 3 workbook reopen", "restored views clean state", "invalid axis dirty state", "corrected axis clean state"]]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("report.json"))
            stopEngine(); Darwin.exit(0)
        } catch { fail(error.localizedDescription) }
    }
    func imageData(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw HostError.failed("Could not capture the application view.") }
        return png
    }
}

@main
struct RDataCraftMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = RDataCraftApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
