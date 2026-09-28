import SwiftUI
import ServiceManagement

struct ManageView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedManageSection") private var selection = "accounts"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(GS.line).frame(width: 1)
            VStack(spacing: 0) {
                Group {
                    switch selection {
                    case "rules": RulesView()
                    case "guard": GuardView()
                    case "ssh": SSHView()
                    case "preferences": PreferencesView()
                    default: AccountsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let error = state.lastError {
                    HStack(alignment: .top) {
                        Notice(text: error, symbol: "exclamationmark.circle", color: GS.danger)
                        Button { state.lastError = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.gsQuiet).accessibilityLabel("Dismiss error")
                    }
                    .padding(16).background(GS.surface)
                }
            }
        }
        .frame(minWidth: 880, idealWidth: 940, maxWidth: .infinity,
               minHeight: 650, idealHeight: 700, maxHeight: .infinity)
        .background(GS.canvas)
        .foregroundStyle(GS.ink)
        .tint(GS.accent)
        .onAppear {
            state.refresh()
            state.refreshGitIdentityNow()
            state.refreshGlance()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitSwitch").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("A little less context switching.")
                        .font(.system(size: 9)).foregroundStyle(GS.muted)
                }
            }
            .padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 36)
            Eyebrow(text: "Workspace").padding(.horizontal, 24).padding(.bottom, 12)
            VStack(spacing: 4) {
                navItem("Accounts", symbol: "person.2", id: "accounts", count: state.accounts.count)
                navItem("Folder rules", symbol: "folder", id: "rules")
                navItem("Push guard", symbol: "shield.lefthalf.filled", id: "guard")
                navItem("SSH keys", symbol: "key.horizontal", id: "ssh")
            }.padding(.horizontal, 12)
            Eyebrow(text: "Repository tools").padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 12)
            VStack(spacing: 4) {
                toolItem("Check repository", symbol: "checkmark.shield", window: WindowID.repoCheck)
                toolItem("Clone repository", symbol: "arrow.down.to.line", window: WindowID.clone)
            }.padding(.horizontal, 12)
            Spacer()
            navItem("Preferences", symbol: "slider.horizontal.3", id: "preferences")
                .padding(.horizontal, 12).padding(.bottom, 18)
            Rectangle().fill(GS.line).frame(height: 1).padding(.horizontal, 20)
            HStack(spacing: 9) {
                if let active = state.activeLogin {
                    AccountAvatar(login: active, size: 30, active: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(active).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text("Active on this Mac").font(.system(size: 10)).foregroundStyle(GS.muted)
                    }
                    Spacer(minLength: 0)
                    Circle().fill(GS.accent).frame(width: 6, height: 6)
                } else {
                    Image(systemName: "person.crop.circle").foregroundStyle(GS.muted)
                    Text("No active account").font(.system(size: 11)).foregroundStyle(GS.muted)
                }
            }
            .padding(20)
        }
        .frame(width: 216)
        .background(GS.sidebar)
    }

    private func navItem(_ title: String, symbol: String, id: String, count: Int? = nil) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selection == id ? .semibold : .medium))
                Spacer()
                if let count {
                    Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(GS.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .foregroundStyle(selection == id ? GS.accent : GS.muted)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(selection == id ? GS.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.gsRow)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }

    private func toolItem(_ title: String, symbol: String, window: String) -> some View {
        Button {
            openWindow(id: window)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 8))
            }
            .foregroundStyle(GS.muted).padding(.horizontal, 12).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gsRow)
    }
}

struct AccountsTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                PageHeader(title: "Your accounts", subtitle: "Different contexts. One place to switch.")
                Spacer(minLength: 0)
                Button { openWindow(id: WindowID.addAccount) } label: {
                    Label("Connect account", systemImage: "plus")
                }
                .buttonStyle(.gsPrimary)
            }
            .padding(28)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.accounts.isEmpty {
                        VStack(spacing: 0) {
                            EmptyState(symbol: "person.2", title: "Make yourself at home",
                                       detail: "Connect your personal and work accounts. The right identity is always a click away.")
                            Button("Connect your first account") { openWindow(id: WindowID.addAccount) }
                                .buttonStyle(.gsPrimary).padding(.bottom, 28)
                        }.gsSurface()
                    } else {
                        HStack {
                            Eyebrow(text: "Connected accounts")
                            Spacer()
                            Text("\(state.accounts.count) connected to GitHub")
                                .font(.system(size: 11)).foregroundStyle(GS.muted)
                        }
                        ForEach(state.accounts, id: \.self) { login in
                            AccountCard(login: login)
                        }
                        Notice(text: "Switching updates your HTTPS push account. Folder rules and repository settings can override your commit identity.")
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow(text: "Global git identity")
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(GS.accent)
                    if let identity = state.gitIdentityNow, !identity.email.isEmpty {
                        Text(identity.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(identity.email).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(GS.muted).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).help(identity.email)
                    } else {
                        Text("No global commit identity set").font(.system(size: 12)).foregroundStyle(GS.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GS.sidebar.opacity(0.55))
            .overlay(alignment: .top) { Rectangle().fill(GS.line).frame(height: 1) }
        }
    }
}

