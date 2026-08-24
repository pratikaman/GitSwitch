import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = LoginSession()

    var body: some View {
        VStack(spacing: 16) {
            switch session.status {
            case .idle, .starting:
                ProgressView("Starting GitHub login…")
                    .padding(.vertical, 20)

            case .waiting:
                Text("Enter this code on GitHub")
                    .font(.headline)
                Text(session.code ?? "…")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Text("The code is on your clipboard and the GitHub\ndevice page was opened in your browser.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Reopen github.com/login/device") {
                    session.openVerificationPage()
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to authorize…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .success(let login):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Signed in as \(login)")
                    .font(.headline)
                Text("This account is now active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .failed(let msg):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Login didn't complete")
                    .font(.headline)
                ScrollView {
                    Text(msg)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                Button("Try Again") { session.start() }
            }

            if case .success = session.status {
                EmptyView()
            } else {
                Button("Cancel") {
                    session.cancel(silent: true)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            if session.status == .idle { session.start() }
        }
        .onDisappear { session.cancel(silent: true) }
        .onChange(of: session.status) { newStatus in
            if case .success = newStatus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        }
    }
}
