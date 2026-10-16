import AppKit
import Security
import Darwin

typealias Message = [String: Any]
let frameLimit = 8 * 1024 * 1024
let queueLimit = 16 * 1024 * 1024
enum HostError: Error { case protocolError, vaultError }

// Each child has private pipes. Payload forwarding never runs on the AppKit thread.
final class Child {
    let process = Process()
    let input = Pipe(), output = Pipe()
    let writes = DispatchQueue(label: "neutrino.pipe.write")
    let lock = NSLock()
    var queued = 0, incoming = 0
    var session = "", stopped = false
    var packet: ((Child, Message) -> Void)?
    var gone: ((Child) -> Void)?

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }
    func start() throws {
        try process.run()
        // Process closes the parent's unused ends when passed Pipe objects.
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { DispatchQueue.main.async { [self] in gone?(self) } }
            do {
                while true {
                    guard let header = try read(4) else { return }
                    let length = header.reduce(0) { ($0 << 8) | Int($1) }
                    guard length > 0, length <= frameLimit,
                          let bytes = try read(length),
                          let message = try JSONSerialization.jsonObject(with: bytes) as? Message else {
                        throw HostError.protocolError
                    }
                    lock.lock()
                    incoming += length
                    let full = incoming > queueLimit
                    lock.unlock()
                    if full { throw HostError.protocolError }
                    DispatchQueue.main.async { [self] in
                        lock.lock(); incoming -= length; lock.unlock()
                        if !stopped { packet?(self, message) }
                    }
                }
            } catch { return }
        }
    }
    func read(_ count: Int) throws -> Data? {
        var bytes = Data()
        while bytes.count < count {
            guard let part = try output.fileHandleForReading.read(upToCount: count - bytes.count),
                  !part.isEmpty else { return nil }
            bytes.append(part)
        }
        return bytes
    }
    func send(_ message: Message) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: message),
              bytes.count <= frameLimit else { stop(); return }
        var length = UInt32(bytes.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(bytes)
        lock.lock()
        let full = stopped || queued + frame.count > queueLimit
        if !full { queued += frame.count }
        lock.unlock()
        if full { stop(); return }
        writes.async { [self, frame] in
            do { try input.fileHandleForWriting.write(contentsOf: frame) }
            catch { DispatchQueue.main.async { [self] in stop() } }
            lock.lock(); queued -= frame.count; lock.unlock()
        }
    }
    func stop() {
        lock.lock(); let wasStopped = stopped; stopped = true; lock.unlock()
        if wasStopped { return }
        // Close stdin first so the worker can release sockets on parent EOF.
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

func vault(_ message: Message) throws -> Any {
    guard let key = message["key"] as? String,
          key.hasPrefix("neutrino.flutter."), key.utf8.count <= 160 else { throw HostError.vaultError }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "flutter_secure_storage_service",
        kSecAttrAccount as String: key,
        kSecAttrSynchronizable as String: false,
        kSecUseDataProtectionKeychain as String: false
    ]
    switch message["op"] as? String {
    case "read":
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return NSNull() }
        guard status == errSecSuccess, let bytes = result as? Data,
              let text = String(data: bytes, encoding: .utf8) else { throw HostError.vaultError }
        return text
    case "write":
        guard let text = message["value"] as? String else { throw HostError.vaultError }
        let values = [kSecValueData as String: Data(text.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw HostError.vaultError }
    case "delete":
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw HostError.vaultError }
    default: throw HostError.vaultError
    }
    return NSNull()
}

