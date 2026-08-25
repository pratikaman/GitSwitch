import SwiftUI
import AppKit
import ServiceManagement

enum WindowID {
    static let addAccount = "add-account"
    static let manage = "manage-accounts"
}

@main
struct GitSwitchApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)

        Window("Add GitHub Account", id: WindowID.addAccount) {
            AddAccountView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("GitHub Accounts", id: WindowID.manage) {
            ManageView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @AppStorage("showNameInMenuBar") private var showName = true

    private static let templateIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "tiff"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    private var icon: Image {
        if let ns = Self.templateIcon {
            return Image(nsImage: ns)
        }
        return Image(systemName: "person.crop.circle")
    }

    var body: some View {
        if showName, let login = state.activeLogin {
            HStack(spacing: 4) {
                icon.renderingMode(.template)
                Text(login)
            }
        } else {
            icon.renderingMode(.template)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("syncGitIdentity") private var syncIdentity = true
    @AppStorage("showNameInMenuBar") private var showName = true

    var body: some View {
        Group {
            if let active = state.activeLogin {
                Text("Active: \(active)")
                if let email = state.identity(for: active)?.email, !email.isEmpty {
                    Text("Committing as \(email)")
                }
            } else {
                Text("No active GitHub account")
            }
            Divider()
            ForEach(state.accounts, id: \.self) { login in
                Toggle(isOn: Binding(
                    get: { state.activeLogin == login },
                    set: { _ in state.switchTo(login) }
                )) {
                    Text(login)
                }
            }
            Divider()
            Button("Add GitHub Account…") { open(WindowID.addAccount) }
            Button("Manage Accounts…") { open(WindowID.manage) }
            Divider()
            Toggle("Sync Git Identity on Switch", isOn: $syncIdentity)
            Toggle("Show Account Name in Menu Bar", isOn: $showName)
            Toggle("Launch at Login", isOn: launchAtLogin)
            if let err = state.lastError {
                Divider()
                Text(err).lineLimit(3)
            }
            Divider()
            Button("Quit GitSwitch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { state.refresh() }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    AppState.shared.lastError = "Launch at login: \(error.localizedDescription)"
                }
            }
        )
    }
}
