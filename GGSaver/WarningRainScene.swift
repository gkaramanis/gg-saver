import AppKit
import CoreText
import SpriteKit

private enum Tune {
    static let rows: CGFloat = 45                         // text rows on the panel
    static let pitch: CGFloat = 0.9                       // column spacing, in row heights
    static let speed: ClosedRange<CGFloat> = 6...14       // rows per second, nearest depth
    static let trail: ClosedRange<CGFloat> = 18...40      // rows a character stays visible for
    static let depth: ClosedRange<CGFloat> = 0.55...1     // 1 is nearest
    static let scramble: TimeInterval = 0.05              // s between random glyphs in the head and in a decoding cell
    static let decode: TimeInterval = 0.2                 // s a landed cell scrambles before showing its character
    static let behind: CGFloat = 1.5                      // rows behind the head's centre that characters land
    static let fadeCurve: CGFloat = 1.6                   // > 1 lets the trail linger, then thin out
    static let halo: CGFloat = 2.4                        // halo diameter, in row heights
    static let haloAlpha: CGFloat = 0.35
    static let streak: CGFloat = 5                        // streak length, in row heights
    static let streakAlpha: CGFloat = 0.3
    static let firstWait: ClosedRange<TimeInterval> = 0...6
    static let wait: ClosedRange<TimeInterval> = 2...10   // s between messages in a column
    static let functionWait: ClosedRange<TimeInterval> = 0.5...4
}

/// Warning rain: ggplot2's functions, or its warnings and errors, run down
/// the panel in columns, like the rain in The Matrix. A glowing head of
/// scrambling glyphs slides down each column, and the message lands just
/// behind it, each character decoding before it settles. A column that
/// reaches the bottom carries on from the top, so the whole message gets written.
final class WarningRainScene: GGScene {
    private struct Drop {
        let text: [Character]
        let speed: CGFloat
        let fade: CGFloat
        let colour: SKColor
        let depth: CGFloat
        var head: CGFloat = 0
        var written = 0
        var scrambleClock: TimeInterval = 0
    }

    /// The moving parts of one column's head.
    private struct Head {
        let glyph: SKSpriteNode
        let halo: SKSpriteNode
        let streak: SKSpriteNode
    }

    private let messages: Messages
    private let wait: ClosedRange<TimeInterval>
    private let defaultColour: CGColor
    private let rowHeight: CGFloat
    private let columnWidth: CGFloat
    private let margin: CGFloat
    private let columns: Int
    private let rows: Int
    private var glyphs: [Character: SKTexture] = [:]
    private var glyphList: [SKTexture] = []

    private var cells: [SKSpriteNode] = []
    private var brightness: [CGFloat] = []
    private var peaks: [CGFloat] = []
    private var fades: [CGFloat] = []
    private var targets: [SKTexture?] = []
    private var decoding: [TimeInterval] = []
    private var drops: [Drop?]
    private var waits: [TimeInterval]
    private var heads: [Head] = []

    override var theme: GGTheme { .grey }

