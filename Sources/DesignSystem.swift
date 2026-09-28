import SwiftUI
import AppKit

// Shared, appearance-aware surfaces keep the menu and all windows in step.
enum GS {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let canvas = adaptive(0xF8F9F6, 0x191D1B)
    static let sidebar = adaptive(0xEFF1EC, 0x141815)
    static let surface = adaptive(0xFFFFFF, 0x222824)
    static let inset = adaptive(0xF3F5F1, 0x1B211D)
    static let line = adaptive(0xE1E6DF, 0x343D36)
    static let ink = adaptive(0x202E25, 0xE9EFE8)
    static let muted = adaptive(0x69776D, 0xA0AEA3)
    static let accent = adaptive(0x26734D, 0x87CDA0)
    static let accentFill = adaptive(0x26734D, 0x9CDCB1)
    static let onAccent = adaptive(0xFFFFFF, 0x12251A)
    static let accentSoft = adaptive(0xE7F0E8, 0x283D2E)
    static let warning = adaptive(0x96621B, 0xE5B96D)
    static let danger = adaptive(0xB3453D, 0xF19589)
    static let avatarColors = [accent, adaptive(0x71669E, 0xB9AADF),
                               adaptive(0x986A43, 0xD9AF83), adaptive(0x477A9C, 0x94BFDA)]
}

struct GSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, kind == .quiet ? 8 : 13)
            .padding(.vertical, 9)
            .foregroundStyle(kind == .primary ? GS.onAccent : GS.ink)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(kind == .secondary ? GS.line : .clear))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }

    private func background(pressed: Bool) -> Color {
        if kind == .primary { return GS.accentFill.opacity(pressed ? 0.75 : hovered ? 0.9 : 1) }
        if pressed || hovered { return GS.accentSoft }
        return kind == .quiet ? .clear : GS.surface
    }
}

extension ButtonStyle where Self == GSButtonStyle {
    static var gsPrimary: GSButtonStyle { GSButtonStyle(kind: .primary) }
    static var gsSecondary: GSButtonStyle { GSButtonStyle(kind: .secondary) }
    static var gsQuiet: GSButtonStyle { GSButtonStyle(kind: .quiet) }
}

struct GSRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovered && isEnabled ? GS.accentSoft.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(hovered && isEnabled ? GS.accent.opacity(0.3) : .clear))
            .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.5)
            .onHover { hovered = $0 }
    }
}

extension ButtonStyle where Self == GSRowButtonStyle {
    static var gsRow: GSRowButtonStyle { GSRowButtonStyle() }
}

private struct GSFieldStyle: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($focused)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(GS.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? GS.accent : GS.line, lineWidth: focused ? 1.5 : 1))
    }
}

struct Surface: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(GS.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(highlighted ? GS.accent.opacity(0.45) : GS.line))
    }
}

extension View {
    func gsSurface(highlighted: Bool = false) -> some View { modifier(Surface(highlighted: highlighted)) }
    func gsField() -> some View {
        modifier(GSFieldStyle())
    }
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: size * 0.49, weight: .semibold))
            .foregroundStyle(GS.onAccent)
            .frame(width: size, height: size)
            .background(GS.accentFill, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct AccountAvatar: View {
    let login: String
    var size: CGFloat = 40
    var active = false

    private var color: Color {
        let colors = GS.avatarColors
        return colors[login.utf8.reduce(0) { ($0 + Int($1)) % colors.count }]
    }

    var body: some View {
        Text(String(login.prefix(2)).uppercased())
            .font(.system(size: size * 0.31, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? GS.accent : color)
            .frame(width: size, height: size)
            .background(active ? GS.accentSoft : color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(GS.muted)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                .foregroundStyle(GS.ink)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(GS.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StatusPill: View {
    var text = "Active"
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(GS.accent).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(GS.accent)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(GS.accentSoft, in: Capsule())
    }
}

struct Notice: View {
    let text: String
    var symbol = "info.circle"
    var color: Color = GS.muted
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(GS.accent)
                .frame(width: 58, height: 58)
                .background(GS.accentSoft, in: RoundedRectangle(cornerRadius: 18))
                .padding(.bottom, 4)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(GS.ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(GS.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 330)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(GS.muted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityCounts: View {
    let counts: GlanceCounts
    var compact = false
    var body: some View {
        HStack(spacing: 14) {
            Label(compact ? "\(counts.prs)" : "\(counts.prs) \(counts.prs == 1 ? "PR" : "PRs")", systemImage: "arrow.triangle.pull")
                .help("\(counts.prs) open pull requests").accessibilityLabel("\(counts.prs) open pull requests")
            Label(compact ? "\(counts.reviews)" : "\(counts.reviews) \(counts.reviews == 1 ? "review" : "reviews")", systemImage: "text.bubble")
                .help("\(counts.reviews) requested reviews").accessibilityLabel("\(counts.reviews) requested reviews")
            Label("\(counts.notifications >= 50 ? "50+" : String(counts.notifications))\(compact ? "" : " unread")", systemImage: "bell")
                .help("Unread notifications").accessibilityLabel("\(counts.notifications >= 50 ? "50 or more" : String(counts.notifications)) unread notifications")
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .monospacedDigit()
        .foregroundStyle(GS.muted)
    }
}
