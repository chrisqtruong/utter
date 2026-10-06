// Draws the app icon: serika-dark background, waveform bars drawn like thick marker
// strokes (a bit crooked, uneven widths), then the site's lopsided marker dot as the "."
// One file per color option (keep in step with Utter/Views/AppIcons.swift).
// Run from the repo root: swift Tools/make_icon.swift
import AppKit
import CoreImage
import ImageIO

func color(_ hex: String) -> CGColor {
    let n = Int(hex.dropFirst(), radix: 16)!
    return CGColor(red: CGFloat(n >> 16) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
}
let options: [(id: String, bg: String, bars: String, dot: String)] = [
    ("AppIcon", "#323437", "#e2b714", "#e2b714"),
    ("AppIcon-light", "#e1e1e3", "#323437", "#e2b714"),
    ("AppIcon-nord", "#242933", "#d8dee9", "#88c0d0"),
    ("AppIcon-miami", "#f35588", "#f0e9ec", "#05dfd7"),
    ("AppIcon-sweden", "#0058a3", "#ffcc02", "#ffffff"),
    ("AppIcon-matrix", "#000000", "#15ff00", "#15ff00"),
]

let size = 1024.0
for option in options {
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

ctx.setFillColor(color(option.bg))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Each bar: x, half-height, width, lean (top shifts by this), bow (sideways bulge mid-stroke).
let bars: [(x: Double, h: Double, w: Double, lean: Double, bow: Double)] = [
    (230, 92, 66, -10, 6),
    (338, 188, 72, 14, -9),
    (450, 270, 70, -6, 12),
    (560, 150, 74, 18, -6),
    (668, 214, 66, -14, 8),
]
ctx.setStrokeColor(color(option.bars))
ctx.setLineCap(.round)
for b in bars {
    let cy = size / 2 + 20
    let bottom = CGPoint(x: b.x - b.lean / 2, y: cy - b.h)
    let top = CGPoint(x: b.x + b.lean / 2, y: cy + b.h)
    ctx.setLineWidth(b.w)
    ctx.move(to: bottom)
    ctx.addQuadCurve(to: top, control: CGPoint(x: b.x + b.bow * 2, y: cy))
    ctx.strokePath()
}

// The marker dot (same path as the site's favicon), sitting low like a full stop.
let dot: [(Double, Double)] = [
    (58.2, 23.4),
    (60.9, 29.0), (61.0, 35.8), (58.4, 41.4), (56.2, 46.2), (53.8, 48.2), (50.4, 50.6),
    (46.6, 53.2), (39.2, 56.4), (33.3, 56.7), (27.4, 56.9), (20.0, 54.4), (15.4, 51.5),
    (10.9, 48.5), (7.7, 42.8), (5.9, 38.9), (4.2, 35.0), (2.8, 32.4), (4.7, 28.2),
    (6.5, 23.9), (12.2, 16.9), (17.1, 13.2), (22.0, 9.6), (28.6, 6.5), (34.0, 6.2),
    (39.3, 5.9), (45.0, 8.4), (49.0, 11.3), (53.0, 14.1), (56.6, 18.0), (58.2, 23.4),
]
let dx = 742.0, dy = 270.0, s = 2.2   // where the 64×64 path goes, and how big (y flipped below)
func p(_ i: Int) -> CGPoint { CGPoint(x: dx + dot[i].0 * s, y: dy + (64 - dot[i].1) * s) }
ctx.setFillColor(color(option.dot))
ctx.move(to: p(0))
var i = 1
while i + 2 < dot.count { ctx.addCurve(to: p(i + 2), control1: p(i), control2: p(i + 1)); i += 3 }
ctx.closePath()
ctx.fillPath()

NSGraphicsContext.current = nil
let dir = URL(fileURLWithPath: "Utter/Resources/Assets.xcassets/\(option.id).appiconset")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
// App icons must be fully opaque with no transparency channel, or iOS may fail to show them.
let flat = CIContext().createCGImage(CIImage(cgImage: rep.cgImage!), from: CGRect(x: 0, y: 0, width: size, height: size),
                                     format: .RGBX8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("icon.png") as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, flat, [kCGImagePropertyHasAlpha: false] as CFDictionary)
CGImageDestinationFinalize(dest)
try! """
{
  "images" : [ { "filename" : "icon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""".write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote", dir.lastPathComponent)
}
