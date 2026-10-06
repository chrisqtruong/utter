import SwiftUI

// Palettes from Monkeytype (github.com/monkeytypegame/monkeytype, GPL-3.0), the same 37 Vox2 uses.
// Roles as there: `text` is the transcript, `sub` is labels and quiet text,
// `subAlt` is lines and fills, `main` is the accent, `error` is warnings.
struct Theme: Identifiable, Equatable {
    let name: String
    let bg: Color
    let main: Color
    let sub: Color
    let subAlt: Color
    let text: Color
    let error: Color
    let isDark: Bool
    /// [bg, main, sub, subAlt, text, error], for sharing with the keyboard
    let hex: [String]

    var id: String { name }

    init(_ name: String, _ palette: [String]) {
        var hex = palette
        hex[2] = Theme.readable(hex[2], on: hex[0], toward: hex[4])
        self.name = name
        bg = Color(hex: hex[0]); main = Color(hex: hex[1]); sub = Color(hex: hex[2])
        subAlt = Color(hex: hex[3]); text = Color(hex: hex[4]); error = Color(hex: hex[5])
        isDark = Theme.luma(hex[0]) < 140
        self.hex = hex
    }

    /// Some palettes make quiet text too faint to read on a phone (olivia's is barely there).
    /// Nudge it toward the main text color until it reads clearly, keeping its hue.
    static let minContrast = 3.5

    private static func readable(_ sub: String, on bg: String, toward text: String) -> String {
        let s = rgb(sub), t = rgb(text), b = rgb(bg)
        var mix = 0.0
        while mix < 1, contrast(blend(s, t, mix), b) < minContrast { mix += 0.05 }
        let c = blend(s, t, min(mix, 1))
        return String(format: "#%02x%02x%02x", Int(c.0.rounded()), Int(c.1.rounded()), Int(c.2.rounded()))
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return (Double(n >> 16), Double((n >> 8) & 255), Double(n & 255))
    }

