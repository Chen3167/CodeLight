import SwiftUI

/// List of paired servers.
struct ServerListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            ForEach(appState.servers) { server in
                NavigationLink(value: server) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(appState.currentServer?.id == server.id && appState.isConnected ? .green : .secondary)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.headline)
                            Text(server.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if appState.currentServer?.id == server.id && appState.isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { indices in
                for index in indices {
                    appState.removeServer(appState.servers[index])
                }
            }
        }
        .navigationTitle("Servers")
        .navigationDestination(for: ServerConfig.self) { server in
            SessionListView(server: server)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    PairingView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
