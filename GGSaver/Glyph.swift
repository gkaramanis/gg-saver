import SpriteKit

/// The 26 pch shapes, as drawing paths and physics bodies.
/// Unit geometry follows R's engine.c: a circle of radius 1, with the other
/// shapes sized to match its area.
@MainActor
enum Glyph {
    enum Fill { case none, solid, background }

    static let stroke: CGFloat = 0.32

    /// Half-side of the box every glyph fits in, stroke included.
    static let extent: CGFloat = 1.9

    private static let root2 = CGFloat(2).squareRoot()
    private static let sq = CGFloat.pi.squareRoot() / 2
    private static let tr = (4 * CGFloat.pi / (3 * CGFloat(3).squareRoot())).squareRoot()
    private static let trx = tr * CGFloat(3).squareRoot() / 2
    private static let trY = tr / 2

    private static let up = [CGPoint(x: 0, y: tr), CGPoint(x: -trx, y: -trY), CGPoint(x: trx, y: -trY)]
    private static let down = up.map { CGPoint(x: -$0.x, y: -$0.y) }
    private static let starUp = [CGPoint(x: 0, y: 1.15), CGPoint(x: -1.212, y: -0.95), CGPoint(x: 1.212, y: -0.95)]
    private static let starDown = starUp.map { CGPoint(x: -$0.x, y: -$0.y) }

    private static func square(_ s: CGFloat) -> [CGPoint] {
        [CGPoint(x: -s, y: -s), CGPoint(x: s, y: -s), CGPoint(x: s, y: s), CGPoint(x: -s, y: s)]
    }

    private static func diamond(_ s: CGFloat) -> [CGPoint] {
        [CGPoint(x: 0, y: -s), CGPoint(x: s, y: 0), CGPoint(x: 0, y: s), CGPoint(x: -s, y: 0)]
    }

    private static func plus(_ s: CGFloat) -> [[CGPoint]] {
        [[CGPoint(x: -s, y: 0), CGPoint(x: s, y: 0)], [CGPoint(x: 0, y: -s), CGPoint(x: 0, y: s)]]
    }

    private static func cross(_ s: CGFloat) -> [[CGPoint]] {
        [[CGPoint(x: -s, y: -s), CGPoint(x: s, y: s)], [CGPoint(x: -s, y: s), CGPoint(x: s, y: -s)]]
    }

    static func shape(_ pch: Int) -> (path: CGPath, fill: Fill) {
        let p = CGMutablePath()
        func poly(_ pts: [CGPoint]) { p.addLines(between: pts); p.closeSubpath() }
        func lines(_ segments: [[CGPoint]]) { segments.forEach { p.addLines(between: $0) } }
        func circle(_ r: CGFloat = 1) { p.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)) }

        let d = root2 * sq
        var fill = Fill.none
        switch pch {
        case 0: poly(square(sq))
        case 1: circle()
        case 2: poly(up)
        case 3: lines(plus(root2))
        case 4: lines(cross(1))
        case 5: poly(diamond(d))
        case 6: poly(down)
        case 7: poly(square(sq)); lines(cross(sq))
        case 8: lines(plus(root2)); lines(cross(1))
        case 9: poly(diamond(d)); lines(plus(d))
        case 10: circle(); lines(plus(1))
        case 11: poly(starUp); poly(starDown)
        case 12: poly(square(sq)); lines(plus(sq))
        case 13: circle(); lines(cross(1 / root2))
        case 14: poly(square(sq)); lines([[CGPoint(x: -sq, y: -sq), CGPoint(x: 0, y: sq), CGPoint(x: sq, y: -sq)]])
        case 15: poly(square(sq)); fill = .solid
        case 16: circle(); fill = .solid
        case 17: poly(up); fill = .solid
        case 18: poly(diamond(1)); fill = .solid
        case 19: circle(); fill = .solid
        case 20: circle(2 / 3); fill = .solid
        case 21: circle(); fill = .background
        case 22: poly(square(sq)); fill = .background
        case 23: poly(diamond(d)); fill = .background
        case 24: poly(up); fill = .background
        case 25: poly(down); fill = .background
        default: circle()
        }
        return (p, fill)
    }

    /// Draws a glyph centred on the origin in glyph units. A nil colour means
    /// ggplot2's defaults: ink for everything and no fill for 21–25.
    static func draw(_ pch: Int, in ctx: CGContext, colour: CGColor?, ink: CGColor) {
        let (path, fill) = shape(pch)
        let main = colour ?? ink
        ctx.setLineWidth(stroke)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        switch fill {
        case .none:
            ctx.setStrokeColor(main)
            ctx.strokePath()
        case .solid:
            ctx.setFillColor(main)
            ctx.setStrokeColor(main)
            ctx.drawPath(using: pch == 19 ? .fillStroke : .fill)
        case .background:
            if let colour {
                ctx.setFillColor(colour)
                ctx.setStrokeColor(ink)
                ctx.drawPath(using: .fillStroke)
            } else {
                ctx.setStrokeColor(ink)
                ctx.strokePath()
            }
        }
    }

    /// A physics body matching the drawn outline, with `u` points per glyph unit.
    static func body(_ pch: Int, unit u: CGFloat) -> SKPhysicsBody {
        let pad = stroke / 2

        func polygon(_ pts: [CGPoint], grow: CGFloat = 1) -> SKPhysicsBody {
            var pts = pts.map { CGPoint(x: $0.x * grow * u, y: $0.y * grow * u) }
            if signedArea(pts) < 0 { pts.reverse() }
            let path = CGMutablePath()
            path.addLines(between: pts)
            path.closeSubpath()
            return SKPhysicsBody(polygonFrom: path)
        }

        // A stroke segment through the origin, as a thin box.
        func bar(_ angle: CGFloat, _ half: CGFloat) -> SKPhysicsBody {
            let c = cos(angle), s = sin(angle), l = half + pad, t: CGFloat = 0.22
            return polygon([
                CGPoint(x: -c * l + s * t, y: -s * l - c * t),
                CGPoint(x: c * l + s * t, y: s * l - c * t),
                CGPoint(x: c * l - s * t, y: s * l + c * t),
                CGPoint(x: -c * l - s * t, y: -s * l + c * t),
            ])
        }

        let quarter = CGFloat.pi / 4, half = CGFloat.pi / 2
        switch pch {
        case 1, 10, 13, 19, 21: return SKPhysicsBody(circleOfRadius: (1 + pad) * u)
        case 16: return SKPhysicsBody(circleOfRadius: u)
        case 20: return SKPhysicsBody(circleOfRadius: u * 2 / 3)
        case 0, 7, 12, 14, 22: return polygon(square(sq), grow: (sq + pad) / sq)
        case 15: return polygon(square(sq))
        case 2, 24: return polygon(up, grow: (trY + pad) / trY)
        case 17: return polygon(up)
        case 6, 25: return polygon(down, grow: (trY + pad) / trY)
        case 5, 9, 23: return polygon(diamond(root2 * sq), grow: (sq + pad) / sq)
        case 18: return polygon(diamond(1))
        case 3: return SKPhysicsBody(bodies: [bar(0, root2), bar(half, root2)])
        case 4: return SKPhysicsBody(bodies: [bar(quarter, root2), bar(-quarter, root2)])
        case 8: return SKPhysicsBody(bodies: [bar(0, root2), bar(half, root2), bar(quarter, root2), bar(-quarter, root2)])
        case 11: return SKPhysicsBody(bodies: [polygon(starUp, grow: 1.1), polygon(starDown, grow: 1.1)])
        default: return SKPhysicsBody(circleOfRadius: u)
        }
    }

    private static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }
}
