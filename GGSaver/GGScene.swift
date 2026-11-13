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
        addChild(edges())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The panel the scene draws on.
    var theme: GGTheme { options.theme }

    /// White plot margin around the panel, in points.
    var plotMargin: CGFloat { 0 }

    /// Where the panel sits in the scene.
    var panelRect: CGRect { CGRect(origin: .zero, size: size).insetBy(dx: plotMargin, dy: plotMargin) }

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
        let inner = panelRect
        return sprite(z: -1) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.translateBy(x: inner.minX, y: inner.minY)
            theme.drawPanel(ctx, size: inner.size, pixel: 1 / pixels)
        }
    }

    /// The plot margin and the panel's edges, drawn over the scene so shapes
    /// that cross the panel's edge are clipped by it.
    private func edges() -> SKSpriteNode {
        let inner = panelRect
        return sprite(z: 10) { ctx in
            if plotMargin > 0 {
                ctx.addRect(CGRect(origin: .zero, size: size))
                ctx.addRect(inner)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fillPath(using: .evenOdd)
            }
            ctx.translateBy(x: inner.minX, y: inner.minY)
            theme.drawEdges(ctx, size: inner.size)
        }
    }

    private func sprite(z: CGFloat, draw: (CGContext) -> Void) -> SKSpriteNode {
        let node = SKSpriteNode(texture: SKTexture(cgImage: render(size, draw: draw)), size: size)
        node.anchorPoint = .zero
        node.zPosition = z
        return node
    }
}
