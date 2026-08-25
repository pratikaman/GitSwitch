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
        VStack(alignment: .leading, spacing: 12) {
            Text("Clones with the right account and sets the repo's commit identity in one step.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    TextField("owner/repo or GitHub URL", text: $input)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Account").foregroundStyle(.secondary)
                    Picker("", selection: $account) {
                        ForEach(state.accounts, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                }
                GridRow {
                    Text("Into").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Choose…") {
                            if let d = Panels.chooseDirectory(title: "Folder to clone into") { dest = d }
                        }
                        Text(dest.isEmpty ? "no folder selected" : collapseTilde(dest))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Toggle("Add a folder rule so this repo always commits as \(account.isEmpty ? "that account" : account)", isOn: $makeRule)
                .font(.callout)

            HStack {
                Button(cloning ? "Cloning…" : "Clone") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cloning || input.isEmpty || account.isEmpty || dest.isEmpty)
                if cloning { ProgressView().controlSize(.small) }
                Spacer()
                if let cp = clonedPath {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cp)])
                    }
                }
            }

            if let s = status {
                ScrollView {
                    Text(s)
                        .font(.caption.monospaced())
                        .foregroundStyle(failed ? .red : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 520, height: 330)
        .onAppear {
            if account.isEmpty { account = state.activeLogin ?? state.accounts.first ?? "" }
            if dest.isEmpty {
                let dev = NSString(string: "~/Developer").expandingTildeInPath
                dest = FileManager.default.fileExists(atPath: dev)
                    ? dev
                    : NSString(string: "~/Downloads").expandingTildeInPath
            }
        }
    }

    private func clone() {
        guard let parsed = GitHubURL.parse(input) else {
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
