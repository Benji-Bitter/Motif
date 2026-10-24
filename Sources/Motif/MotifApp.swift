import SwiftUI
import MotifCore

@main
struct MotifApp: App {
    @StateObject private var env = MotifApp.makeEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .preferredColorScheme(env.appearance.scheme)
                .frame(minWidth: 980, minHeight: 640)
                .task { await env.start() }
                .alert(item: $env.alert) { content in
                    Alert(title: Text(content.title), message: Text(content.message))
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            MotifCommands()
        }
    }

    private static func makeEnvironment() -> AppEnvironment {
        do {
            return try AppEnvironment()
        } catch {
            fatalError("Could not open the Motif library: \(error.localizedDescription)")
        }
    }
}

/// Native menu commands — navigation shortcuts, import, export, apply.
struct MotifCommands: Commands {
    @FocusedObject private var env: AppEnvironment?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Motif") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "Motif",
                    .applicationVersion: "0.1.0",
                    .version: "1"
                ])
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Import Artwork…") { env?.selection = .wallet }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Import Video…") { env?.selection = .wallpaper }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button("Overview") { env?.selection = .overview }.keyboardShortcut("1")
            Button("Wallet Studio") { env?.selection = .wallet }.keyboardShortcut("2")
            Button("Wallpaper Studio") { env?.selection = .wallpaper }.keyboardShortcut("3")
            Button("Library") { env?.selection = .library }.keyboardShortcut("4")
            Button("Devices") { env?.selection = .devices }.keyboardShortcut("5")
            Button("Settings") { env?.selection = .settings }.keyboardShortcut("6")
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $env.selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Motif")
            .frame(minWidth: 200)
        } detail: {
            switch env.selection {
            case .overview: OverviewView()
            case .wallet: WalletStudioView()
            case .wallpaper: WallpaperStudioView()
            case .library: LibraryView()
            case .devices: DevicesView()
            case .settings: SettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    env.showingApply = true
                } label: {
                    Label("Apply…", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Open the apply workflow (⌘⇧A)")
            }
        }
        .sheet(isPresented: $env.showingApply) {
            ApplySheet()
        }
        .focusedObject(env)
    }
}
