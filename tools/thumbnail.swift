// Renders Lava lamp after a minute of simulated time into the two images
// System Settings shows for the screensaver. Run tools/thumbnail.sh.
import AppKit
import SpriteKit

let size = CGSize(width: 900 * 90.0 / 58, height: 900)
let view = SKView(frame: NSRect(origin: .zero, size: size))
let scene = LavaLampScene(aspect: size.width / size.height, options: Options(), pixelsPerPoint: 1)
view.presentScene(scene)
var t = 0.0
while t < 60 { t += 1.0 / 60; scene.update(t) }
let rep = NSBitmapImageRep(cgImage: view.texture(from: scene)!.cgImage())
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
