// Renders the app icon: `swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset`
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size: CGFloat = 1024

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / size
    context.scaleBy(x: scale, y: scale)

    // Rounded-square body on Apple's icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.33, green: 0.30, blue: 0.93, alpha: 1).cgColor,
        NSColor(srgbRed: 0.09, green: 0.72, blue: 0.78, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

    // Three faint screens: the places focus can go.
    context.setFillColor(NSColor.white.withAlphaComponent(0.13).cgColor)
    for rect in [CGRect(x: 170, y: 640, width: 250, height: 160), CGRect(x: 604, y: 640, width: 250, height: 160), CGRect(x: 387, y: 214, width: 250, height: 160)] {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.fillPath()
    }

    // The eye.
    let center = CGPoint(x: 512, y: 512)
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: center.x - 300, y: center.y))
    eye.addQuadCurve(to: CGPoint(x: center.x + 300, y: center.y), control: CGPoint(x: center.x, y: center.y + 250))
    eye.addQuadCurve(to: CGPoint(x: center.x - 300, y: center.y), control: CGPoint(x: center.x, y: center.y - 250))
    eye.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    context.addPath(eye)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Iris looking a little to the right: focus is moving over there.
    let iris = CGPoint(x: center.x + 42, y: center.y)
    context.saveGState()
    context.addPath(eye)
    context.clip()
    let irisGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.62, alpha: 1).cgColor,
        NSColor(srgbRed: 0.05, green: 0.52, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.addEllipse(in: CGRect(x: iris.x - 118, y: iris.y - 118, width: 236, height: 236))
    context.clip()
    context.drawRadialGradient(irisGradient, startCenter: iris, startRadius: 20, endCenter: iris, endRadius: 118, options: [])
    context.restoreGState()
    context.setFillColor(NSColor(srgbRed: 0.04, green: 0.05, blue: 0.16, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: iris.x - 52, y: iris.y - 52, width: 104, height: 104))
    context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    context.fillEllipse(in: CGRect(x: iris.x + 14, y: iris.y + 20, width: 34, height: 34))
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for entry in sizes {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    try render(pixels: pixels).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(output.path)")