final class Host: NSObject, NSApplicationDelegate {
    var core: Child?, ui: Child?
    var item: NSStatusItem!
    var connectedIcon: NSImage?, disconnectedIcon: NSImage?
    var state: Message = [:]
    var counter = 0, generation = 0
    var wanted = false, quitting = false, showOnReady = true
    var failures: [Date] = []
    var route = "connection", shutdownID = ""
    var lockFD: Int32 = -1
    let root = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
    let notification = Notification.Name("cn.neutrino.desktop.activate")
    let bundleID = "cn.neutrino.neutrinoProxyClientDesktop"
    lazy var data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(bundleID)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            lockFD = Darwin.open(data.appendingPathComponent("host.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard lockFD >= 0 else { throw HostError.protocolError }
            if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
                DistributedNotificationCenter.default().post(name: self.notification, object: bundleID)
                NSApp.terminate(nil); return
            }
            fcntl(lockFD, F_SETFD, FD_CLOEXEC)
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(openWindow), name: self.notification, object: bundleID)
            showOnReady = !CommandLine.arguments.contains("--background")
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let icon = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/neutrino-tray.png")
            if let base = NSImage(contentsOf: icon) {
                connectedIcon = statusIcon(base, connected: true)
                disconnectedIcon = statusIcon(base, connected: false)
            }
            updateMenu()
            try startCore()
        } catch {
            let alert = NSAlert()
            alert.messageText = "后台启动失败"
            alert.informativeText = "请确认应用完整、配置目录可写，然后重试。"
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func child(_ name: String, _ arguments: [String]) throws -> Child {
        let child = Child(executable: root.appendingPathComponent(name), arguments: arguments)
        child.packet = { [weak self] child, message in self?.receive(child, message) }
        child.gone = { [weak self] child in self?.gone(child) }
        try child.start()
        return child
    }
    func startCore() throws {
        #if arch(arm64)
        let name = "neutrino_worker_arm64"
        #else
        let name = "neutrino_worker_x64"
        #endif
        let trust = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/App.framework/Resources/flutter_assets/assets/test.jks")
        core = try child(name, [data.path, trust.path])
    }
    @discardableResult func command(_ op: String) -> String {
        counter += 1
        let id = "host-\(counter)"
        core?.send(["kind": "request", "version": 1, "id": id, "op": op,
                    "source": "host", "session": "host", "params": Message()])
        return id
    }
    @objc func openWindow() { openPage("connection") }
    @objc func openLogs() { openPage("logs") }
    func openPage(_ page: String) {
        if quitting { return }
        route = page
        if ui == nil {
            do {
                ui = try child("neutrino_ui", ["--hosted"])
                generation += 1; ui?.session = "\(generation)"
            } catch { return }
        }
        ui?.send(["kind": "activate", "route": route, "trayReady": true])
    }
    @objc func connect() {
        let config = state["config"] as? Message ?? [:]
        if core != nil, state["ready"] as? Bool == true,
           state["hasLicense"] as? Bool != true || (config["server"] as? String ?? "").isEmpty {
            openPage("settings"); return
        }
        wanted = true
        if core == nil { failures.removeAll(); try? startCore() }
        else { command("connect") }
    }
    @objc func disconnect() { wanted = false; command("disconnect") }
    @objc func requestQuit() {
        if let ui { ui.send(["kind": "prepareQuit"]) } else { quit() }
    }
    func quit() {
        if quitting { return }
        quitting = true; wanted = false
        if core == nil { NSApp.terminate(nil); return }
        shutdownID = command("shutdown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { NSApp.terminate(nil) }
    }
    func updateMenu() {
        let engine = state["engine"] as? Message ?? [:]
        let phase = engine["state"] as? String ?? "idle"
        item.button?.image = phase == "connected" ? connectedIcon : disconnectedIcon
        let active = phase != "idle" && phase != "error"
        let labels = ["idle": "尚未连接", "connected": "已连接", "connecting": "正在连接",
                      "authenticating": "正在认证", "reconnecting": "等待重连", "error": "连接失败"]
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Neutrino · \(labels[phase] ?? phase)", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        item.button?.toolTip = title.title
        let displayed = active ? engine["activeConfig"] ?? state["config"] : state["config"]
        if let config = displayed as? Message, let server = config["server"] as? String {
            let line = NSMenuItem(title: "\(server):\(config["port"] ?? "")", action: nil, keyEquivalent: "")
            line.isEnabled = false; menu.addItem(line)
        }
        menu.addItem(.separator())
        func add(_ title: String, _ action: Selector, _ enabled: Bool = true) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; entry.isEnabled = enabled; menu.addItem(entry)
        }
        add("打开主窗口", #selector(openWindow)); add("查看日志", #selector(openLogs))
        add(active ? "断开连接" : "连接", active ? #selector(disconnect) : #selector(connect), core == nil || state["ready"] as? Bool == true)
        menu.addItem(.separator()); add("退出应用", #selector(requestQuit))
        item.menu = menu
    }
    func receive(_ child: Child, _ message: Message) {
        let kind = message["kind"] as? String ?? ""
        if child === core {
            switch kind {
            case "ready":
                guard message["version"] as? Int == 1 else { quit(); return }
                command("snapshot")
                if wanted { command("connect") }
                if let ui { core?.send(["kind": "request", "version": 1, "id": "reattach", "op": "attach", "source": "ui", "session": ui.session]) }
                if showOnReady { showOnReady = false; openWindow() }
            case "vault":
                var reply: Message = ["kind": "vaultResult", "id": message["id"] ?? ""]
                do { reply["result"] = try vault(message) }
                catch { reply["error"] = "System vault unavailable" }
                core?.send(reply)
            case "state":
                guard var value = message["data"] as? Message else { return }
                ui?.send(message)
                var engine = value["engine"] as? Message ?? [:]
                if engine["state"] as? String == "error" { wanted = false }
                engine["logs"] = [Any](); value["engine"] = engine
                state = value; updateMenu()
            case "response":
                if message["source"] as? String == "ui", message["session"] as? String == ui?.session { ui?.send(message) }
                if quitting, message["source"] as? String == "host", message["id"] as? String == shutdownID { NSApp.terminate(nil) }
            default: break
            }
        } else if child === ui {
            switch kind {
            case "request":
                var request = message
                guard let core else {
                    request["kind"] = "response"; request["error"] = "网络内核已退出，请从菜单栏重试。"
                    ui?.send(request); return
                }
                let op = message["op"] as? String ?? ""
                if op == "shutdown" { return }
                if op == "connect" || (op == "save" && (message["params"] as? Message)?["reconnect"] as? Bool == true) { wanted = true }
                if op == "disconnect" { wanted = false }
                request["source"] = "ui"; request["session"] = child.session
                core.send(request)
            case "uiReady": ui?.send(["kind": "activate", "route": route, "trayReady": true])
            case "quitApproved": quit()
            default: break
            }
        }
    }
    func gone(_ child: Child) {
        child.stop()
        if child === ui {
            core?.send(["kind": "request", "version": 1, "source": "host", "session": child.session, "id": "detach", "op": "detach"])
            ui = nil
        } else if child === core {
            core = nil
            if quitting { NSApp.terminate(nil); return }
            state["ready"] = false; state["epoch"] = "stopped"
            state["error"] = "网络内核已退出，正在尝试恢复。"
            state["engine"] = ["state": "error", "logs": [Any]()]
            ui?.send(["kind": "state", "data": state]); updateMenu()
            failures.removeAll { Date().timeIntervalSince($0) > 300 }
            if failures.count < 3 {
                let delay = [1.0, 3.0, 10.0][failures.count]
                failures.append(Date())
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, !quitting, core == nil else { return }
                    try? startCore()
                }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !quitting, core != nil { requestQuit(); return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        ui?.stop(); core?.stop()
        if lockFD >= 0 { Darwin.close(lockFD) }
    }
}

func statusIcon(_ base: NSImage, connected: Bool) -> NSImage {
    // The drawing handler keeps the badge sharp on Retina displays. Cache both
    // images in the host so state updates do not require Flutter or new images.
    let size: CGFloat = 18
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
        base.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        let center = NSPoint(x: size * 0.78, y: size * 0.78)
        let radius = size * 0.16, outer = size * 0.20
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - outer, y: center.y - outer,
                                  width: outer * 2, height: outer * 2)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let color = connected
            ? NSColor(srgbRed: 57 / 255.0, green: 191 / 255.0, blue: 69 / 255.0, alpha: 1)
            : NSColor(srgbRed: 146 / 255.0, green: 151 / 255.0, blue: 160 / 255.0, alpha: 1)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)).fill()
        return true
    }
}

signal(SIGPIPE, SIG_IGN)
let application = NSApplication.shared
let host = Host()
application.delegate = host
application.setActivationPolicy(.accessory)
application.run()
