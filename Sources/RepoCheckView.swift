import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RepoReport {
    var root = ""
    var branch = ""
    var remoteURL: String?
    var owner: String?
    var repo: String?
    var protoDesc = "—"
    var pushAccount: String?
    var pushVia = ""
    var commitName = ""
    var commitEmail = ""
    var emailOrigin = ""
    var expected: String?
    var problems: [String] = []
    var ok: Bool { problems.isEmpty }
}

struct RepoCheckView: View {
    @EnvironmentObject var state: AppState
    @State private var path = ""
    @State private var report: RepoReport?
    @State private var checking = false
    @State private var error: String?
    @State private var fixMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drop a repo folder here (or choose one) to see which account it will push and commit as.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Choose Repo…") {
                    if let d = Panels.chooseDirectory(title: "Choose a git repository") {
                        path = d
                        analyze()
                    }
                }
                Text(path.isEmpty ? "no repo selected" : collapseTilde(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                Button("Re-check") { analyze() }
                    .disabled(path.isEmpty || checking)
            }

            if let e = error {
                Label(e, systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let r = report {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        r.ok ? "Everything matches." : "Mismatch found",
                        systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(r.ok ? Color.green : Color.orange)

                    ForEach(r.problems, id: \.self) { p in
                        Text(p).font(.callout).foregroundStyle(.orange)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        row("Repository", (r.owner.map { "\($0)/\(r.repo ?? "?")" } ?? "not GitHub") + "  (\(r.branch))")
                        row("Remote", "\(r.protoDesc)  \(r.remoteURL ?? "none")")
                        row("Pushes as", r.pushAccount.map { "\($0)  via \(r.pushVia)" } ?? "unknown")
                        row("Commits as", "\(r.commitName) <\(r.commitEmail)>")
                        row("Identity from", r.emailOrigin)
                        if let ex = r.expected {
                            row("Expected account", ex)
                        }
                    }
                    .font(.callout)

                    if !r.ok {
                        HStack(spacing: 8) {
                            if let ex = r.expected, state.accounts.contains(ex),
                               ex != state.activeLogin {
                                Button("Switch to \(ex)") {
                                    state.switchTo(ex)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { analyze() }
                                }
                            }
                            if let ex = r.expected, state.accounts.contains(ex) {
                                Button("Add Folder Rule") { addRule(login: ex, dir: r.root) }
                            }
                        }
                        .controlSize(.small)
                    }
                    if let m = fixMessage {
                        Text(m).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 560, height: 400)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let u = url {
                    DispatchQueue.main.async {
                        path = u.path
                        analyze()
                    }
                }
            }
            return true
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    private func analyze() {
        guard !path.isEmpty else { return }
        checking = true
        error = nil
        fixMessage = nil
        let p = path
        let active = state.activeLogin
        let accounts = state.accounts
        let identities = state.identities
        DispatchQueue.global().async {
            var rep = RepoReport()
            let top = Shell.run(Shell.git, ["-C", p, "rev-parse", "--show-toplevel"])
            guard top.status == 0 else {
                DispatchQueue.main.async {
                    checking = false
                    report = nil
                    error = "Not a git repository."
                }
                return
            }
            rep.root = top.out.trimmingCharacters(in: .whitespacesAndNewlines)
            rep.branch = Shell.run(Shell.git, ["-C", rep.root, "rev-parse", "--abbrev-ref", "HEAD"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var url = Shell.run(Shell.git, ["-C", rep.root, "remote", "get-url", "--push", "origin"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if url.isEmpty {
                let first = Shell.run(Shell.git, ["-C", rep.root, "remote"]).out
                    .split(separator: "\n").first.map(String.init)
                if let f = first {
                    url = Shell.run(Shell.git, ["-C", rep.root, "remote", "get-url", "--push", f]).out
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            rep.remoteURL = url.isEmpty ? nil : url

            if let u = rep.remoteURL, let parsed = GitHubURL.parse(u) {
                if let host = parsed.sshHost {
                    rep.owner = parsed.owner
                    rep.repo = parsed.repo
                    rep.protoDesc = "SSH"
                    rep.pushVia = "the SSH key for '\(host)'"
                    rep.pushAccount = SSHManager.testAlias(host)
                    if rep.pushAccount == nil {
                        rep.problems.append("The SSH host '\(host)' did not authenticate with GitHub.")
                    }
                } else {
                    rep.owner = parsed.owner
                    rep.repo = parsed.repo
                    rep.protoDesc = "HTTPS"
                    rep.pushVia = "the active gh account"
                    rep.pushAccount = active
                }
            } else if rep.remoteURL == nil {
                rep.problems.append("This repo has no push remote.")
            } else {
                rep.problems.append("The remote is not a GitHub repository — GitSwitch doesn't manage it.")
            }

            rep.commitName = Shell.run(Shell.git, ["-C", rep.root, "config", "user.name"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rep.commitEmail = Shell.run(Shell.git, ["-C", rep.root, "config", "user.email"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let origin = Shell.run(Shell.git, ["-C", rep.root, "config", "--show-origin", "user.email"]).out
            if let originPath = origin.split(separator: "\t").first {
                rep.emailOrigin = collapseTilde(String(originPath).replacingOccurrences(of: "file:", with: ""))
            }

            if let owner = rep.owner {
                rep.expected = GuardManager.expectedAccount(forOwner: owner, accounts: accounts)
            }
            if let ex = rep.expected {
                if let push = rep.pushAccount, push != ex {
                    rep.problems.append("Pushes will use '\(push)' but this repo expects '\(ex)'.")
                }
                if let id = identities[ex], !id.email.isEmpty, rep.commitEmail != id.email {
                    rep.problems.append("Commits use \(rep.commitEmail), but \(ex) commits as \(id.email).")
                }
            }

            DispatchQueue.main.async {
                checking = false
                report = rep
            }
        }
    }

    private func addRule(login: String, dir: String) {
        guard let id = state.identity(for: login), !id.email.isEmpty else {
            fixMessage = "Set a commit email for \(login) first (Manage Accounts)."
            return
        }
        DispatchQueue.global().async {
            let e = RulesManager.addRule(dir: dir, login: login, identity: id)
            DispatchQueue.main.async {
                fixMessage = e ?? "Folder rule added — commits in this repo now use \(login)'s identity."
                state.loadRules()
                analyze()
            }
        }
    }
}
