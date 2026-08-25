import Foundation
import SwiftUI

struct GitIdentity: Codable, Equatable {
    var name: String = ""
    var email: String = ""
}

struct GlanceCounts: Equatable {
    var prs: Int
    var reviews: Int
    var notifications: Int
    var fetchedAt: Date
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var accounts: [String] = []
    @Published var activeLogin: String?
    @Published var busy = false
    @Published var lastError: String?
    @Published var gitIdentityNow: GitIdentity?
    @Published private(set) var identities: [String: GitIdentity] = [:]
    @Published var glance: [String: GlanceCounts] = [:]
    @Published var rules: [FolderRule] = []

    private var timer: Timer?
    private var glanceTimer: Timer?
    private var glanceInFlight = false
    private var autoFetchAttempted = Set<String>()
    private let hostsPath = NSString(string: "~/.config/gh/hosts.yml").expandingTildeInPath

    private init() {
        loadIdentities()
        refresh()
        refreshGitIdentityNow()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        loadRules()
        refreshGlance()
        glanceTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refreshGlance(force: true)
        }
    }

    func loadRules() {
        DispatchQueue.global().async { [weak self] in
            let r = RulesManager.loadRules()
            DispatchQueue.main.async {
                if r != self?.rules { self?.rules = r }
            }
        }
    }

    /// Per-account PR / review-request / notification counts, fetched with each
    /// account's own token (no switching involved).
    func refreshGlance(force: Bool = false) {
        guard !glanceInFlight else { return }
        if !force, let newest = glance.values.map(\.fetchedAt).max(),
           Date().timeIntervalSince(newest) < 300 { return }
        let logins = accounts
        guard !logins.isEmpty else { return }
        glanceInFlight = true
        DispatchQueue.global().async { [weak self] in
            var result: [String: GlanceCounts] = [:]
            for login in logins {
                let tok = Shell.run(Shell.gh, ["auth", "token", "--user", login]).out
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tok.isEmpty else { continue }
                func count(_ path: String, _ jq: String) -> Int? {
                    let r = Shell.run(Shell.gh, ["api", path, "--jq", jq], extraEnv: ["GH_TOKEN": tok])
                    guard r.status == 0 else { return nil }
                    return Int(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                let prs = count("search/issues?q=is:pr+is:open+author:\(login)", ".total_count")
                let reviews = count("search/issues?q=is:pr+is:open+review-requested:\(login)", ".total_count")
                let notifs = count("notifications?per_page=50", "length")
                if prs != nil || reviews != nil || notifs != nil {
                    result[login] = GlanceCounts(
                        prs: prs ?? 0, reviews: reviews ?? 0,
                        notifications: notifs ?? 0, fetchedAt: Date())
                }
            }
            DispatchQueue.main.async {
                self?.glanceInFlight = false
                self?.glance.merge(result) { _, new in new }
            }
        }
    }

    var identitySyncEnabled: Bool {
        UserDefaults.standard.object(forKey: "syncGitIdentity") as? Bool ?? true
    }

    // MARK: - Account discovery (reads gh's hosts.yml)

    func refresh() {
        guard let text = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            if !accounts.isEmpty { accounts = [] }
            if activeLogin != nil { activeLogin = nil }
            return
        }
        var found: [String] = []
        var active: String?
        var inGitHubHost = false
        var inUsers = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent == 0 {
                inGitHubHost = (trimmed == "github.com:")
                inUsers = false
                continue
            }
            guard inGitHubHost else { continue }
            if indent == 4 {
                inUsers = (trimmed == "users:")
                if trimmed.hasPrefix("user:") {
                    active = String(trimmed.dropFirst("user:".count)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if inUsers, indent == 8, trimmed.hasSuffix(":") {
                found.append(String(trimmed.dropLast()))
            }
        }
        if found != accounts { accounts = found }
        if active != activeLogin { activeLogin = active }

        // Fill in identity for the active account once, so the UI has something to show.
        if let a = active, identities[a] == nil, !autoFetchAttempted.contains(a) {
            autoFetchAttempted.insert(a)
            fetchIdentityFromGitHub(for: a)
        }
    }

    // MARK: - Switching

    func switchTo(_ login: String) {
        guard login != activeLogin, !busy else { return }
        busy = true
        DispatchQueue.global().async { [weak self] in
            let r = Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", login])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if r.status != 0 {
                    let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastError = msg.isEmpty ? "Failed to switch to \(login)" : msg
                    return
                }
                self.lastError = nil
                self.refresh()
                self.applyIdentityIfEnabled(for: login)
            }
        }
    }

    func handleLoginSuccess() {
        refresh()
        if let a = activeLogin {
            applyIdentityIfEnabled(for: a)
        }
    }

    func signOut(_ login: String) {
        busy = true
        DispatchQueue.global().async { [weak self] in
            let r = Shell.run(Shell.gh, ["auth", "logout", "--hostname", "github.com", "--user", login])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if r.status != 0 {
                    let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastError = msg.isEmpty ? "Failed to sign out \(login)" : msg
                }
                self.refresh()
            }
        }
    }

    // MARK: - Git identity

    func identity(for login: String) -> GitIdentity? { identities[login] }

    func setIdentity(_ login: String, name: String? = nil, email: String? = nil) {
        var id = identities[login] ?? GitIdentity()
        if let name { id.name = name }
        if let email { id.email = email }
        identities[login] = id
        persistIdentities()
    }

    private func applyIdentityIfEnabled(for login: String) {
        guard identitySyncEnabled else { return }
        if let id = identities[login], !(id.name.isEmpty && id.email.isEmpty) {
            applyGitIdentity(id)
        } else {
            fetchIdentityFromGitHub(for: login) { [weak self] in
                guard let self, self.identitySyncEnabled, let id = self.identities[login] else { return }
                self.applyGitIdentity(id)
            }
        }
    }

    func applyGitIdentity(_ id: GitIdentity) {
        DispatchQueue.global().async { [weak self] in
            if !id.name.isEmpty { Shell.run(Shell.git, ["config", "--global", "user.name", id.name]) }
            if !id.email.isEmpty { Shell.run(Shell.git, ["config", "--global", "user.email", id.email]) }
            DispatchQueue.main.async { self?.refreshGitIdentityNow() }
        }
    }

    func refreshGitIdentityNow() {
        DispatchQueue.global().async { [weak self] in
            let n = Shell.run(Shell.git, ["config", "--global", "user.name"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let e = Shell.run(Shell.git, ["config", "--global", "user.email"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self?.gitIdentityNow = GitIdentity(name: n, email: e)
            }
        }
    }

    /// Fetches name/email from the GitHub profile. Only fills fields the user
    /// hasn't set. If the login isn't the active account, gh is switched over
    /// briefly and switched back.
    func fetchIdentityFromGitHub(for login: String, completion: (() -> Void)? = nil) {
        let previous = activeLogin
        DispatchQueue.global().async { [weak self] in
            var switchedAway = false
            if previous != login {
                let s = Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", login])
                if s.status != 0 {
                    DispatchQueue.main.async {
                        self?.lastError = "Couldn't fetch profile for \(login)"
                        completion?()
                    }
                    return
                }
                switchedAway = true
            }
            let r = Shell.run(Shell.gh, ["api", "user"])
            if switchedAway, let prev = previous {
                Shell.run(Shell.gh, ["auth", "switch", "--hostname", "github.com", "--user", prev])
            }
            var name: String?
            var email: String?
            if r.status == 0,
               let data = r.out.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                name = (obj["name"] as? String) ?? (obj["login"] as? String)
                email = obj["email"] as? String
                if email == nil, let uid = obj["id"] as? Int, let lg = obj["login"] as? String {
                    // GitHub's no-reply address; valid for pushes when the real email is private.
                    email = "\(uid)+\(lg)@users.noreply.github.com"
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if r.status != 0 {
                    self.lastError = "Couldn't fetch profile for \(login)"
                } else {
                    var id = self.identities[login] ?? GitIdentity()
                    if id.name.isEmpty, let name { id.name = name }
                    if id.email.isEmpty, let email { id.email = email }
                    self.identities[login] = id
                    self.persistIdentities()
                }
                self.refresh()
                completion?()
            }
        }
    }

    // MARK: - Persistence

    private func loadIdentities() {
        guard let s = UserDefaults.standard.string(forKey: "identities"),
              let data = s.data(using: .utf8),
              let d = try? JSONDecoder().decode([String: GitIdentity].self, from: data) else { return }
        identities = d
    }

    private func persistIdentities() {
        if let data = try? JSONEncoder().encode(identities),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "identities")
        }
        // Keep folder-rule identity files in step with edited identities.
        for rule in rules {
            if let login = rule.login, let id = identities[login] {
                RulesManager.writeIdentityFile(login: login, identity: id)
            }
        }
    }
}
