import SpriteKit

/// What the scenes share: a world of fixed height drawn on a ggplot2 panel.
/// Every scene is `height` points tall, so motion looks the same on every
/// screen and in the System Settings preview.
class GGScene: SKScene {
    static let height: CGFloat = 900

    let aspect: CGFloat
    let options: Options

    /// Device pixels per scene point, for crisp textures.
    let pixels: CGFloat

    private var lastTime: TimeInterval?

    init(aspect: CGFloat, options: Options, pixelsPerPoint: CGFloat) {
        self.aspect = aspect
        self.options = options
        pixels = pixelsPerPoint
        super.init(size: CGSize(width: GGScene.height * aspect, height: GGScene.height))
        scaleMode = .fill
        anchorPoint = .zero
        backgroundColor = .black
        addChild(panel())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The panel the scene draws on.
    var theme: GGTheme { options.theme }

    /// Seconds since the previous frame, capped so a stall doesn't jump ahead.
    func step(_ currentTime: TimeInterval) -> TimeInterval {
        let dt = min(currentTime - (lastTime ?? currentTime), 1.0 / 30)
        lastTime = currentTime
        return dt
    }

    /// Renders at device resolution into a context scaled to scene points.
    func render(_ area: CGSize, draw: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((area.width * pixels).rounded(.up)))
        let h = max(1, Int((area.height * pixels).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: pixels, y: pixels)
        draw(ctx)
        return ctx.makeImage()!
    }

    private func panel() -> SKSpriteNode {
        let image = render(size) { ctx in
            theme.drawPanel(ctx, size: size, pixel: 1 / pixels)
        }
        let node = SKSpriteNode(texture: SKTexture(cgImage: image), size: size)
        node.anchorPoint = .zero
        node.zPosition = -1
        return node
    }
}
