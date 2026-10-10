import ScreenSaver
import SpriteKit

@objc(GGSaverView)
final class GGSaverView: ScreenSaverView {
    private let skView: SKView
    private var options = Options.load()
    private lazy var sheet: OptionsSheet = {
        let sheet = OptionsSheet()
        sheet.onSave = { [weak self] options in
            self?.options = options
            self?.present()
        }
        return sheet
    }()

    override init?(frame: NSRect, isPreview: Bool) {
        skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1 / 60

        skView.autoresizingMask = [.width, .height]
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        addSubview(skView)

        // Since macOS 14, legacyScreenSaver keeps running after the saver is
        // dismissed, and each start adds another instance. Quit when told the
        // saver is stopping. The preview runs in System Settings, so skip it.
        if !isPreview {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(willStop(_:)),
                name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func willStop(_ note: Notification) {
        exit(0)
    }

    override func startAnimation() {
        super.startAnimation()
        if skView.scene == nil { present() }
        skView.isPaused = false
    }

    override func stopAnimation() {
        super.stopAnimation()
        skView.isPaused = true
    }

    // The view can arrive with a zero frame and be sized later, so build the
    // scene once the shape of the screen is known, and again if it changes.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let scene = skView.scene as? GGScene, newSize.height > 0 else { return }
        if abs(scene.aspect - newSize.width / newSize.height) > 0.01 { present() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if skView.scene != nil { present() }
    }

    override func draw(_ rect: NSRect) {}

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        sheet.show(options)
        return sheet.window
    }

    private func present() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let aspect = size.width / size.height
        let pixels = backing * size.height / GGScene.height
        let scene: GGScene
        switch options.scene {
        case .shapeFall: scene = ShapeFallScene(aspect: aspect, options: options, pixelsPerPoint: pixels)
        case .warningRain: scene = WarningRainScene(aspect: aspect, options: options, pixelsPerPoint: pixels)
        }
        skView.presentScene(scene)
    }
}
