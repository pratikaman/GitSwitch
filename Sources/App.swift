import SwiftUI
import AppKit
import ServiceManagement

enum WindowID {
    static let addAccount = "add-account"
    static let manage = "manage-accounts"
    static let repoCheck = "repo-check"
    static let clone = "clone"
}

@main
struct GitSwitchApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("Add GitHub Account", id: WindowID.addAccount) {
            AddAccountView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("GitSwitch", id: WindowID.manage) {
            ManageView()
                .environmentObject(state)
        }
        .defaultSize(width: 940, height: 700)
        .windowResizability(.contentMinSize)

        Window("Check Repo", id: WindowID.repoCheck) {
            RepoCheckView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("Clone from GitHub", id: WindowID.clone) {
            CloneView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @AppStorage("showNameInMenuBar") private var showName = true

    private static let templateIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "tiff"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    private var icon: Image {
        if let ns = Self.templateIcon {
            return Image(nsImage: ns)
        }
        return Image(systemName: "person.crop.circle")
    }

    var body: some View {
        if showName, let login = state.activeLogin {
            HStack(spacing: 4) {
                icon.renderingMode(.template)
                Text(login)
            }
        } else {
            icon.renderingMode(.template)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedManageSection") private var section = "accounts"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                Text("GitSwitch").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                if state.busy { ProgressView().controlSize(.small) }
                Button { state.refresh(); state.refreshGlance(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.gsQuiet)
                .help("Refresh accounts and activity")
                .accessibilityLabel("Refresh accounts and activity")
            }
            .padding(18)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Switch account")
                    Spacer()
                    Text("github.com").font(.system(size: 10)).foregroundStyle(GS.muted)
                }
                .padding(.horizontal, 6)
                if state.accounts.isEmpty {
                    EmptyState(symbol: "person.crop.circle.badge.plus", title: "Your accounts, together",
                               detail: "Connect GitHub to switch accounts and keep your commits in the right name.")
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(state.accounts, id: \.self) { login in
                                menuAccount(login)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(state.accounts.count) * 74, 296))
                }
                Button { open(WindowID.addAccount) } label: {
                    Label("Connect an account", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gsSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)

            if let identity = state.gitIdentityNow, !identity.email.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Global commit identity")
                    Label(identity.email, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(GS.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .help(identity.email)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(GS.inset)
            }

            VStack(spacing: 2) {
                menuAction("Check a repository", symbol: "checkmark.shield", window: WindowID.repoCheck)
                menuAction("Clone a repository", symbol: "arrow.down.to.line", window: WindowID.clone)
                menuAction("Manage accounts", symbol: "person.2", window: WindowID.manage)
            }
            .padding(10)

            if let error = state.lastError {
                Notice(text: error, symbol: "exclamationmark.circle", color: GS.danger)
                    .lineLimit(3).help(error)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }

            Divider().overlay(GS.line)
            HStack {
                Button {
                    section = "preferences"
                    open(WindowID.manage)
                } label: { Label("Preferences", systemImage: "gearshape") }
                .buttonStyle(.gsQuiet)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.gsQuiet)
                    .keyboardShortcut("q")
            }
            .padding(8)
        }
        .frame(width: 356)
        .foregroundStyle(GS.ink)
        .background(GS.canvas)
        .tint(GS.accent)
        .onAppear {
            state.refresh()
            state.refreshGitIdentityNow()
            state.refreshGlance()
        }
    }

    private func menuAccount(_ login: String) -> some View {
        let active = state.activeLogin == login
        return Button { state.switchTo(login) } label: {
            HStack(spacing: 11) {
                AccountAvatar(login: login, size: 38, active: active)
                VStack(alignment: .leading, spacing: 6) {
                    Text(login).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(login)
                    if let counts = state.glance[login] {
                        ActivityCounts(counts: counts, compact: true)
                    } else {
                        Text(active ? "Current push account" : "Click to switch")
                            .font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                }
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(GS.accent)
                }
            }
            .padding(10)
            .frame(height: 69)
            .background(active ? GS.accentSoft.opacity(0.65) : GS.surface,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? GS.accent.opacity(0.25) : GS.line))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.gsRow)
        .disabled(state.busy)
        .accessibilityLabel(active ? "\(login), active account" : "Switch to \(login)")
    }

    private func menuAction(_ title: String, symbol: String, window: String) -> some View {
        Button {
            if window == WindowID.manage { section = "accounts" }
            open(window)
        } label: {
            HStack {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(GS.muted)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(GS.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gsQuiet)
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
