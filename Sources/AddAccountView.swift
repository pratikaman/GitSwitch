import SwiftUI
import AppKit

struct AddAccountView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = LoginSession()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                BrandMark(size: 30)
                Text("GitSwitch").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Eyebrow(text: "Connect account")
            }
            Divider()
            switch session.status {
            case .idle, .starting:
                VStack(spacing: 18) {
                    EmptyState(symbol: "person.crop.circle.badge.plus", title: "A new account, right at home",
                               detail: "We’re getting a secure sign-in code from GitHub.")
                    ProgressView().controlSize(.small)
                }.padding(.vertical, 16)
            case .waiting:
                VStack(spacing: 10) {
                    Text("Let’s connect your GitHub")
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.5)
                    Text("One quick step in your browser and you’re in.")
                        .font(.system(size: 13)).foregroundStyle(GS.muted)
                }
                AuthorizationCodeView(session: session)
                HStack(alignment: .top, spacing: 12) {
                    stepNumber("1")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Paste your code on GitHub").font(.system(size: 12, weight: .semibold))
                        Text("The code is copied and your browser is ready.")
                            .font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 12) {
                    stepNumber("2")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Authorize the account you want to add").font(.system(size: 12, weight: .semibold))
                        Text("GitSwitch will take it from there.").font(.system(size: 11)).foregroundStyle(GS.muted)
                    }
                    Spacer()
                }
                Button { session.openVerificationPage() } label: {
                    Label("Continue on GitHub", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.gsPrimary)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization…").font(.system(size: 11)).foregroundStyle(GS.muted)
                }
            case .success(let login):
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46, weight: .light)).foregroundStyle(GS.accent)
                    Text("You’re connected").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("\(login) is now your active account.").font(.system(size: 13)).foregroundStyle(GS.muted)
                }.padding(.vertical, 35)
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 40, weight: .light)).foregroundStyle(GS.warning)
                    Text("Let’s try that again").font(.system(size: 24, weight: .semibold, design: .rounded))
                    ScrollView {
                        Text(message).font(.system(size: 12)).foregroundStyle(GS.muted)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                    Button("Get a new code") { session.start() }.buttonStyle(.gsPrimary)
                }.padding(.vertical, 16)
            }
            if case .success = session.status {
                EmptyView()
            } else {
                Divider()
                HStack {
                    Label("Secure sign-in with GitHub", systemImage: "lock")
                        .font(.system(size: 10)).foregroundStyle(GS.muted)
                    Spacer()
                    Button("Cancel") {
                        session.cancel(silent: true)
                        dismiss()
                    }.buttonStyle(.gsQuiet).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(28).frame(width: 460)
        .foregroundStyle(GS.ink).background(GS.canvas).tint(GS.accent)
        .onAppear { if session.status == .idle { session.start() } }
        .onDisappear { session.cancel(silent: true) }
        .onChange(of: session.status) { newStatus in
            if case .success = newStatus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        }
    }

    private func stepNumber(_ number: String) -> some View {
        Text(number).font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(GS.accent).frame(width: 24, height: 24)
            .background(GS.accentSoft, in: Circle())
    }
}

struct AuthorizationCodeView: View {
    @ObservedObject var session: LoginSession
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Eyebrow(text: "Your one-time code")
            Text(session.code ?? "····-····")
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .tracking(3).textSelection(.enabled).foregroundStyle(GS.ink)
            Button {
                guard let code = session.code else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
            } label: {
                Label(copied ? "Copied to clipboard" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
            }.buttonStyle(.gsQuiet).disabled(session.code == nil)
        }
        .padding(22).frame(maxWidth: .infinity)
        .background(GS.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(GS.accent.opacity(0.2)))
        .onChange(of: session.code) { _ in copied = false }
    }
}
