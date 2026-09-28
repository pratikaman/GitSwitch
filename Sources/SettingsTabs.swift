import SwiftUI
import AppKit

func collapseTilde(_ p: String) -> String {
    let home = NSHomeDirectory()
    return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}

enum Panels {
    static func chooseDirectory(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = title
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

// MARK: - Folder rules tab

struct RulesView: View {
    @EnvironmentObject var state: AppState
    @State private var newDir = ""
    @State private var newLogin = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Folder rules", subtitle: "The right commit identity, wherever you work.")
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.person.crop")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(GS.accent)
                    Text("Give a folder an account. Every repository inside it will use that account’s commit name and email automatically.")
                        .font(.system(size: 13)).foregroundStyle(GS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(GS.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Your folder rules")
                    if state.rules.isEmpty {
                        EmptyState(symbol: "folder.badge.plus", title: "A place for every account",
                                   detail: "Keep work in one folder and personal projects in another. Add your first rule below.")
                            .gsSurface()
                    }
                    ForEach(state.rules) { rule in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill").foregroundStyle(GS.accent)
                                .frame(width: 34, height: 34).background(GS.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(collapseTilde(rule.dir)).font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle).help(rule.dir)
                                Text("Commits as \(rule.login ?? "unknown account")")
                                    .font(.system(size: 11)).foregroundStyle(GS.muted)
                            }
                            Spacer(minLength: 8)
                            Button { remove(rule) } label: { Image(systemName: "trash").foregroundStyle(GS.muted) }
                                .buttonStyle(.gsQuiet).help("Remove folder rule")
                                .accessibilityLabel("Remove rule for \(collapseTilde(rule.dir))")
                        }
                        .padding(14).gsSurface()
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add a folder rule").font(.system(size: 14, weight: .semibold))
                    FormField(label: "Folder") {
                        HStack {
                            Image(systemName: "folder").foregroundStyle(GS.muted)
                            Text(newDir.isEmpty ? "Choose a folder for your repositories" : collapseTilde(newDir))
                                .font(.system(size: 12)).foregroundStyle(newDir.isEmpty ? GS.muted : GS.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button("Browse…") {
                                if let d = Panels.chooseDirectory(title: "Folder whose repos belong to one account") { newDir = d }
                            }.buttonStyle(.gsSecondary)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        FormField(label: "Commit as") {
                            Picker("Account for folder rule", selection: $newLogin) {
                                Text("Select an account").tag("")
                                ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button { add() } label: { Label("Add rule", systemImage: "plus") }
                            .buttonStyle(.gsPrimary).disabled(newDir.isEmpty || newLogin.isEmpty)
                    }
                    if let error { Notice(text: error, symbol: "exclamationmark.circle", color: GS.danger) }
                }.padding(20).gsSurface()
                Notice(text: "Folder rules set commit identity. Pushes still use your active account; Push Guard can catch a mismatch.")
            }.padding(28)
        }
        .onAppear {
            state.loadRules()
            if newLogin.isEmpty { newLogin = state.activeLogin ?? state.accounts.first ?? "" }
        }
    }

    private func add() {
        guard let id = state.identity(for: newLogin), !id.email.isEmpty else {
            error = "Set a commit email for \(newLogin) in Accounts first."
            return
        }
        error = nil
        let dir = newDir
        let login = newLogin
        DispatchQueue.global().async {
            let e = RulesManager.addRule(dir: dir, login: login, identity: id)
            DispatchQueue.main.async {
                error = e
                if e == nil { newDir = "" }
                state.loadRules()
            }
        }
    }

    private func remove(_ rule: FolderRule) {
        DispatchQueue.global().async {
            RulesManager.removeRule(rule)
            DispatchQueue.main.async { state.loadRules() }
        }
    }
}

// MARK: - Push guard tab

struct GuardMapping: Identifiable {
    var owner: String
    var login: String
    var id: String { owner }
}

struct GuardView: View {
    @EnvironmentObject var state: AppState
    @State private var enabled = false
    @State private var foreign: String?
    @State private var mappings: [GuardMapping] = []
    @State private var newOwner = ""
    @State private var newLogin = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Push guard", subtitle: "A final check before your code leaves your Mac.")
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: enabled ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 28, weight: .light)).foregroundStyle(GS.accent)
                            .frame(width: 52, height: 52).background(GS.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(enabled ? "Your pushes are protected" : "Check before you push")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Block GitHub pushes from the wrong account.")
                                .font(.system(size: 12)).foregroundStyle(GS.muted)
                        }
                        Spacer()
                        Toggle("Block pushes from the wrong account", isOn: guardBinding)
                            .labelsHidden().toggleStyle(.switch).disabled(foreign != nil)
                    }
                    if let foreign {
                        Notice(text: "Your Git hooks are already managed at \(foreign). GitSwitch will leave that setting in place.", symbol: "exclamationmark.triangle", color: GS.warning)
                    } else {
                        Notice(text: "Checks the repository owner against your active account. Existing repository hooks continue to run.")
                    }
                }.padding(20).gsSurface(highlighted: enabled)
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Organization mappings")
                    Text("Your own accounts are matched automatically. Map an organization to the account you use there.")
                        .font(.system(size: 12)).foregroundStyle(GS.muted)
                    if mappings.isEmpty {
                        EmptyState(symbol: "building.2", title: "Bring your organizations along",
                                   detail: "Add an organization below so Push Guard knows which account belongs to it.").gsSurface()
                    }
                    ForEach(mappings) { mapping in
                        HStack(spacing: 12) {
                            Image(systemName: "building.2").foregroundStyle(GS.muted)
                            Text(mapping.owner).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(GS.muted)
                            Text(mapping.login).font(.system(size: 12)).foregroundStyle(GS.accent).lineLimit(1)
                            Spacer()
                            Button { removeMapping(mapping) } label: { Image(systemName: "trash") }
                                .buttonStyle(.gsQuiet).accessibilityLabel("Remove mapping for \(mapping.owner)")
                        }.padding(14).gsSurface()
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect an organization").font(.system(size: 14, weight: .semibold))
                    HStack(alignment: .bottom, spacing: 12) {
                        FormField(label: "Organization or owner") {
                            TextField("e.g. your-team", text: $newOwner).gsField()
                                .accessibilityLabel("Organization or owner name")
                        }
                        FormField(label: "Account") {
                            Picker("Account for organization", selection: $newLogin) {
                                Text("Select an account").tag("")
                                ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().padding(.vertical, 6)
                        }
                        Button("Add") { addMapping() }.buttonStyle(.gsPrimary)
                            .disabled(newOwner.trimmingCharacters(in: .whitespaces).isEmpty || newLogin.isEmpty)
                    }
                    if let error { Notice(text: error, symbol: "exclamationmark.circle", color: GS.danger) }
                }.padding(20).gsSurface()
                Notice(text: "Need a one-time bypass? Run GITSWITCH_SKIP=1 git push.", symbol: "terminal")
            }.padding(28)
        }
        .onAppear { reload() }
    }

    private var guardBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { on in
                DispatchQueue.global().async {
                    var err: String?
                    if on { err = GuardManager.enable() } else { GuardManager.disable() }
                    DispatchQueue.main.async {
                        error = err
                        reload()
                    }
                }
            }
        )
    }

    private func reload() {
        DispatchQueue.global().async {
            let en = GuardManager.isEnabled()
            let fr = GuardManager.foreignHooksPath()
            let maps = GuardManager.loadMappings().map { GuardMapping(owner: $0.owner, login: $0.login) }
            DispatchQueue.main.async {
                enabled = en
                foreign = fr
                mappings = maps
                if newLogin.isEmpty { newLogin = state.activeLogin ?? state.accounts.first ?? "" }
            }
        }
    }

    private func addMapping() {
        let owner = newOwner.trimmingCharacters(in: .whitespaces)
        var maps = mappings.filter { $0.owner.lowercased() != owner.lowercased() }
        maps.append(GuardMapping(owner: owner, login: newLogin))
        save(maps)
        newOwner = ""
    }

    private func removeMapping(_ m: GuardMapping) {
        save(mappings.filter { $0.owner != m.owner })
    }

    private func save(_ maps: [GuardMapping]) {
        DispatchQueue.global().async {
            GuardManager.saveMappings(maps.map { ($0.owner, $0.login) })
            DispatchQueue.main.async { reload() }
        }
    }
}

