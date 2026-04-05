import SwiftUI

/// Root navigation — shows pairing if no servers, otherwise session list for current server.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            if appState.servers.isEmpty {
                PairingView()
            } else if appState.isConnected {
                SessionListView(server: appState.currentServer ?? appState.servers[0])
            } else {
                VStack(spacing: 16) {
                    ProgressView("Connecting to server...")
                    Button("Reset") {
                        appState.servers.removeAll()
                        UserDefaults.standard.removeObject(forKey: "servers")
                        appState.disconnect()
                    }
                    .foregroundStyle(.red)
                }
                .task {
                    if let server = appState.currentServer ?? appState.servers.first {
                        await appState.connectTo(server)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
