import SwiftUI

struct ManageView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if state.accounts.isEmpty {
                        Text("No GitHub accounts on this Mac yet.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                    ForEach(state.accounts, id: \.self) { login in
                        AccountCard(login: login)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    if let g = state.gitIdentityNow, !g.email.isEmpty {
                        Text("git commits as: \(g.name) <\(g.email)>")
                            .font(.caption)
                    }
                    Text("Switching changes the account git push uses everywhere. Repos with a local user.email override are not affected.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Account…") {
                    openWindow(id: WindowID.addAccount)
                }
            }
            .padding(12)
        }
        .frame(width: 500, height: 440)
        .onAppear {
            state.refresh()
            state.refreshGitIdentityNow()
        }
    }
}

struct AccountCard: View {
    @EnvironmentObject var state: AppState
    let login: String
    @State private var confirmSignOut = false

    private var isActive: Bool { state.activeLogin == login }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.green : Color.secondary)
                Text(login)
                    .font(.headline)
                if isActive {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                Spacer()
                if !isActive {
                    Button("Make Active") { state.switchTo(login) }
                        .disabled(state.busy)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Commit name").font(.caption).foregroundStyle(.secondary)
                    TextField("Name used for git commits", text: nameBinding)
                }
                GridRow {
                    Text("Commit email").font(.caption).foregroundStyle(.secondary)
                    TextField("Email used for git commits", text: emailBinding)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Fetch from GitHub") {
                    state.fetchIdentityFromGitHub(for: login)
                }
                .help("Fills empty fields from the GitHub profile. If the profile email is private, GitHub's no-reply address is used.")
                if isActive {
                    Button("Apply to git now") {
                        if let id = state.identity(for: login) {
                            state.applyGitIdentity(id)
                        }
                    }
                    .help("Writes these values to the global git config immediately.")
                }
                Spacer()
                Button("Sign Out…", role: .destructive) { confirmSignOut = true }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.5) : Color.gray.opacity(0.25))
        )
        .alert("Sign out of \(login)?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { state.signOut(login) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account's token from the gh CLI on this Mac. You can add it back any time.")
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { state.identity(for: login)?.name ?? "" },
            set: { state.setIdentity(login, name: $0) }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { state.identity(for: login)?.email ?? "" },
            set: { state.setIdentity(login, email: $0) }
        )
    }
}
