import SwiftUI

/// Root navigation — shows pairing if no servers, otherwise server list.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            if appState.servers.isEmpty {
                PairingView()
            } else {
                ServerListView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
