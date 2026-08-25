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
        VStack(alignment: .leading, spacing: 10) {
            Text("Repos inside a mapped folder always commit with that account's name and email — even if you forget to switch.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    if state.rules.isEmpty {
                        Text("No folder rules yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                    ForEach(state.rules) { rule in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collapseTilde(rule.dir))
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("commits as \(rule.login ?? "?")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") { remove(rule) }
                                .controlSize(.small)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button("Choose Folder…") {
                    if let d = Panels.chooseDirectory(title: "Folder whose repos belong to one account") {
                        newDir = d
                    }
                }
                Text(newDir.isEmpty ? "no folder selected" : collapseTilde(newDir))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Picker("", selection: $newLogin) {
                    ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Button("Add Rule") { add() }
                    .disabled(newDir.isEmpty || newLogin.isEmpty)
            }
            if let e = error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
            Text("Rules only control commit identity. Pushing still uses the active account — enable the Push Guard to catch that.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .onAppear {
            state.loadRules()
            if newLogin.isEmpty { newLogin = state.activeLogin ?? state.accounts.first ?? "" }
        }
    }

    private func add() {
        guard let id = state.identity(for: newLogin), !id.email.isEmpty else {
            error = "Set a commit email for \(newLogin) in the Accounts tab first."
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
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Block pushes from the wrong account", isOn: guardBinding)
                .disabled(foreign != nil)
            if let f = foreign {
                Text("You already have core.hooksPath set to \(f); GitSwitch won't override it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Installs a global pre-push hook. A push to a GitHub repo is blocked when the repo's owner expects a different account than the active one. Repos' own pre-push hooks still run. Bypass once with GITSWITCH_SKIP=1 git push.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("Organization mappings")
                .font(.headline)
            Text("Repos owned by your own accounts are matched automatically. Add org names here (e.g. a work org → work account).")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(mappings) { m in
                        HStack {
                            Text(m.owner).font(.callout)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                            Text(m.login).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove") { removeMapping(m) }.controlSize(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("org or owner name", text: $newOwner)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newLogin) {
                    ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Button("Add") { addMapping() }
                    .disabled(newOwner.trimmingCharacters(in: .whitespaces).isEmpty || newLogin.isEmpty)
            }
            if let e = error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("SSH-remote repos ignore account switching — they authenticate with whichever key GitHub knows. This shows who each SSH host in ~/.ssh/config actually signs in as.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    if aliases.isEmpty {
                        Text("No github.com hosts found in ~/.ssh/config.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    }
                    ForEach(aliases) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.host).font(.callout)
                                if let k = a.identityFile {
                                    Text(collapseTilde(k)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            switch results[a.host] {
                            case .none:
                                ProgressView().controlSize(.small)
                            case .some(let r) where r.hasPrefix("@"):
                                Label(String(r.dropFirst()), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            case .some:
                                Label("no access", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
            Divider()
            Text("Upload a public key to an account")
                .font(.headline)
            HStack(spacing: 8) {
                Picker("", selection: $selKey) {
                    ForEach(keys, id: \.self) { Text(collapseTilde($0)).tag($0) }
                }
                .labelsHidden()
                Picker("", selection: $selAccount) {
                    ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Button(uploading ? "Uploading…" : "Upload") { upload() }
                    .disabled(uploading || selKey.isEmpty || selAccount.isEmpty)
            }
            if let s = uploadStatus {
                Text(s).font(.caption).foregroundStyle(s.hasPrefix("Uploaded") ? .green : .red)
            }
        }
        .padding(14)
        .onAppear { reload() }
        .sheet(isPresented: $showScopeFlow) {
            DeviceCodeSheet(
                session: scopeSession,
                title: "Allow GitSwitch to manage SSH keys for \(selAccount)",
                onCancel: { cancelScopeFlow() }
            )
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
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            switch session.status {
            case .idle, .starting:
                ProgressView("Contacting GitHub…")
            case .waiting:
                Text(session.code ?? "…")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Text("The code is on your clipboard; enter it on the GitHub page that just opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization…").font(.caption).foregroundStyle(.secondary)
                }
            case .success:
                Label("Authorized", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let msg):
                Text(msg)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 340)
    }
}
