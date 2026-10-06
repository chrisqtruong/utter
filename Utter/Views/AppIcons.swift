import SwiftUI

/// The app icon options. Each is the same drawing (marker bars + the marker dot) in a theme's colors.
/// Tools/make_icon.swift draws the real icon files from this same list, so keep the two in step.
struct AppIconOption: Identifiable {
    let id: String          // asset name; "AppIcon" is the default
    let label: String
    let bg: String, bars: String, dot: String

    var isDefault: Bool { id == "AppIcon" }
}

enum AppIcons {
    static let options: [AppIconOption] = [
        AppIconOption(id: "AppIcon", label: "serika dark", bg: "#323437", bars: "#e2b714", dot: "#e2b714"),
        AppIconOption(id: "AppIcon-light", label: "serika", bg: "#e1e1e3", bars: "#323437", dot: "#e2b714"),
        AppIconOption(id: "AppIcon-nord", label: "nord", bg: "#242933", bars: "#d8dee9", dot: "#88c0d0"),
        AppIconOption(id: "AppIcon-miami", label: "miami", bg: "#f35588", bars: "#f0e9ec", dot: "#05dfd7"),
        AppIconOption(id: "AppIcon-sweden", label: "sweden", bg: "#0058a3", bars: "#ffcc02", dot: "#ffffff"),
        AppIconOption(id: "AppIcon-matrix", label: "matrix", bg: "#000000", bars: "#15ff00", dot: "#15ff00"),
    ]
}

/// The icon drawing in SwiftUI, for previews in Settings. Coordinates match the 1024-point icon file.
struct IconArt: View {
    let option: AppIconOption

    // x, half-height, width, lean, bow — the same numbers as Tools/make_icon.swift
    static let bars: [(x: CGFloat, h: CGFloat, w: CGFloat, lean: CGFloat, bow: CGFloat)] = [
        (230, 92, 66, -10, 6), (338, 188, 72, 14, -9), (450, 270, 70, -6, 12), (560, 150, 74, 18, -6), (668, 214, 66, -14, 8),
    ]

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 1024
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: option.bg)))
            for b in Self.bars {
                // the icon file is drawn y-up; flip for the screen
                let cy = 1024 / 2 - 20.0
                var path = Path()
                path.move(to: CGPoint(x: (b.x - b.lean / 2) * k, y: (cy + b.h) * k))
                path.addQuadCurve(to: CGPoint(x: (b.x + b.lean / 2) * k, y: (cy - b.h) * k),
                                  control: CGPoint(x: (b.x + b.bow * 2) * k, y: cy * k))
                ctx.stroke(path, with: .color(Color(hex: option.bars)), style: StrokeStyle(lineWidth: b.w * k, lineCap: .round))
            }
            let dot = MarkerDot().path(in: CGRect(x: 742 * k, y: (1024 - 270 - 64 * 2.2) * k, width: 64 * 2.2 * k, height: 64 * 2.2 * k))
            ctx.fill(dot, with: .color(Color(hex: option.dot)))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
