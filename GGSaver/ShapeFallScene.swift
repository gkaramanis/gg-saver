import SpriteKit

private enum Tune {
    static let radius: CGFloat = 1 / 30       // shape size as a share of panel height
    static let gravity: CGFloat = 2.5         // panel heights per s²
    static let fillTo: CGFloat = 0.7          // pile height that ends the fill
    static let pileArea: CGFloat = 7          // glyph units² one piled shape takes, gaps included
    static let hold: TimeInterval = 4         // s with a full pile before it drains
    static let restAfter: TimeInterval = 0.5  // s a shape must stay still to count as piled
    static let maxDrain: TimeInterval = 10
}

final class ShapeNode: SKSpriteNode {
    var rest: TimeInterval = 0
}

/// Shape fall: the 26 pch shapes tumble into the panel, pile up, then drain away.
final class ShapeFallScene: GGScene {
    private enum Phase { case fill, hold, drain }

    private let r: CGFloat
    private let unit: CGFloat
    private let spawnEvery: TimeInterval
    private let maxShapes: Int
    private let maxFill: TimeInterval
    private let floor = SKNode()

    private var phase = Phase.fill
    private var clock: TimeInterval = 0
    private var spawnClock: TimeInterval = 0
    private var lastStep: TimeInterval = 0
    private var bag: [Int] = []
    private var shapes: [ShapeNode] = []
    private var textures: [Int: SKTexture] = [:]

    override init(aspect: CGFloat, options: Options, pixelsPerPoint: CGFloat) {
        let size = CGSize(width: GGScene.height * aspect, height: GGScene.height)
        r = size.height * Tune.radius
        unit = r / 1.5

        // Spawn at the rate that fills the pile in the chosen time. The caps
        // only end a fill that never reaches its height.
        let expected = max(1, Int(size.width * size.height * Tune.fillTo / (Tune.pileArea * unit * unit)))
        spawnEvery = options.fillTime.seconds / Double(expected)
        maxShapes = 2 * expected
        maxFill = 3 * options.fillTime.seconds
        super.init(aspect: aspect, options: options, pixelsPerPoint: pixelsPerPoint)

        // SpriteKit gravity is in m/s² at 150 points per metre.
        physicsWorld.gravity = CGVector(dx: 0, dy: -Tune.gravity * size.height / 150)

        addWalls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Cycle

    override func update(_ currentTime: TimeInterval) {
        let dt = step(currentTime)
        lastStep = dt
        clock += dt

        switch phase {
        case .fill:
            spawnClock += dt
            while spawnClock >= spawnEvery {
                spawnClock -= spawnEvery
                spawn()
            }
            if pileHeight() > size.height * Tune.fillTo || shapes.count >= maxShapes || clock > maxFill {
                begin(.hold)
            }
        case .hold:
            if clock > Tune.hold { begin(.drain) }
        case .drain:
            let gone = -3 * r
            shapes.removeAll { node in
                guard node.position.y < gone else { return false }
                node.removeFromParent()
                return true
            }
            if shapes.isEmpty || clock > Tune.maxDrain { reset() }
        }
    }

    override func didSimulatePhysics() {
        let slow = size.height * 0.05
        for node in shapes {
            guard let body = node.physicsBody else { continue }
            let v = body.velocity
            let still = body.isResting || (hypot(v.dx, v.dy) < slow && !body.allContactedBodies().isEmpty)
            node.rest = still ? node.rest + lastStep : 0
        }
    }

    private func begin(_ next: Phase) {
        phase = next
        clock = 0
        if next == .drain {
            floor.physicsBody = nil
            for node in shapes { node.physicsBody?.isResting = false }
        }
    }

    private func reset() {
        for node in shapes { node.removeFromParent() }
        shapes.removeAll()
        floor.physicsBody = floorBody()
        phase = .fill
        clock = 0
        spawnClock = 0
    }

    /// Height of the settled pile: the highest shape that has been still a while.
    private func pileHeight() -> CGFloat {
        var top: CGFloat = 0
        for node in shapes where node.rest > Tune.restAfter {
            top = max(top, node.position.y + r)
        }
        return top
    }

    // MARK: Shapes

    /// Deals all 26 shapes in a random order before repeating any.
    private func nextShape() -> Int {
        if bag.isEmpty { bag = Array(0..<26).shuffled() }
        return bag.removeLast()
    }

    private func spawn() {
        let pch = nextShape()
        let colour: Int? = options.shapeColour == .palette ? Int.random(in: 0..<Palette.hue.count) : nil
        let side = 2 * Glyph.extent * unit
        let node = ShapeNode(texture: texture(pch: pch, colour: colour), size: CGSize(width: side, height: side))
        node.position = CGPoint(x: CGFloat.random(in: r...(size.width - r)),
                                y: size.height + r * CGFloat.random(in: 1.5...4))
        node.zRotation = CGFloat.random(in: 0..<(2 * .pi))

        let body = Glyph.body(pch, unit: unit)
        body.friction = 0.5
        body.restitution = 0.1
        body.linearDamping = 0.2
        body.angularDamping = 1.0
        body.velocity = CGVector(dx: CGFloat.random(in: -0.15...0.15) * size.height, dy: -0.2 * size.height)
        body.angularVelocity = CGFloat.random(in: -4...4)
        node.physicsBody = body

        addChild(node)
        shapes.append(node)
    }

    private func texture(pch: Int, colour: Int?) -> SKTexture {
        let key = pch * 100 + (colour ?? 99)
        if let cached = textures[key] { return cached }
        let side = 2 * Glyph.extent * unit
        let image = render(CGSize(width: side, height: side)) { ctx in
            ctx.translateBy(x: side / 2, y: side / 2)
            ctx.scaleBy(x: unit, y: unit)
            Glyph.draw(pch, in: ctx, colour: colour.map { Palette.hue[$0] }, ink: Palette.ink)
        }
        let made = SKTexture(cgImage: image)
        textures[key] = made
        return made
    }

    // MARK: Walls

    private func addWalls() {
        let top = size.height + 12 * r
        for x in [0, size.width] {
            let wall = SKNode()
            let body = SKPhysicsBody(edgeFrom: CGPoint(x: x, y: -10 * r), to: CGPoint(x: x, y: top))
            body.friction = 0.5
            wall.physicsBody = body
            addChild(wall)
        }
        floor.physicsBody = floorBody()
        addChild(floor)
    }

    private func floorBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(edgeFrom: .zero, to: CGPoint(x: size.width, y: 0))
        body.friction = 0.6
        return body
    }
}
