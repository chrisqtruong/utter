import SwiftUI

// Building blocks for Utter's own pages (settings, stats, models), so they look like the
// rest of the app instead of a stock iOS form: lowercase mono labels, a short rule under
// each heading, plain rows, and hand-drawn marks for anything that's on or chosen.

struct Page<Content: View>: View {
    let title: String
    var showsDone = true
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg.ignoresSafeArea())
        .toolbarBackground(theme.bg, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .handDrawnBack(!showsDone)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 1) {
                    Text(title).foregroundStyle(theme.text)
                    Text(".").foregroundStyle(theme.main)
                }
                .font(.mono(17, .semibold))
            }
            if showsDone {
                if #available(iOS 26.0, *) {
                    // just the highlighter swipe, without iOS's glass bubble behind it
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
            }
        }
    }
}

extension ToolbarContent {
    /// Without iOS's glass bubble behind the button, so it sits right on the theme color.
    @ToolbarContentBuilder
    func noGlass() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension Page {
    private var doneButton: some View {
        Button { dismiss() } label: { Text("done").font(.mono(15, .semibold)).fixedSize() }
            .buttonStyle(SwipeButtonStyle())
            .fixedSize()
    }
}

struct PageSection<Content: View>: View {
    let label: String
    var note: String?
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: label)
                Rectangle().fill(theme.sub.opacity(0.5)).frame(width: 22, height: 1.5)
            }
            VStack(alignment: .leading, spacing: 12) { content }
            if let note {
                Text(note)
                    .font(.ui(14))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A plain row: title on the left, value and an arrow on the right.
struct PageRow: View {
    let title: String
    var value: String?
    var arrow = true
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ui(17)).foregroundStyle(theme.text)
            Spacer(minLength: 12)
            if let value {
                Text(value).font(.mono(14)).foregroundStyle(theme.sub).lineLimit(1)
            }
            if arrow {
                Text("→").font(.mono(15)).foregroundStyle(theme.sub)
            }
        }
        .frame(minHeight: 30)
        .contentShape(Rectangle())
    }
}

/// On/off as a hand-drawn ring that fills with a marker dot when on.
struct MarkerToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { isOn.toggle() }
            Haptics.tap()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    MarkerLoop(seed: title, round: true, pad: -2)
                        .stroke(isOn ? theme.main : theme.sub, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    if isOn {
                        MarkerDot().fill(theme.main).padding(5).transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 26, height: 26)
                Text(title).font(.ui(17)).foregroundStyle(theme.text)
                Spacer()
                Text(isOn ? "on" : "off").font(.mono(13)).foregroundStyle(isOn ? theme.main : theme.sub)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Pick one from a few short options, the chosen one circled.
struct MarkerChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { selection = value } label: {
                    Text(label)
                        .font(.mono(14, on ? .semibold : .regular))
                        .foregroundStyle(on ? theme.text : theme.sub)
                        .markerLoop(on, seed: label, color: theme.main, pad: 5)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Hand-drawn back button

/// Replaces iOS's back button with a marker-drawn arrow (no glass bubble). Swiping back still works.
struct HandBackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        Button { dismiss() } label: {
            MarkerChevron()
                .stroke(theme.text, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 22)
                .rotationEffect(.degrees(-3))
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

extension View {
    func handDrawnBack(_ on: Bool = true) -> some View {
        modifier(HandBackModifier(on: on))
    }
}

private struct HandBackModifier: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar { ToolbarItem(placement: .topBarLeading) { HandBackButton() }.noGlass() }
        } else {
            content
        }
    }
}

/// Hiding iOS's back button also turns off swipe-from-the-edge to go back; this turns it back on.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
