import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    private var screenParametersObserver: NSObjectProtocol?

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()

        self.pinToPrimaryScreen()

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

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pinToPrimaryScreen()
        }

        super.awakeFromNib()
    }

    deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(Self.primaryScreenFrame, display: flag)
    }

    private func pinToPrimaryScreen() {
        super.setFrame(Self.primaryScreenFrame, display: true)
    }

    private static var primaryScreenFrame: NSRect {
        NSScreen.screens.first?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }
}
