import SpriteKit

private enum Tune {
    static let maxBlobs = 16                                  // uniforms in the shader
    static let pool = 3                                       // fixed blobs that make the puddle at the bottom
    static let blobsPerAspect: CGFloat = 5                    // moving blobs per unit of width / height
    static let sigma: ClosedRange<CGFloat> = 0.045...0.085    // blob bandwidth, in panel heights
    static let poolSigma: CGFloat = 0.17
    static let speed: CGFloat = 45                            // points per second at full heat
    static let response: CGFloat = 0.6                        // how fast velocity follows heat, per second
    static let heat: CGFloat = 0.18                           // heating at the bottom, cooling at the top, per second
    static let rate: ClosedRange<CGFloat> = 0.7...1.3         // per-blob spread in heating rate
    static let wander: CGFloat = 20                           // sideways push, points per second squared
    static let bands: CGFloat = 8                             // palette colours above the clear lowest band
}

/// Lava lamp: geom_density_2d_filled() of a few blobs of wax, filled with
/// one of the viridis palettes. Blobs heat at
/// the bottom, rise, cool at the top and sink, and the density's bands merge
/// and split as they pass. The lowest band is clear, so the panel shows.
final class LavaLampScene: GGScene {
    private struct Blob {
        var x: CGFloat, y: CGFloat
        var vx: CGFloat = 0, vy: CGFloat = 0
        var temp: CGFloat
        let sigma: CGFloat
        let rate: CGFloat
        let pool: Bool
    }

    private var blobs: [Blob] = []
    private let uniforms: [SKUniform]
    private var time: TimeInterval = 0

    override init(aspect: CGFloat, options: Options, pixelsPerPoint: CGFloat) {
        uniforms = (0..<Tune.maxBlobs).map { SKUniform(name: "u_b\($0)", vectorFloat4: vector_float4(0, 0, 1, 0)) }
        super.init(aspect: aspect, options: options, pixelsPerPoint: pixelsPerPoint)
        makeBlobs()

        let shader = SKShader(source: LavaLampScene.source)
        shader.uniforms = uniforms + [
            SKUniform(name: "u_size", vectorFloat2: vector_float2(Float(size.width), Float(size.height))),
            SKUniform(name: "u_px", float: Float(1 / pixels)),
            SKUniform(name: "u_step", float: Float(1 / (Tune.bands + 0.5))),
        ] + options.lavaPalette.colours.enumerated().map { i, hex in
            SKUniform(name: "u_c\(i + 1)", vectorFloat4: vector_float4(Float((hex >> 16) & 0xFF) / 255,
                                                                     Float((hex >> 8) & 0xFF) / 255,
                                                                     Float(hex & 0xFF) / 255, 1))
        }
        let node = SKSpriteNode(color: .clear, size: size)
        node.anchorPoint = .zero
        node.shader = shader
        addChild(node)
        upload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var theme: GGTheme { .grey }

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(step(currentTime))
        time += TimeInterval(dt)
        let h = size.height, w = size.width

        for i in blobs.indices {
            var b = blobs[i]
            if b.pool {
                b.x += sin(CGFloat(time) * 0.05 + CGFloat(i) * 2) * 6 * dt
            } else {
                // Warm below the middle, cool above it; hot wax rises.
                b.temp = min(1, max(0, b.temp + Tune.heat * b.rate * (1 - 2 * b.y / h) * dt))
                let target = (b.temp - 0.5) * 2 * Tune.speed
                b.vy += (target - b.vy) * min(1, Tune.response * dt)
                b.y += b.vy * dt
                if b.y < 0 { b.y = 0; b.vy = max(0, b.vy) }
                if b.y > h - b.sigma { b.y = h - b.sigma; b.vy = min(0, b.vy) }

                b.vx += CGFloat.random(in: -1...1) * Tune.wander * dt
                b.vx *= 1 - 0.3 * dt
                b.x += b.vx * dt
                if b.x < b.sigma || b.x > w - b.sigma {
                    b.x = min(max(b.x, b.sigma), w - b.sigma)
                    b.vx = -b.vx
                }
            }
            blobs[i] = b
        }
        upload()
    }

    /// Sends each blob to the shader, with the bandwidth breathing slowly.
    private func upload() {
        let t = CGFloat(time)
        let adjust = 1 + 0.2 * sin(t * 2 * .pi / 37) + 0.1 * sin(t * 2 * .pi / 13)
        for (i, uniform) in uniforms.enumerated() {
            guard i < blobs.count else { uniform.vectorFloat4Value = vector_float4(0, 0, 1, 0); continue }
            let b = blobs[i]
            let sigma = b.pool ? b.sigma : b.sigma * adjust
            uniform.vectorFloat4Value = vector_float4(Float(b.x), Float(b.y), Float(sigma), 1)
        }
    }

    private func makeBlobs() {
        let h = size.height, w = size.width
        for k in 0..<Tune.pool {
            blobs.append(Blob(x: w * (CGFloat(k) + 0.5) / CGFloat(Tune.pool), y: -0.05 * h, temp: 0,
                              sigma: Tune.poolSigma * h, rate: 1, pool: true))
        }
        let moving = min(Tune.maxBlobs - Tune.pool, max(4, Int((Tune.blobsPerAspect * aspect).rounded())))
        for _ in 0..<moving {
            let sigma = CGFloat.random(in: Tune.sigma) * h
            blobs.append(Blob(x: .random(in: sigma...(w - sigma)), y: .random(in: 0...(h * 0.9)),
                              temp: .random(in: 0...1), sigma: sigma, rate: .random(in: Tune.rate), pool: false))
        }
    }

    /// Sums one Gaussian per blob and fills between breaks with the palette.
    /// The gradient gives each break's distance in points, to antialias it.
    private static let source: String = {
        let terms = (0..<Tune.maxBlobs).map { i in
            """
                d = p - u_b\(i).xy;
                e = u_b\(i).w * exp(-dot(d, d) / (2.0 * u_b\(i).z * u_b\(i).z));
                f += e;
                g -= e * d / (u_b\(i).z * u_b\(i).z);
            """
        }.joined(separator: "\n")
        return """
        void main() {
            vec2 p = v_tex_coord * u_size;
            vec4 pal[9];
            pal[0] = vec4(0.0); pal[1] = u_c1; pal[2] = u_c2; pal[3] = u_c3; pal[4] = u_c4;
            pal[5] = u_c5; pal[6] = u_c6; pal[7] = u_c7; pal[8] = u_c8;
            float f = 0.0;
            vec2 g = vec2(0.0);
            vec2 d;
            float e;
        \(terms)
            float t = f / u_step;
            float k = min(floor(t), \(Int(Tune.bands)).0);
            float slope = max(length(g) / u_step, 1e-5);
            vec4 c = pal[int(k)];
            c = mix(pal[int(max(k - 1.0, 0.0))], c, clamp(0.5 + (t - k) / slope / u_px, 0.0, 1.0));
            if (t < \(Int(Tune.bands)).0) {
                c = mix(pal[int(k + 1.0)], c, clamp(0.5 + (k + 1.0 - t) / slope / u_px, 0.0, 1.0));
            }
            gl_FragColor = vec4(c.rgb * c.a, c.a);
        }
        """
    }()
}