    override init(aspect: CGFloat, options: Options, pixelsPerPoint: CGFloat) {
        let size = CGSize(width: GGScene.height * aspect, height: GGScene.height)
        let bundle = Bundle(for: GGSaverView.self)
        switch options.rainText {
        case .functions:
            messages = Messages(bundle: bundle, name: "functions")
            wait = Tune.functionWait
            defaultColour = Palette.darkGreen
        case .warnings:
            messages = Messages(bundle: bundle, name: "messages")
            wait = Tune.wait
            defaultColour = Palette.darkRed
        }
        rowHeight = size.height / Tune.rows
        columnWidth = rowHeight * Tune.pitch
        columns = max(1, Int(size.width / columnWidth))
        margin = (size.width - CGFloat(columns) * columnWidth) / 2
        rows = Int(Tune.rows)
        drops = Array(repeating: nil, count: columns)
        waits = (0..<columns).map { _ in TimeInterval.random(in: Tune.firstWait) }
        super.init(aspect: aspect, options: options, pixelsPerPoint: pixelsPerPoint)
        makeGlyphs()
        makeCells()
        makeHeads()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func update(_ currentTime: TimeInterval) {
        let dt = step(currentTime)

        for c in 0..<columns {
            guard var drop = drops[c] else {
                waits[c] -= dt
                if waits[c] <= 0 {
                    drops[c] = newDrop()
                    showHead(c, drop: drops[c]!)
                }
                continue
            }
            drop.head += drop.speed * CGFloat(dt)

            // A character lands once the head has cleared its cell.
            while drop.written < drop.text.count && CGFloat(drop.written) + Tune.behind <= drop.head {
                write(drop.text[drop.written], column: c, row: drop.written % rows, drop: drop)
                drop.written += 1
            }
            if drop.written >= drop.text.count {
                drops[c] = nil
                waits[c] = TimeInterval.random(in: wait)
                hideHead(c)
            } else {
                drop.scrambleClock -= dt
                moveHead(c, drop: &drop)
                drops[c] = drop
            }
        }

        for i in cells.indices where decoding[i] > 0 {
            let before = Int(decoding[i] / Tune.scramble)
            decoding[i] -= dt
            if decoding[i] <= 0 {
                cells[i].texture = targets[i]
            } else if Int(decoding[i] / Tune.scramble) != before {
                cells[i].texture = glyphList.randomElement()
            }
        }

        for i in cells.indices where brightness[i] > 0 {
            brightness[i] -= fades[i] * CGFloat(dt)
            if brightness[i] <= 0 {
                brightness[i] = 0
                cells[i].isHidden = true
            } else {
                cells[i].alpha = peaks[i] * pow(brightness[i], 1 / Tune.fadeCurve)
            }
        }
    }

    // MARK: Drops

    private func newDrop() -> Drop {
        let text = Array(messages.random())
        let depth = CGFloat.random(in: Tune.depth)
        let speed = CGFloat.random(in: Tune.speed) * depth
        let trail = CGFloat.random(in: Tune.trail)
        let colour: SKColor
        switch options.rainColour {
        case .ink: colour = SKColor(cgColor: defaultColour) ?? .black
        case .palette: colour = SKColor(cgColor: Palette.hue.randomElement()!) ?? .black
        }
        return Drop(text: text, speed: speed, fade: speed / trail, colour: colour, depth: depth)
    }

    private func write(_ ch: Character, column c: Int, row r: Int, drop: Drop) {
        let i = c * rows + r
        guard ch != " ", let texture = glyphs[ch] else {
            brightness[i] = 0
            decoding[i] = 0
            cells[i].isHidden = true
            return
        }
        let cell = cells[i]
        cell.texture = glyphList.randomElement()
        targets[i] = texture
        decoding[i] = Tune.decode
        cell.color = drop.colour
        cell.setScale(scale(drop.depth))
        cell.isHidden = false
        brightness[i] = 1
        peaks[i] = opacity(drop.depth)
        cell.alpha = peaks[i]
        fades[i] = drop.fade
    }

    // MARK: Heads

    private func scale(_ depth: CGFloat) -> CGFloat { 0.75 + 0.25 * depth }
    private func opacity(_ depth: CGFloat) -> CGFloat { 0.4 + 0.6 * depth }

    private func showHead(_ c: Int, drop: Drop) {
        let head = heads[c]
        let s = scale(drop.depth)
        head.glyph.setScale(s)
        head.halo.setScale(s)
        head.streak.setScale(s)
        head.halo.color = drop.colour
        head.streak.color = drop.colour
        head.glyph.alpha = opacity(drop.depth)
        head.halo.alpha = Tune.haloAlpha * drop.depth
        head.streak.alpha = Tune.streakAlpha * drop.depth
        for node in [head.glyph, head.halo, head.streak] { node.isHidden = false }
    }

    private func hideHead(_ c: Int) {
        let head = heads[c]
        for node in [head.glyph, head.halo, head.streak] { node.isHidden = true }
    }

    /// Slides the head to its exact position and scrambles its glyph.
    private func moveHead(_ c: Int, drop: inout Drop) {
        let head = heads[c]
        let row = drop.head.truncatingRemainder(dividingBy: CGFloat(rows))
        let y = size.height - row * rowHeight
        head.glyph.position.y = y
        head.halo.position.y = y
        head.streak.position.y = y

        if drop.scrambleClock <= 0 {
            head.glyph.texture = glyphList.randomElement()
            drop.scrambleClock = Tune.scramble
        }
    }

    // MARK: Setup

    private func makeCells() {
        let cellSize = CGSize(width: columnWidth, height: rowHeight)
        cells.reserveCapacity(columns * rows)
        for c in 0..<columns {
            for r in 0..<rows {
                let cell = SKSpriteNode(texture: nil, color: .black, size: cellSize)
                cell.colorBlendFactor = 1
                cell.isHidden = true
                cell.position = CGPoint(x: margin + (CGFloat(c) + 0.5) * columnWidth,
                                        y: size.height - (CGFloat(r) + 0.5) * rowHeight)
                addChild(cell)
                cells.append(cell)
            }
        }
        brightness = Array(repeating: 0, count: cells.count)
        peaks = Array(repeating: 1, count: cells.count)
        fades = Array(repeating: 0, count: cells.count)
        targets = Array(repeating: nil, count: cells.count)
        decoding = Array(repeating: 0, count: cells.count)
    }

    private func makeHeads() {
        let haloSide = rowHeight * Tune.halo
        let streakSize = CGSize(width: columnWidth * 0.7, height: rowHeight * Tune.streak)

        // A white radial glow, tinted per column.
        let halo = SKTexture(cgImage: render(CGSize(width: haloSide, height: haloSide)) { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                      locations: [0, 1])!
            let centre = CGPoint(x: haloSide / 2, y: haloSide / 2)
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                   endCenter: centre, endRadius: haloSide / 2, options: [])
        })

