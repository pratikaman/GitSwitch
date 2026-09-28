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
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Check before you commit", subtitle: "See which identity a repository is really using.")
            Button { chooseRepository() } label: {
                HStack(spacing: 16) {
                    if report != nil {
                        Image(systemName: "folder.fill").font(.system(size: 24)).foregroundStyle(GS.accent)
                    }
                    VStack(alignment: report == nil ? .center : .leading, spacing: report == nil ? 12 : 5) {
                        if report == nil {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 32, weight: .light)).foregroundStyle(GS.accent)
                        }
                        Text(path.isEmpty ? "Drop a repository here" : (path as NSString).lastPathComponent)
                            .font(.system(size: 16, weight: .semibold))
                        Text(path.isEmpty ? "or click to choose a folder" : collapseTilde(path))
                            .font(.system(size: 12, design: path.isEmpty ? .default : .monospaced))
                            .foregroundStyle(GS.muted).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: report == nil ? .center : .leading)
                    if report != nil {
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, report == nil ? 34 : 20)
                .background(dropTargeted ? GS.accentSoft : GS.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(dropTargeted ? GS.accent : GS.accent.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain).disabled(checking)
            .accessibilityLabel("Choose a repository, or drop a repository folder here")

            if checking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking your repository…").font(.system(size: 12)).foregroundStyle(GS.muted)
                }
            }
            if let error { Notice(text: error, symbol: "exclamationmark.circle", color: GS.danger) }
            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: report.ok ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(report.ok ? "Everything lines up" : "Something needs your attention")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(report.ok ? "No identity mismatches detected." : "Review the details before your next push.")
                                    .font(.system(size: 12))
                            }
                        }.foregroundStyle(report.ok ? GS.accent : GS.warning)
                        ForEach(report.problems, id: \.self) { problem in
                            Notice(text: problem, symbol: "exclamationmark.circle", color: GS.warning)
                        }
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                            row("Repository", (report.owner.map { "\($0)/\(report.repo ?? "?")" } ?? "Not on GitHub") + "  ·  \(report.branch)")
                            row("Remote", "\(report.protoDesc)  \(report.remoteURL ?? "None")")
                            row("Push account", report.pushAccount.map { "\($0) via \(report.pushVia)" } ?? "Unknown")
                            row("Commit identity", "\(report.commitName) <\(report.commitEmail)>")
                            row("Identity source", report.emailOrigin)
                            if let expected = report.expected { row("Expected account", expected) }
                        }
                        if let fixMessage { Notice(text: fixMessage) }
                    }.padding(20).gsSurface()
                }.frame(maxHeight: 340)
                if !report.ok, let expected = report.expected, state.accounts.contains(expected) {
                    HStack(spacing: 8) {
                        if expected != state.activeLogin {
                            Button("Switch to \(expected)") {
                                state.switchTo(expected)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { analyze() }
                            }.buttonStyle(.gsPrimary).disabled(state.busy || checking)
                        }
                        Button("Add folder rule") { addRule(login: expected, dir: report.root) }
                            .buttonStyle(.gsSecondary).disabled(checking)
                    }
                }
            } else if !checking {
                HStack(alignment: .top, spacing: 20) {
                    checkHint("Push account", symbol: "arrow.up.right", detail: "Where your credentials point")
                    checkHint("Commit identity", symbol: "person.crop.circle", detail: "The name behind your commits")
                    checkHint("Folder rules", symbol: "folder", detail: "What’s setting your identity")
                }.padding(.vertical, 8)
            }
            HStack {
                Notice(text: "Inspecting a repository doesn’t change its configuration.", symbol: "eye")
                if !path.isEmpty {
                    Button { analyze() } label: { Label("Check again", systemImage: "arrow.clockwise") }
                        .buttonStyle(.gsSecondary).disabled(checking || state.busy)
                }
            }
        }
        .padding(28).frame(width: 680)
        .foregroundStyle(GS.ink).background(GS.canvas).tint(GS.accent)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard !checking, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                if let url, url.isFileURL {
                    DispatchQueue.main.async { path = url.path; analyze() }
                }
            }
            return true
        }
    }

    private func chooseRepository() {
        if let directory = Panels.chooseDirectory(title: "Choose a Git repository") {
            path = directory
            analyze()
        }
    }

    private func checkHint(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(GS.accent).padding(.bottom, 3)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(GS.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(GS.muted)
            Text(value).font(.system(size: 12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func analyze() {
        guard !path.isEmpty else { return }
        checking = true
        report = nil
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
