import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        self.setFrame(screenFrame, display: true)

        self.contentViewController = flutterViewController

        flutterViewController.backgroundColor = .clear

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false

        self.styleMask = [.borderless, .fullSizeContentView]
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if let screen = NSScreen.main {
            super.setFrame(screen.frame, display: flag)
        } else {
            super.setFrame(frameRect, display: flag)
        }
    }
}