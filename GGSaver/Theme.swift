import CoreGraphics

private func hex(_ v: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1)
}

enum Palette {
    /// ggplot2's default ink, used for points in every complete theme.
    static let ink = hex(0x000000)


    /// scales::hue_pal()(26)
    static let hue: [CGColor] = ([
        0xF8766D, 0xEE8043, 0xE18A00, 0xD19300, 0xBE9C00, 0xA8A400, 0x8CAB00, 0x68B100, 0x24B700,
        0x00BB49, 0x00BE70, 0x00C090, 0x00C1AB, 0x00BFC4, 0x00BBDA, 0x00B5ED, 0x00ACFC, 0x42A0FF,
        0x8B93FF, 0xB684FF, 0xD575FE, 0xEB69F0, 0xF962DD, 0xFF61C6, 0xFF65AC, 0xFF6D8E,
    ] as [UInt32]).map(hex)
}

/// The panel of the ggplot2 complete themes Shape fall offers. Line widths are relative to the
/// base line size, as in the theme definitions.
enum GGTheme: String, CaseIterable {
    case grey, bw, classic

    var title: String { "theme_\(rawValue)()" }

    private var paper: CGColor {
        self == .grey ? hex(0xEBEBEB) : hex(0xFFFFFF)
    }

    /// Grid colour with major and minor widths.
    private var grid: (colour: CGColor, major: CGFloat, minor: CGFloat)? {
        switch self {
        case .grey: return (hex(0xFFFFFF), 1, 0.5)
        case .bw: return (hex(0xEBEBEB), 1, 0.5)
        case .classic: return nil
        }
    }

    private var border: CGColor? {
        self == .bw ? hex(0x333333) : nil
    }

    /// Line width that matches the base line size on a panel `height` tall.
    static func base(_ height: CGFloat) -> CGFloat { height / 540 }

    /// Draws the panel's background and grid across `size`, in a context
    /// scaled to points. `pixel` is one device pixel in points, the thinnest line drawn.
    func drawPanel(_ ctx: CGContext, size: CGSize, pixel: CGFloat) {
        let base = GGTheme.base(size.height)
        let rect = CGRect(origin: .zero, size: size)
        ctx.setFillColor(paper)
        ctx.fill(rect)

        if let grid {
            ctx.setStrokeColor(grid.colour)
            let major = size.height / 4
            for (step, rel) in [(major / 2, grid.minor), (major, grid.major)] {
                ctx.setLineWidth(max(rel * base, pixel))
                var x = (size.width / 2).truncatingRemainder(dividingBy: step)
                while x < size.width {
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y = (size.height / 2).truncatingRemainder(dividingBy: step)
                while y < size.height {
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                ctx.strokePath()
            }
        }
    }

    /// Draws what sits on top of the panel's contents: the border, or
    /// theme_classic()'s axis lines.
    func drawEdges(_ ctx: CGContext, size: CGSize) {
        let base = GGTheme.base(size.height)
        let rect = CGRect(origin: .zero, size: size)

        if let border {
            ctx.setStrokeColor(border)
            ctx.setLineWidth(base)
            ctx.stroke(rect.insetBy(dx: base / 2, dy: base / 2))
        }

        // theme_classic() has axis lines on the left and bottom instead of a border.
        if self == .classic {
            ctx.setStrokeColor(Palette.ink)
            ctx.setLineWidth(base)
            ctx.move(to: CGPoint(x: base / 2, y: size.height))
            ctx.addLine(to: CGPoint(x: base / 2, y: base / 2))
            ctx.addLine(to: CGPoint(x: size.width, y: base / 2))
            ctx.strokePath()
        }
    }
}
