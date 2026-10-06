import SwiftUI

// Hand-drawn marks, ported from chrisqtruong.github.io (assets/site.js):
// the lopsided marker dot, the wobbly loop around a selection, and the drawn underline.

/// One dab of a big marker: lopsided, with a smooth edge. Same path as the site's favicon (64×64).
struct MarkerDot: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (58.2, 23.4),
            (60.9, 29.0), (61.0, 35.8), (58.4, 41.4), (56.2, 46.2), (53.8, 48.2), (50.4, 50.6),
            (46.6, 53.2), (39.2, 56.4), (33.3, 56.7), (27.4, 56.9), (20.0, 54.4), (15.4, 51.5),
            (10.9, 48.5), (7.7, 42.8), (5.9, 38.9), (4.2, 35.0), (2.8, 32.4), (4.7, 28.2),
            (6.5, 23.9), (12.2, 16.9), (17.1, 13.2), (22.0, 9.6), (28.6, 6.5), (34.0, 6.2),
            (39.3, 5.9), (45.0, 8.4), (49.0, 11.3), (53.0, 14.1), (56.6, 18.0), (58.2, 23.4),
        ]
        let sx = rect.width / 64, sy = rect.height / 64
        func p(_ i: Int) -> CGPoint { CGPoint(x: rect.minX + pts[i].0 * sx, y: rect.minY + pts[i].1 * sy) }
        var path = Path()
        path.move(to: p(0))
        var i = 1
        while i + 2 < pts.count {
            path.addCurve(to: p(i + 2), control1: p(i), control2: p(i + 1))
            i += 3
        }
        path.closeSubpath()
        return path
    }
}

/// A thick marker going once around something: overshoots where it closes, never quite even.
/// `seed` keeps each item's wobble the same from redraw to redraw.
struct MarkerLoop: Shape {
    var seed: String
    var round = false
    var pad: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var rnd = Seeded(seed)
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2 + pad, ry = rect.height / 2 + pad * 0.8
        let start = Double.pi * (1.1 + rnd.next() * 0.15)
        let sweep = Double.pi * 2 * (1.09 + rnd.next() * 0.05)
        let ph = (rnd.next() * 6, rnd.next() * 6)
        let drift = 2 + rnd.next() * 2.5
        let n = 30
        var pts: [CGPoint] = []
        for i in 0...n {
            let t = Double(i) / Double(n), a = start + sweep * t
            func sq(_ v: Double) -> Double { (v < 0 ? -1 : 1) * pow(abs(v), round ? 1 : 0.62) }
            let wob = 1 + 0.025 * sin(a * 2 + ph.0) + 0.02 * sin(a * 3 + ph.1)
            pts.append(CGPoint(x: cx + rx * sq(cos(a)) * wob, y: cy + ry * sq(sin(a)) * wob - drift * t + drift / 2))
        }
        return smooth(pts)
    }
}

/// A drawn underline with a little flick up at the end.
struct MarkerUnderline: Shape {
    var seed: String

    func path(in rect: CGRect) -> Path {
        var rnd = Seeded(seed)
        let w = rect.width, y = rect.maxY + 3, tilt = (rnd.next() - 0.5) * 3
        var pts: [CGPoint] = []
        for i in 0...6 {
            let t = Double(i) / 6
            pts.append(CGPoint(x: rect.minX - 3 + (w + 8) * t,
                               y: y + tilt * t + sin(t * .pi) * (1 + rnd.next()) + (rnd.next() - 0.5) * 0.8))
        }
        pts.append(CGPoint(x: rect.minX + w + 8, y: y + tilt - 3 - rnd.next() * 2))
        return smooth(pts)
    }
}

/// A back arrow drawn with the marker: a "<" that's a little uneven, with a soft overshoot at the point.
struct MarkerChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.84, 0.04))
        path.addQuadCurve(to: p(0.16, 0.5), control: p(0.42, 0.2))       // upper stroke, bowed out
        path.addQuadCurve(to: p(0.22, 0.6), control: p(0.08, 0.57))      // a rounded turn at the point
        path.addQuadCurve(to: p(0.78, 0.97), control: p(0.52, 0.74))     // lower stroke, a little shorter and flatter
        return path
    }
}

/// A marker arrow curving up and to the left, a little uneven, like one drawn on a page.
struct MarkerArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.92, 0.96))                                        // the tail
        path.addQuadCurve(to: p(0.14, 0.14), control: p(0.24, 0.86))       // one sweeping stroke up to the tip
        path.move(to: p(0.42, 0.12))                                        // the head: two strokes, not quite matching
        path.addQuadCurve(to: p(0.13, 0.13), control: p(0.27, 0.09))
        path.addQuadCurve(to: p(0.17, 0.44), control: p(0.12, 0.28))
        return path
    }
}

/// A rough highlighter swipe, for buttons (from the site's header links).
struct MarkerSwipe: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 30
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(4, 8))
        path.addCurve(to: p(68, 4.6), control1: p(20, 4.5), control2: p(44, 7))
        path.addCurve(to: p(97.4, 6.6), control1: p(82, 3.4), control2: p(92, 4.4))
        path.addCurve(to: p(96.2, 24.6), control1: p(99.2, 12), control2: p(98.6, 19))
        path.addCurve(to: p(30, 26.4), control1: p(76, 26.6), control2: p(52, 24.4))
        path.addCurve(to: p(3.2, 24.4), control1: p(18, 27.4), control2: p(9, 26.6))
        path.addCurve(to: p(4, 8), control1: p(1.2, 18.4), control2: p(1.8, 12.6))
        path.closeSubpath()
        return path
    }
}

/// Smooth curve through points (Catmull-Rom as cubic Béziers), as on the site.
private func smooth(_ pts: [CGPoint]) -> Path {
    var path = Path()
    guard let first = pts.first else { return path }
    path.move(to: first)
    for i in 1..<pts.count {
        let p0 = pts[max(0, i - 2)], p1 = pts[i - 1], p = pts[i], p3 = pts[min(pts.count - 1, i + 1)]
        let c1 = CGPoint(x: p1.x + (p.x - p0.x) / 6, y: p1.y + (p.y - p0.y) / 6)
        let c2 = CGPoint(x: p.x - (p3.x - p1.x) / 6, y: p.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p, control1: c1, control2: c2)
    }
    return path
}

/// The site's seeded random numbers (FNV-1a hash, then a mixer), so shapes match across redraws.
private struct Seeded {
    private var h: UInt32 = 2_166_136_261

    init(_ text: String) {
        for c in text.utf16 { h = (h ^ UInt32(c)) &* 16_777_619 }
    }

    mutating func next() -> Double {
        h = ((h ^ (h >> 15)) &* 2_246_822_507) ^ ((h ^ (h >> 13)) &* 3_266_489_909)
        return Double(h) / 4_294_967_296
    }
}

extension View {
    /// Circles this view with a marker loop when `on`.
    func markerLoop(_ on: Bool, seed: String, color: Color, round: Bool = false, pad: CGFloat = 6) -> some View {
        overlay {
            if on {
                MarkerLoop(seed: seed, round: round, pad: pad)
                    .stroke(color, style: StrokeStyle(lineWidth: round ? 2.2 : 2.6, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    func markerUnderline(_ on: Bool, seed: String, color: Color) -> some View {
        overlay {
            if on {
                MarkerUnderline(seed: seed)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
            }
        }
    }
}