    private static func blend(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    /// WCAG contrast ratio: 1 (none) to 21 (black on white).
    private static func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        func lum(_ c: (Double, Double, Double)) -> Double {
            func ch(_ v: Double) -> Double { let x = v / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
        }
        let la = lum(a), lb = lum(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luma(_ hex: String) -> Double {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return 0.299 * Double(n >> 16) + 0.587 * Double((n >> 8) & 255) + 0.114 * Double(n & 255)
    }
}

struct ThemeGroup: Identifiable {
    let name: String
    let themes: [Theme]
    var id: String { name }
}

enum Themes {
    // "auto" follows the system: serika dark at night, serika in light mode.
    static let autoName = "auto"

    static let groups: [ThemeGroup] = [
        ThemeGroup(name: "dark", themes: [
            Theme("serika dark", ["#323437", "#e2b714", "#646669", "#2c2e31", "#d1d0c5", "#ca4754"]),
            Theme("carbon", ["#313131", "#f66e0d", "#616161", "#2b2b2b", "#f5e6c8", "#e72d2d"]),
            Theme("nord", ["#242933", "#88c0d0", "#929aaa", "#2e3440", "#d8dee9", "#bf616a"]),
            Theme("dracula", ["#282a36", "#bd93f9", "#6272a4", "#20222c", "#f8f8f2", "#ff5555"]),
            Theme("catppuccin", ["#1e1e2e", "#cba6f7", "#7f849c", "#181825", "#cdd6f4", "#f38ba8"]),
            Theme("rose pine", ["#1f1d27", "#9ccfd8", "#c4a7e7", "#282533", "#e0def4", "#eb6f92"]),
            Theme("gruvbox dark", ["#282828", "#d79921", "#665c54", "#212121", "#ebdbb2", "#fb4934"]),
            Theme("8008", ["#333a45", "#f44c7f", "#939eae", "#2e343d", "#e9ecf0", "#da3333"]),
            Theme("bento", ["#2d394d", "#ff7a90", "#4a768d", "#263041", "#fffaf8", "#ee2a3a"]),
            Theme("olivia", ["#1c1b1d", "#deaf9d", "#4e3e3e", "#262223", "#f2efed", "#bf616a"]),
            Theme("superuser", ["#262a33", "#43ffaf", "#526777", "#1f232c", "#e5f7ef", "#ff5f5f"]),
            Theme("arch", ["#0c0d11", "#7ebab5", "#454864", "#171a25", "#f6f5f5", "#ff4754"]),
        ]),
        ThemeGroup(name: "contrast", themes: [
            Theme("dots", ["#121520", "#ffffff", "#676e8a", "#1b1e2c", "#ffffff", "#da3333"]),
            Theme("matrix", ["#000000", "#15ff00", "#006500", "#032000", "#d1ffcd", "#da3333"]),
            Theme("hammerhead", ["#030613", "#4fcdb9", "#213c53", "#0a1928", "#e2f1f5", "#e32b2b"]),
            Theme("aurora", ["#011926", "#00e980", "#245c69", "#000c13", "#ffffff", "#b94da1"]),
            Theme("terminal", ["#191a1b", "#79a617", "#48494b", "#141516", "#e7eae0", "#a61717"]),
            Theme("modern ink", ["#ffffff", "#ff360d", "#b7b7b7", "#ececec", "#000000", "#d70000"]),
            Theme("9009", ["#eeebe2", "#080909", "#99947f", "#d3cfc1", "#080909", "#c87e74"]),
        ]),
        ThemeGroup(name: "colorful", themes: [
            Theme("miami", ["#f35588", "#05dfd7", "#94294c", "#db4979", "#f0e9ec", "#fff591"]),
            Theme("strawberry", ["#f37f83", "#fcfcf8", "#e53c58", "#ef6e77", "#fcfcf8", "#fcd23f"]),
            Theme("honey", ["#f2aa00", "#fff546", "#a66b00", "#e19e00", "#f3eecb", "#df3333"]),
            Theme("botanical", ["#7b9c98", "#eaf1f3", "#495755", "#72908d", "#eaf1f3", "#f6c9b4"]),
            Theme("laser", ["#221b44", "#009eaf", "#b82356", "#1e173b", "#dbe7e8", "#a8d400"]),
            Theme("sweden", ["#0058a3", "#ffcc02", "#57abdb", "#024f8e", "#ffffff", "#e74040"]),
            Theme("vaporwave", ["#a4a7ea", "#e368da", "#7c7faf", "#989bd9", "#f1ebf1", "#573ca9"]),
            Theme("nautilus", ["#132237", "#ebb723", "#0b4c6c", "#0e1a29", "#1cbaac", "#da3333"]),
        ]),
        ThemeGroup(name: "light", themes: [
            Theme("serika", ["#e1e1e3", "#e2b714", "#aaaeb3", "#d1d3d8", "#323437", "#da3333"]),
            Theme("paper", ["#eeeeee", "#444444", "#b2b2b2", "#dddddd", "#444444", "#d70000"]),
            Theme("solarized light", ["#fdf6e3", "#859900", "#2aa198", "#e2d8be", "#181819", "#d33682"]),
            Theme("lil dragon", ["#ebe1ef", "#8a5bd6", "#a28db8", "#dac7e2", "#212b43", "#f794ca"]),
            Theme("milkshake", ["#ffffff", "#212b43", "#62cfe6", "#ddeff3", "#212b43", "#f19dac"]),
            Theme("mizu", ["#afcbdd", "#fcfbf6", "#85a5bb", "#9fc1d4", "#1a2633", "#bf616a"]),
            Theme("lavender", ["#ada6c2", "#e4e3e9", "#e4e3e9", "#a19bb9", "#2f2a41", "#ca4754"]),
            Theme("shoko", ["#ced7e0", "#81c4dd", "#7599b1", "#b7cada", "#3b4c58", "#bf616a"]),
            Theme("blueberry light", ["#dae0f5", "#506477", "#92a4be", "#c1c7df", "#678198", "#df4576"]),
        ]),
    ]

    static let all: [Theme] = groups.flatMap(\.themes)

    static func named(_ name: String, systemDark: Bool) -> Theme {
        if let theme = all.first(where: { $0.name == name }) { return theme }
        return all.first { $0.name == (systemDark ? "serika dark" : "serika") }!
    }
}

extension Color {
    init(hex: String) {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double(n >> 16) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}

// The current theme, readable anywhere with @Environment(\.theme).
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Themes.all[0]
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