// MARK: - SSH tab

struct SSHView: View {
    @EnvironmentObject var state: AppState
    @State private var aliases: [SSHAlias] = []
    @State private var results: [String: String] = [:]
    @State private var keys: [String] = []
    @State private var selKey = ""
    @State private var selAccount = ""
    @State private var uploadStatus: String?
    @State private var uploading = false
    @State private var showScopeFlow = false
    @State private var prevActive: String?
    @StateObject private var scopeSession = LoginSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    PageHeader(title: "SSH keys", subtitle: "Know who’s on the other end of your connection.")
                    Spacer()
                    Button { retestAll() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.gsSecondary).help("Retest SSH connections")
                        .accessibilityLabel("Retest SSH connections")
                }
                Notice(text: "SSH repositories use their key’s identity, independently of your active account. These connections come from your SSH configuration.", symbol: "key.horizontal")
                    .padding(18).background(GS.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "GitHub connections")
                    if aliases.isEmpty {
                        EmptyState(symbol: "key.horizontal", title: "No SSH hosts yet",
                                   detail: "GitHub hosts in ~/.ssh/config will appear here, along with the account each key connects to.").gsSurface()
                    }
                    ForEach(aliases) { alias in
                        HStack(spacing: 12) {
                            Image(systemName: "terminal").foregroundStyle(GS.accent)
                                .frame(width: 34, height: 34).background(GS.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(alias.host).font(.system(size: 13, weight: .medium, design: .monospaced))
                                if let key = alias.identityFile {
                                    Text(collapseTilde(key)).font(.system(size: 11)).foregroundStyle(GS.muted)
                                        .lineLimit(1).truncationMode(.middle).help(key)
                                }
                            }
                            Spacer()
                            switch results[alias.host] {
                            case .none:
                                ProgressView().controlSize(.small).accessibilityLabel("Testing connection")
                            case .some(let result) where result.hasPrefix("@"):
                                Label(String(result.dropFirst()), systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11)).foregroundStyle(GS.accent)
                            case .some:
                                Label("No access", systemImage: "exclamationmark.circle")
                                    .font(.system(size: 11)).foregroundStyle(GS.warning)
                            }
                        }.padding(16).gsSurface()
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add a key to GitHub").font(.system(size: 14, weight: .semibold))
                        Text("Upload an existing public key to one of your accounts.")
                            .font(.system(size: 12)).foregroundStyle(GS.muted)
                    }
                    if keys.isEmpty {
                        Notice(text: "No public keys found in ~/.ssh. Create an SSH key to get started.")
                    }
                    FormField(label: "Public key") {
                        Picker("Public key", selection: $selKey) {
                            Text("Select a public key").tag("")
                            ForEach(keys, id: \.self) { Text(collapseTilde($0)).tag($0) }
                        }.labelsHidden()
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        FormField(label: "GitHub account") {
                            Picker("GitHub account for key", selection: $selAccount) {
                                Text("Select an account").tag("")
                                ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden()
                        }
                        Button { upload() } label: {
                            Label(uploading ? "Uploading…" : "Upload key", systemImage: "arrow.up.to.line")
                        }
                        .buttonStyle(.gsPrimary).disabled(uploading || selKey.isEmpty || selAccount.isEmpty)
                    }
                    .disabled(uploading)
                    if let uploadStatus {
                        Notice(text: uploadStatus, symbol: uploadStatus.hasPrefix("Uploaded") ? "checkmark.circle" : "info.circle",
                               color: uploadStatus.hasPrefix("Uploaded") ? GS.accent : GS.danger)
                    }
                }.padding(20).gsSurface()
            }.padding(28)
        }
        .onAppear { reload() }
        .sheet(isPresented: $showScopeFlow) {
            DeviceCodeSheet(session: scopeSession,
                            title: "Manage SSH keys for \(selAccount)",
                            onCancel: { cancelScopeFlow() })
        }
    }

    private func reload() {
        let found = SSHManager.githubAliases()
        aliases = found
        keys = SSHManager.publicKeys()
        if selKey.isEmpty { selKey = keys.first ?? "" }
        if selAccount.isEmpty { selAccount = state.activeLogin ?? state.accounts.first ?? "" }
        for a in found where results[a.host] == nil {
            let host = a.host
            DispatchQueue.global().async {
                let login = SSHManager.testAlias(host)
                DispatchQueue.main.async {
                    results[host] = login.map { "@\($0)" } ?? "-"
                }
            }
        }
    }

    private func retestAll() {
        results = [:]
        reload()
    }

    private func upload() {
        uploading = true
        uploadStatus = nil
        let key = selKey
        let account = selAccount
        let prev = state.activeLogin
        prevActive = prev
        DispatchQueue.global().async {
            if account != prev {
                let s = Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", account])
                if s.status != 0 {
                    finish("Couldn't switch to \(account).", restore: false)
                    return
                }
            }
            let r = Shell.run(Shell.gh, ["ssh-key", "add", key, "--title", "GitSwitch \(Host.current().localizedName ?? "Mac")"])
            if r.status == 0 {
                finish("Uploaded ✓ — key added to \(account).", restore: true)
            } else if (r.err + r.out).contains("public_key") || (r.err + r.out).lowercased().contains("scope") {
                DispatchQueue.main.async {
                    scopeSession.onSuccess = { retryAfterScope(key: key, account: account) }
                    showScopeFlow = true
                    scopeSession.start(args: ["auth", "refresh", "--hostname", "github.com", "-s", "admin:public_key"])
                }
            } else {
                let e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(e.isEmpty ? "Upload failed." : e, restore: true)
            }
        }
    }

    private func retryAfterScope(key: String, account: String) {
        showScopeFlow = false
        DispatchQueue.global().async {
            let r = Shell.run(Shell.gh, ["ssh-key", "add", key, "--title", "GitSwitch \(Host.current().localizedName ?? "Mac")"])
            if r.status == 0 {
                finish("Uploaded ✓ — key added to \(account).", restore: true)
            } else {
                let e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(e.isEmpty ? "Upload failed after granting access." : e, restore: true)
            }
        }
    }

    private func cancelScopeFlow() {
        scopeSession.cancel(silent: true)
        showScopeFlow = false
        DispatchQueue.global().async {
            restorePrevious()
            DispatchQueue.main.async {
                uploading = false
                uploadStatus = "Cancelled."
            }
        }
    }

    // Runs on a background queue.
    private func finish(_ message: String, restore: Bool) {
        if restore { restorePrevious() }
        DispatchQueue.main.async {
            uploading = false
            uploadStatus = message
            state.refresh()
            if message.hasPrefix("Uploaded") { retestAll() }
        }
    }

    // Runs on a background queue.
    private func restorePrevious() {
        if let prev = prevActive, prev != selAccount {
            Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", prev])
        }
    }
}

