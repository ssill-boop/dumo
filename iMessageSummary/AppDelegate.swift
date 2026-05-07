import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var config: AppConfig!

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = AppConfig.load()
        #if DEBUG
        iMessageDB.runConsoleSmokeTest()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
