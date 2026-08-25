import Foundation
import AppKit

/// Drives `gh auth login --web`: surfaces the one-time device code, opens the
/// browser, and reports when GitHub confirms the login.
final class LoginSession: ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case waiting
        case success(String)
        case failed(String)
    }

    @Published var status: Status = .idle
    @Published var code: String?

    /// Called on success. Defaults to the add-account behavior; device flows
    /// used for other purposes (e.g. scope refresh) override this.
    var onSuccess: (() -> Void)? = { AppState.shared.handleLoginSuccess() }

    private var process: Process?
    private let bufferQueue = DispatchQueue(label: "gitswitch.login-buffer")
    private var buffer = ""
    private var foundCode = false
    private var cancelled = false
    private var verificationURL = "https://github.com/login/device"

    func start(args: [String] = ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"]) {
        cancel(silent: true)
        cancelled = false
        buffer = ""
        foundCode = false
        code = nil
        status = .starting

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Shell.gh)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["NO_COLOR"] = "1"
        p.environment = env
        p.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        for handle in [out.fileHandleForReading, err.fileHandleForReading] {
            handle.readabilityHandler = { [weak self] fh in
                let data = fh.availableData
                guard let self, !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.bufferQueue.async {
                    self.buffer += text
                    self.scan()
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            self.bufferQueue.async {
                let output = self.buffer
                DispatchQueue.main.async {
                    if self.cancelled { return }
                    if proc.terminationStatus == 0 {
                        let login = Self.match(#"Logged in as (\S+)"#, in: output) ?? "your account"
                        self.status = .success(login)
                        self.onSuccess?()
                    } else {
                        let tail = output
                            .split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            .suffix(5)
                            .joined(separator: "\n")
                        self.status = .failed(tail.isEmpty ? "gh auth login failed." : tail)
                    }
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            status = .failed("Couldn't launch gh: \(error.localizedDescription)")
        }
    }

    // Runs on bufferQueue.
    private func scan() {
        guard !foundCode else { return }
        guard let c = Self.match(#"([A-Z0-9]{4}-[A-Z0-9]{4})"#, in: buffer) else { return }
        foundCode = true
        let url = Self.match(#"(https://\S*github\S*/login/device\S*)"#, in: buffer) ?? verificationURL
        DispatchQueue.main.async {
            self.code = c
            self.verificationURL = url
            self.status = .waiting
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(c, forType: .string)
            self.openVerificationPage()
        }
    }

    func openVerificationPage() {
        if let u = URL(string: verificationURL) {
            NSWorkspace.shared.open(u)
        }
    }

    func cancel(silent: Bool = false) {
        cancelled = true
        process?.terminate()
        process = nil
        if !silent { status = .idle }
    }

    static func match(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        let idx = m.numberOfRanges > 1 ? 1 : 0
        guard let r = Range(m.range(at: idx), in: text) else { return nil }
        return String(text[r])
    }
}