        // A white vertical smear, clear at the top, strongest at the head.
        let streak = SKTexture(cgImage: render(streakSize) { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                      locations: [0, 1])!
            ctx.clip(to: CGRect(origin: .zero, size: streakSize).insetBy(dx: streakSize.width * 0.15, dy: 0))
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: streakSize.height), options: [])
        })

        let ink = SKColor(cgColor: Palette.ink) ?? .black
        for c in 0..<columns {
            let x = margin + (CGFloat(c) + 0.5) * columnWidth

            let haloNode = SKSpriteNode(texture: halo, size: CGSize(width: haloSide, height: haloSide))
            haloNode.colorBlendFactor = 1
            haloNode.zPosition = 1

            let streakNode = SKSpriteNode(texture: streak, size: streakSize)
            streakNode.colorBlendFactor = 1
            streakNode.anchorPoint = CGPoint(x: 0.5, y: 0)
            streakNode.zPosition = 1

            let glyph = SKSpriteNode(texture: nil, color: ink, size: CGSize(width: columnWidth, height: rowHeight))
            glyph.colorBlendFactor = 1
            glyph.zPosition = 2

            for node in [haloNode, streakNode, glyph] {
                node.position.x = x
                node.isHidden = true
                addChild(node)
            }
            heads.append(Head(glyph: glyph, halo: haloNode, streak: streakNode))
        }
    }

    /// Draws every character the messages use into one white sheet, so the
    /// cells share a texture and SpriteKit can batch them.
    private func makeGlyphs() {
        var set = messages.characters
        set.remove(" ")
        let chars = Array(set)

        let font = NSFont.monospacedSystemFont(ofSize: rowHeight * 0.72, weight: .medium)
        let perRow = 16
        let sheetRows = (chars.count + perRow - 1) / perRow
        let sheet = CGSize(width: CGFloat(perRow) * columnWidth, height: CGFloat(sheetRows) * rowHeight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let ascent = font.ascender, descent = -font.descender

        let image = render(sheet) { ctx in
            for (k, ch) in chars.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(ch), attributes: attributes))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                let x = CGFloat(k % perRow) * columnWidth + (columnWidth - width) / 2
                let y = CGFloat(sheetRows - 1 - k / perRow) * rowHeight + (rowHeight - ascent - descent) / 2 + descent
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, ctx)
            }
        }

        let texture = SKTexture(cgImage: image)
        for (k, ch) in chars.enumerated() {
            let rect = CGRect(x: CGFloat(k % perRow) / CGFloat(perRow),
                              y: CGFloat(sheetRows - 1 - k / perRow) / CGFloat(sheetRows),
                              width: 1 / CGFloat(perRow),
                              height: 1 / CGFloat(sheetRows))
            glyphs[ch] = SKTexture(rect: rect, in: texture)
        }
        glyphList = Array(glyphs.values)
    }
}
