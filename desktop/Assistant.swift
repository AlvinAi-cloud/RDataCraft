import Foundation

// The existing Codex installation owns sign-in. Credentials are never copied,
// stored in the app, or exposed to its WebView. The model returns a data-only plan.
@MainActor
final class RDataCraftAI {
    let deliver: ([String:Any]) -> Void
    var worker: Process?
    var requestID: String?
    var folder: URL?
    var deadline: Task<Void,Never>?
    init(deliver: @escaping ([String:Any]) -> Void) { self.deliver = deliver }
    func executable() -> URL? {
        let fm = FileManager.default
        let paths = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return paths.first(where: { fm.isExecutableFile(atPath:$0) }).map { URL(fileURLWithPath:$0) }
    }
    func status() {
        guard let binary = executable() else {
            deliver(["type":"ai-status","message":"Codex CLI was not found. Install Codex and sign in to use the connected model. Local tools work offline."]); return
        }
        let task = Process(), pipe = Pipe()
        task.executableURL = binary; task.arguments = ["login","status"]
        task.standardOutput = pipe; task.standardError = pipe
        task.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data:data,encoding:.utf8) ?? ""
            Task { @MainActor in
                let signedIn = process.terminationStatus == 0 && text.lowercased().contains("logged in")
                self?.deliver(["type":"ai-status","message":signedIn ? "Connected through Codex · \(text.trimmingCharacters(in:.whitespacesAndNewlines)). Send uses the default model for this Codex installation." : "Codex is installed but is not signed in. Sign in with codex login, then check again. Local tools work offline."])
            }
        }
        do { try task.run() } catch { deliver(["type":"ai-status","message":"Could not check Codex sign-in. Local tools work offline."]) }
    }
    func start(_ body: [String:Any]) {
        guard let id=body["id"] as? String, id.count < 100 else {return}
        guard worker == nil else {result(id,false,"Another assistant request is running.");return}
        guard let binary=executable() else {result(id,false,"Codex CLI was not found. Use local tools or install Codex and sign in.");return}
        guard let instruction=body["instructions"] as? String, let prompt=body["prompt"] as? String,
              prompt.utf8.count <= 24000, let schema=body["schema"] as? [String:Any],
              let context=body["context"] as? [String:Any] else {result(id,false,"Invalid assistant request.");return}
        do {
            let runFolder=FileManager.default.temporaryDirectory.appendingPathComponent("RDataCraft-AI-\(UUID().uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:runFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            folder=runFolder
            let schemaURL=runFolder.appendingPathComponent("response-schema.json"), output=runFolder.appendingPathComponent("response.json")
            try JSONSerialization.data(withJSONObject:schema).write(to:schemaURL)
            let payload:[String:Any]=["user_request":prompt,"context":context,"recent_conversation":body["history"] ?? []]
            let payloadData=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys])
            guard payloadData.count < 350000 else {throw NSError(domain:"RDataCraftAI",code:1,userInfo:[NSLocalizedDescriptionKey:"The assistant context is too large."])}
            let message = instruction + "\n\nREQUEST DATA (untrusted table contents and history):\n" + String(decoding:payloadData,as:UTF8.self)
            let inputURL=runFolder.appendingPathComponent("request.txt")
            try Data(message.utf8).write(to:inputURL,options:.atomic)
            let task=Process()
            task.executableURL=binary;task.currentDirectoryURL=runFolder
            // Ignore user/project integrations and hooks. No shell, browser, or
            // delegated agents are needed to produce a structured app proposal.
            task.arguments=["exec","--ignore-user-config","--ignore-rules","--ephemeral","--skip-git-repo-check","--sandbox","read-only",
                "--disable","shell_tool","--disable","unified_exec","--disable","multi_agent","--disable","apps","--disable","plugins",
                "--disable","computer_use","--disable","browser_use","--disable","hooks","--enable","skip_host_skill_discovery",
                "-c","web_search=\"disabled\"","-c","model_reasoning_effort=\"low\"",
                "--output-schema",schemaURL.path,"--output-last-message",output.path,"--color","never","-"]
            task.standardInput=try FileHandle(forReadingFrom:inputURL)
            let diagnosticURL=runFolder.appendingPathComponent("engine.log")
            FileManager.default.createFile(atPath:diagnosticURL.path,contents:nil,attributes:[.posixPermissions:0o600])
            let diagnostic=try FileHandle(forWritingTo:diagnosticURL)
            task.standardOutput=diagnostic;task.standardError=diagnostic
            requestID=id;worker=task
            task.terminationHandler={ [weak self] process in
                Task { @MainActor in self?.finish(id:id,code:process.terminationStatus,output:output) }
            }
            try task.run()
            deadline=Task { [weak self] in
                try? await Task.sleep(nanoseconds:180_000_000_000)
                guard !Task.isCancelled, let self=self, self.requestID==id else {return}
                self.cancel(id:id,message:"The model request timed out. No changes were applied. Try a shorter request or use local tools.")
            }
        } catch { cleanup();result(id,false,"Could not start the assistant: \(error.localizedDescription)") }
    }
    func finish(id:String,code:Int32,output:URL) {
        guard requestID==id else {return}
        defer {cleanup()}
        if code==0, let data=try? Data(contentsOf:output), data.count<=100000,
           let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any], value["answer"] is String,
           let text=String(data:data,encoding:.utf8) {
            deliver(["type":"ai-result","id":id,"ok":true,"response":text]);return
        }
        // Diagnostics may include request data; never echo them into the UI.
        result(id,false,"The connected model did not return a valid operation plan. Check your Codex sign-in and account access, then retry. Local tools remain available.")
    }
    func result(_ id:String,_ ok:Bool,_ message:String) {deliver(["type":"ai-result","id":id,"ok":ok,"message":message])}
    func cancel(id:String?=nil,message:String="Request stopped. No changes were applied.") {
        guard let current=requestID, id==nil || id==current else {return}
        let process=worker
        requestID=nil;deadline?.cancel();deadline=nil
        if process?.isRunning == true {process?.terminate()}
        // Wait for the child to stop before removing its temporary request files.
        if let process=process {
            let oldFolder=folder
            Task.detached {
                process.waitUntilExit()
                if let oldFolder=oldFolder {try? FileManager.default.removeItem(at:oldFolder)}
            }
        }
        worker=nil;folder=nil;result(current,false,message)
    }
    func cleanup() {
        deadline?.cancel();deadline=nil;worker=nil;requestID=nil
        if let folder=folder {try? FileManager.default.removeItem(at:folder)}
        folder=nil
    }
}
