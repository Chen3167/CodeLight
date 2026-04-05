import SwiftUI
import AVFoundation
import CodeLightProtocol

/// QR code scanner for pairing with a CodeIsland instance.
struct PairingView: View {
    @EnvironmentObject var appState: AppState
    @State private var scannedCode: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var manualUrl = ""
    @State private var showManualEntry = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Scan QR Code")
                .font(.title)
                .fontWeight(.bold)

            Text("Open CodeIsland on your Mac\nand scan the pairing QR code")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // QR Scanner placeholder — real implementation needs camera permission
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .frame(width: 250, height: 250)
                .overlay {
                    if isProcessing {
                        ProgressView("Connecting...")
                    } else {
                        VStack {
                            Image(systemName: "camera.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Camera Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button("Enter Manually") {
                showManualEntry = true
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("CodeLight")
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet(url: $manualUrl) {
                Task { await connectManually() }
            }
        }
    }

    private func handleQRCode(_ code: String) async {
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data) else {
            errorMessage = "Invalid QR code"
            return
        }

        isProcessing = true
        let config = ServerConfig(url: payload.serverUrl, name: payload.deviceName)
        appState.addServer(config)
        await appState.connectTo(config)
        isProcessing = false
    }

    private func connectManually() async {
        guard !manualUrl.isEmpty else { return }
        let url = manualUrl.hasPrefix("http") ? manualUrl : "https://\(manualUrl)"
        isProcessing = true
        showManualEntry = false
        let config = ServerConfig(url: url, name: "Server")
        appState.addServer(config)
        await appState.connectTo(config)
        isProcessing = false
    }
}

/// Manual server URL entry sheet.
private struct ManualEntrySheet: View {
    @Binding var url: String
    let onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField("https://island.wdao.chat", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { onConnect() }
                        .disabled(url.isEmpty)
                }
            }
        }
    }
}
