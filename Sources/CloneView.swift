import SwiftUI
import AppKit

struct CloneView: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @State private var account = ""
    @AppStorage("lastCloneDest") private var dest = ""
    @State private var makeRule = true
    @State private var cloning = false
    @State private var status: String?
    @State private var failed = false
    @State private var clonedPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 23, weight: .light)).foregroundStyle(GS.accent)
                    .frame(width: 52, height: 52).background(GS.accentSoft, in: RoundedRectangle(cornerRadius: 15))
                PageHeader(title: "Start in the right place", subtitle: "Clone a repository with the account it belongs to.")
            }
            VStack(alignment: .leading, spacing: 20) {
                FormField(label: "GitHub repository") {
                    TextField("owner/repository or a GitHub URL", text: $input).gsField()
                        .accessibilityLabel("GitHub repository")
                }
                FormField(label: "Clone with") {
                    Picker("Account to clone with", selection: $account) {
                        Text("Select an account").tag("")
                        ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }
                FormField(label: "Destination folder") {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(GS.accent)
                        Text(dest.isEmpty ? "Choose a destination" : collapseTilde(dest))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(GS.muted)
                            .lineLimit(1).truncationMode(.middle).help(dest)
                        Spacer(minLength: 8)
                        Button("Browse…") {
                            if let directory = Panels.chooseDirectory(title: "Folder to clone into") { dest = directory }
                        }.buttonStyle(.gsSecondary)
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Remember this identity").font(.system(size: 13, weight: .semibold))
                        Text("Add a folder rule so future commits use \(account.isEmpty ? "this account" : account).")
                            .font(.system(size: 12)).foregroundStyle(GS.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("Remember this identity", isOn: $makeRule).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            .padding(22).gsSurface().disabled(cloning)
            if state.accounts.isEmpty {
                Notice(text: "Connect a GitHub account from the menu bar before cloning.", symbol: "person.crop.circle.badge.plus")
            }
            if let status {
                ScrollView {
                    Notice(text: status, symbol: failed ? "exclamationmark.circle" : clonedPath == nil ? "arrow.down.circle" : "checkmark.circle",
                           color: failed ? GS.danger : clonedPath == nil ? GS.muted : GS.accent)
                        .padding(14)
                }
                .frame(maxHeight: 90)
                .background(GS.inset, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 10) {
                if cloning {
                    ProgressView().controlSize(.small)
                    Text("Bringing your repository home…").font(.system(size: 11)).foregroundStyle(GS.muted)
                } else {
                    Text("Uses this account’s saved commit identity.")
                        .font(.system(size: 11)).foregroundStyle(GS.muted)
                }
                Spacer(minLength: 0)
                if let clonedPath {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: clonedPath)])
                    }.buttonStyle(.gsSecondary)
                } else {
                    Button { clone() } label: {
                        Label(cloning ? "Cloning…" : "Clone repository", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.gsPrimary).keyboardShortcut(.defaultAction)
                    .disabled(cloning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.isEmpty || dest.isEmpty)
                }
            }
        }
        .padding(28)
        .frame(width: 620)
        .foregroundStyle(GS.ink).background(GS.canvas).tint(GS.accent)
        .onAppear {
            if account.isEmpty { account = state.activeLogin ?? state.accounts.first ?? "" }
            if dest.isEmpty {
                let developer = NSString(string: "~/Developer").expandingTildeInPath
                dest = FileManager.default.fileExists(atPath: developer)
                    ? developer : NSString(string: "~/Downloads").expandingTildeInPath
            }
        }
        .onChange(of: input) { _ in clonedPath = nil; status = nil }
        .onChange(of: account) { _ in clonedPath = nil; status = nil }
        .onChange(of: dest) { _ in clonedPath = nil; status = nil }
    }

    private func clone() {
        guard let parsed = GitHubURL.parse(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = "Couldn't parse that — use owner/repo or a GitHub URL."
            failed = true
            return
        }
        let owner = parsed.owner, repo = parsed.repo
        let target = dest + "/" + repo
        guard !FileManager.default.fileExists(atPath: target) else {
            status = "\(collapseTilde(target)) already exists."
            failed = true
            return
        }
        cloning = true
        failed = false
        clonedPath = nil
        status = "Cloning \(owner)/\(repo) as \(account)…"
        let acct = account
        let addRule = makeRule
        let identity = state.identity(for: acct)
        let active = state.activeLogin
        DispatchQueue.global().async {
            if acct != active {
                let s = Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", acct])
                if s.status != 0 {
                    fail("Couldn't switch to \(acct).")
                    return
                }
            }
            let r = Shell.run(Shell.gh, ["repo", "clone", "\(owner)/\(repo)", target])
            guard r.status == 0 else {
                let e = (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
                fail(e.isEmpty ? "Clone failed." : e)
                return
            }
            var notes: [String] = []
            if let id = identity, !id.email.isEmpty {
                Shell.run(Shell.git, ["-C", target, "config", "user.name", id.name])
                Shell.run(Shell.git, ["-C", target, "config", "user.email", id.email])
                notes.append("commit identity set to \(id.email)")
            }
            if addRule, let id = identity, !id.email.isEmpty {
                if RulesManager.addRule(dir: target, login: acct, identity: id) == nil {
                    notes.append("folder rule added")
                }
            }
            DispatchQueue.main.async {
                cloning = false
                clonedPath = target
                status = "Done — cloned to \(collapseTilde(target))"
                    + (notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))")
                    + ". Active account is now \(acct)."
                state.refresh()
                state.loadRules()
            }
        }
    }

    // Runs on a background queue.
    private func fail(_ message: String) {
        DispatchQueue.main.async {
            cloning = false
            failed = true
            status = message
        }
    }
}
