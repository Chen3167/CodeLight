import Foundation

/// Auth challenge request for public key authentication.
public struct AuthRequest: Codable, Sendable {
    public let publicKey: String   // base64
    public let challenge: String   // base64
    public let signature: String   // base64

    public init(publicKey: String, challenge: String, signature: String) {
        self.publicKey = publicKey
        self.challenge = challenge
        self.signature = signature
    }
}

/// Auth response from server.
public struct AuthResponse: Codable, Sendable {
    public let success: Bool
    public let token: String?
    public let deviceId: String?
}

/// QR code pairing payload (encoded in QR).
public struct PairingQRPayload: Codable, Sendable {
    public let s: String  // server URL
    public let k: String  // temp public key (base64)
    public let n: String  // device name

    public init(serverUrl: String, tempPublicKey: String, deviceName: String) {
        self.s = serverUrl
        self.k = tempPublicKey
        self.n = deviceName
    }

    public var serverUrl: String { s }
    public var tempPublicKey: String { k }
    public var deviceName: String { n }
}

/// Session metadata (sent as encrypted blob).
public struct SessionMetadata: Codable, Sendable {
    public let path: String?         // working directory
    public let title: String?        // session title (conversation summary)
    public let projectName: String?  // project folder name (cwd basename, sent by Mac CodeIsland)
    public let model: String?        // Claude model
    public let mode: String?         // permission mode

    public init(
        path: String? = nil,
        title: String? = nil,
        projectName: String? = nil,
        model: String? = nil,
        mode: String? = nil
    ) {
        self.path = path
        self.title = title
        self.projectName = projectName
        self.model = model
        self.mode = mode
    }

    /// Project name for display: prefer the explicit `projectName`, fall back to
    /// the basename of `path`, and finally to `title`.
    public var displayProjectName: String {
        if let p = projectName, !p.isEmpty { return p }
        if let path = path, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        if let t = title, !t.isEmpty { return t }
        return "Session"
    }
}