struct AccountCard: View {
    @EnvironmentObject var state: AppState
    let login: String
    @State private var confirmSignOut = false
    @State private var fetching = false
    private var isActive: Bool { state.activeLogin == login }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AccountAvatar(login: login, size: 44, active: isActive)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(login).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if isActive { StatusPill() }
                    }
                    if let counts = state.glance[login] {
                        ActivityCounts(counts: counts)
                    } else {
                        Text("GitHub account").font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                }
                Spacer(minLength: 8)
                if !isActive {
                    Button { state.switchTo(login) } label: {
                        Label("Switch", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.gsSecondary).disabled(state.busy || fetching)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                FormField(label: "Commit name") {
                    TextField("Your name", text: nameBinding).gsField()
                        .accessibilityLabel("Commit name for \(login)")
                }
                FormField(label: "Commit email") {
                    TextField("Commit email", text: emailBinding, prompt: Text(verbatim: "you@example.com")).gsField()
                        .accessibilityLabel("Commit email for \(login)")
                }
            }
            HStack(spacing: 4) {
                Button {
                    fetching = true
                    state.fetchIdentityFromGitHub(for: login) { fetching = false }
                } label: {
                    Label(fetching ? "Fetching…" : "Use GitHub profile", systemImage: "arrow.down.circle")
                }
                .help("Fill empty fields with your GitHub name and email.")
                .disabled(fetching || state.busy)
                if isActive {
                    Button {
                        if let identity = state.identity(for: login) {
                            state.applyGitIdentity(identity)
                        }
                    } label: { Label("Apply to Git", systemImage: "checkmark") }
                    .disabled(state.busy)
                    .help("Apply this identity to your global Git configuration.")
                }
                Spacer(minLength: 0)
                Button { confirmSignOut = true } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(GS.muted)
                }
                .disabled(state.busy || fetching)
                .help("Sign out of \(login)")
                .accessibilityLabel("Sign out of \(login)")
            }
            .buttonStyle(.gsQuiet)
            .padding(.horizontal, -8).padding(.vertical, -5)
        }
        .padding(20)
        .gsSurface(highlighted: isActive)
        .alert("Sign out of \(login)?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { state.signOut(login) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account’s GitHub CLI token from this Mac. You can connect it again anytime.")
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { state.identity(for: login)?.name ?? "" }, set: { state.setIdentity(login, name: $0) })
    }
    private var emailBinding: Binding<String> {
        Binding(get: { state.identity(for: login)?.email ?? "" }, set: { state.setIdentity(login, email: $0) })
    }
}

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("syncGitIdentity") private var syncIdentity = true
    @AppStorage("showNameInMenuBar") private var showName = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(title: "Preferences", subtitle: "A few small things to make GitSwitch yours.")
                VStack(spacing: 0) {
                    preference("Sync commit identity", detail: "Update your global Git name and email when you switch accounts.", symbol: "arrow.triangle.branch", isOn: $syncIdentity)
                    Divider().padding(.horizontal, 20)
                    preference("Account in menu bar", detail: "Keep your active GitHub username in view.", symbol: "menubar.rectangle", isOn: $showName)
                    Divider().padding(.horizontal, 20)
                    preference("Launch at login", detail: "Have GitSwitch ready when you start your Mac.", symbol: "power", isOn: launchAtLogin)
                }.gsSurface()
                HStack(spacing: 12) {
                    BrandMark(size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GitSwitch").font(.system(size: 13, weight: .semibold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · Made for your Mac")
                            .font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                }.padding(.top, 6)
            }.padding(28)
        }
    }

    private func preference(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(GS.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(GS.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(20)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enable in
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                state.lastError = "Launch at login: \(error.localizedDescription)"
            }
        })
    }
}
