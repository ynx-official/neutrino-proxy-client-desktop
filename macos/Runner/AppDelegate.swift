import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Cmd+Q must quit the host-owned application, including its network core.
    // Dart retains the existing unsaved-edit confirmation before approval.
    guard let controller = sender.windows.compactMap({ $0.contentViewController as? FlutterViewController }).first else {
      return .terminateNow
    }
    FlutterMethodChannel(name: "cn.neutrino.lifecycle", binaryMessenger: controller.engine.binaryMessenger)
      .invokeMethod("requestQuit", arguments: nil)
    return .terminateCancel
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
