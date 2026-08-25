import Foundation

// MARK: - Folder rules (git includeIf)

struct FolderRule: Identifiable, Equatable {
    let dir: String          // absolute path with trailing slash
    let identityFile: String
    var id: String { dir }

    var login: String? {
        let base = (identityFile as NSString).lastPathComponent
        guard base.hasPrefix("identity-"), base.hasSuffix(".gitconfig") else { return nil }
        return String(base.dropFirst("identity-".count).dropLast(".gitconfig".count))
    }
}

enum RulesManager {
    static let configDir = NSString(string: "~/.config/gitswitch").expandingTildeInPath

    static func identityFilePath(for login: String) -> String {
        configDir + "/identity-\(login).gitconfig"
    }

    static func writeIdentityFile(login: String, identity: GitIdentity) {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        var s = "# Managed by GitSwitch — commit identity for \(login)\n[user]\n"
        if !identity.name.isEmpty { s += "\tname = \(identity.name)\n" }
        if !identity.email.isEmpty { s += "\temail = \(identity.email)\n" }
        try? s.write(toFile: identityFilePath(for: login), atomically: true, encoding: .utf8)
    }

    /// Only returns rules pointing at GitSwitch-managed identity files.
    static func loadRules() -> [FolderRule] {
        let r = Shell.run(Shell.git, ["config", "--global", "-z", "--get-regexp", #"^includeif\."#])
        guard r.status == 0 else { return [] }
        var rules: [FolderRule] = []
        for record in r.out.split(separator: "\0") {
            let parts = record.split(separator: "\n", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0], value = parts[1]
            guard key.lowercased().hasPrefix("includeif.gitdir:"),
                  key.hasSuffix(".path"),
                  value.contains("/.config/gitswitch/identity-") else { continue }
            let dir = String(key.dropFirst("includeif.gitdir:".count).dropLast(".path".count))
            rules.append(FolderRule(dir: dir, identityFile: value))
        }
        return rules.sorted { $0.dir < $1.dir }
    }

    static func addRule(dir rawDir: String, login: String, identity: GitIdentity) -> String? {
        var dir = rawDir
        if !dir.hasSuffix("/") { dir += "/" }
        writeIdentityFile(login: login, identity: identity)
        let r = Shell.run(Shell.git, ["config", "--global", "includeIf.gitdir:\(dir).path", identityFilePath(for: login)])
        if r.status != 0 {
            let e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "git config failed" : e
        }
        return nil
    }

    static func removeRule(_ rule: FolderRule) {
        Shell.run(Shell.git, ["config", "--global", "--remove-section", "includeIf.gitdir:\(rule.dir)"])
    }
}

// MARK: - Push guard (global pre-push hook)

enum GuardManager {
    static let hooksDir = RulesManager.configDir + "/hooks"
    static var hookPath: String { hooksDir + "/pre-push" }
    static let mapPath = RulesManager.configDir + "/push-guard-map"

    static func currentHooksPath() -> String? {
        let r = Shell.run(Shell.git, ["config", "--global", "core.hooksPath"])
        let v = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// A hooksPath set by something other than GitSwitch, or nil.
    static func foreignHooksPath() -> String? {
        guard let hp = currentHooksPath() else { return nil }
        return NSString(string: hp).expandingTildeInPath == hooksDir ? nil : hp
    }

    static func isEnabled() -> Bool {
        guard let hp = currentHooksPath() else { return false }
        return NSString(string: hp).expandingTildeInPath == hooksDir
            && FileManager.default.isExecutableFile(atPath: hookPath)
    }

    static func enable() -> String? {
        do {
            try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
            try hookScript.write(toFile: hookPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        } catch { return error.localizedDescription }
        let r = Shell.run(Shell.git, ["config", "--global", "core.hooksPath", hooksDir])
        if r.status != 0 {
            let e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "git config failed" : e
        }
        return nil
    }

    static func disable() {
        if foreignHooksPath() == nil {
            Shell.run(Shell.git, ["config", "--global", "--unset", "core.hooksPath"])
        }
    }

    // Mappings: repo owner (org) -> account login, stored as "owner=login" lines.
    static func loadMappings() -> [(owner: String, login: String)] {
        guard let text = try? String(contentsOfFile: mapPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            let parts = t.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
    }

    static func saveMappings(_ mappings: [(owner: String, login: String)]) {
        try? FileManager.default.createDirectory(atPath: RulesManager.configDir, withIntermediateDirectories: true)
        let body = "# Managed by GitSwitch — repo owner to account mapping\n"
            + mappings.map { "\($0.owner)=\($0.login)" }.joined(separator: "\n") + "\n"
        try? body.write(toFile: mapPath, atomically: true, encoding: .utf8)
    }

    /// The account expected for a repo owner: explicit mapping first, then an
    /// owner that is itself one of the signed-in accounts.
    static func expectedAccount(forOwner owner: String, accounts: [String]) -> String? {
        if let m = loadMappings().first(where: { $0.owner.lowercased() == owner.lowercased() }) {
            return m.login
        }
        return accounts.first { $0.lowercased() == owner.lowercased() }
    }

    static let hookScript = #"""
#!/bin/sh
# Managed by GitSwitch — blocks pushes to GitHub when the active gh account
# doesn't match the repository owner. Bypass once with: GITSWITCH_SKIP=1 git push
# Chains to the repository's own pre-push hook if one exists.

run_local_hook() {
  gitdir=$(git rev-parse --git-dir 2>/dev/null)
  local_hook="$gitdir/hooks/pre-push"
  if [ -n "$gitdir" ] && [ -x "$local_hook" ]; then
    exec "$local_hook" "$@"
  fi
  exit 0
}

[ -n "$GITSWITCH_SKIP" ] && run_local_hook "$@"

url="$2"
case "$url" in
  *github.com*) ;;
  *) run_local_hook "$@" ;;
esac

owner=$(printf '%s' "$url" | sed -E 's#.*github\.com[:/]+([^/]+)/.*#\1#')
[ -z "$owner" ] || [ "$owner" = "$url" ] && run_local_hook "$@"

hosts="$HOME/.config/gh/hosts.yml"
[ -f "$hosts" ] || run_local_hook "$@"
active=$(awk '$1=="user:"{print $2; exit}' "$hosts")
[ -z "$active" ] && run_local_hook "$@"

expected=""
map="$HOME/.config/gitswitch/push-guard-map"
if [ -f "$map" ]; then
  expected=$(awk -F= -v o="$owner" '/^[^#]/ && tolower($1)==tolower(o){print $2; exit}' "$map")
fi
if [ -z "$expected" ]; then
  if awk -v o="$owner" '
      /^    users:/ {inu=1; next}
      inu && /^        [^ ]+: *$/ {u=$1; sub(/:$/,"",u); if (tolower(u)==tolower(o)) found=1}
      inu && /^    [^ ]/ {inu=0}
      END {exit !found}' "$hosts"; then
    expected="$owner"
  fi
fi

if [ -n "$expected" ] && [ "$expected" != "$active" ]; then
  echo "" >&2
  echo "GitSwitch: push blocked." >&2
  echo "  Active GitHub account:  $active" >&2
  echo "  This repo belongs to:   $owner (expects account '$expected')" >&2
  echo "  Fix:    switch accounts in the GitSwitch menu bar app," >&2
  echo "          or run: gh auth switch --user $expected" >&2
  echo "  Bypass: GITSWITCH_SKIP=1 git push" >&2
  exit 1
fi

run_local_hook "$@"
"""#
}

// MARK: - SSH

struct SSHAlias: Identifiable {
    let host: String
    let identityFile: String?
    var id: String { host }
}

enum SSHManager {
    static func githubAliases() -> [SSHAlias] {
        let path = NSString(string: "~/.ssh/config").expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var aliases: [SSHAlias] = []
        var host: String?
        var hostname: String?
        var identity: String?
        func flush() {
            if let h = host, (hostname ?? h).lowercased().contains("github.com") {
                aliases.append(SSHAlias(host: h, identityFile: identity))
            }
        }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "host":
                flush()
                host = parts[1].split(separator: " ").first.map(String.init)
                hostname = nil
                identity = nil
            case "hostname": hostname = parts[1]
            case "identityfile": identity = parts[1]
            default: break
            }
        }
        flush()
        return aliases
    }

    /// Returns the GitHub login this alias authenticates as, or nil.
    static func testAlias(_ host: String) -> String? {
        let r = Shell.run("/usr/bin/ssh", [
            "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=accept-new", "git@\(host)",
        ])
        return LoginSession.match(#"Hi ([A-Za-z0-9-]+)!"#, in: r.out + r.err)
    }

    static func publicKeys() -> [String] {
        let dir = NSString(string: "~/.ssh").expandingTildeInPath
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items.filter { $0.hasSuffix(".pub") }.sorted().map { dir + "/" + $0 }
    }
}

// MARK: - GitHub URL parsing

enum GitHubURL {
    /// Parses https, ssh, and "owner/repo" forms. Returns (owner, repo, sshHost).
    static func parse(_ input: String) -> (owner: String, repo: String, sshHost: String?)? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = matchGroups(#"^(?:https?://)?(?:www\.)?github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?/?$"#, in: s) {
            return (m[0], m[1], nil)
        }
        if let m = matchGroups(#"^(?:ssh://)?git@([^:/\s]+)[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$"#, in: s) {
            return (m[1], m[2], m[0])
        }
        if let m = matchGroups(#"^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+?)(?:\.git)?$"#, in: s) {
            return (m[0], m[1], nil)
        }
        return nil
    }

    static func matchGroups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            groups.append(String(text[r]))
        }
        return groups
    }
}