// MARK: - Device-code sheet (reused for scope grants)

struct DeviceCodeSheet: View {
    @ObservedObject var session: LoginSession
    let title: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.horizontal").font(.system(size: 28)).foregroundStyle(GS.accent)
            Text(title).font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            switch session.status {
            case .idle, .starting:
                ProgressView("Contacting GitHub…")
            case .waiting:
                AuthorizationCodeView(session: session)
                Text("Enter this code on GitHub to give this account access to manage SSH keys.")
                    .font(.system(size: 12)).foregroundStyle(GS.muted).multilineTextAlignment(.center)
                Button { session.openVerificationPage() } label: {
                    Label("Continue on GitHub", systemImage: "arrow.up.right")
                }.buttonStyle(.gsPrimary)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization…").font(.system(size: 11)).foregroundStyle(GS.muted)
                }
            case .success:
                Label("Authorized", systemImage: "checkmark.circle.fill").foregroundStyle(GS.accent)
            case .failed(let message):
                Notice(text: message, symbol: "exclamationmark.circle", color: GS.danger)
            }
            Button("Cancel", action: onCancel).buttonStyle(.gsSecondary).keyboardShortcut(.cancelAction)
        }
        .padding(28).frame(width: 420)
        .foregroundStyle(GS.ink).background(GS.canvas).tint(GS.accent)
    }
}
