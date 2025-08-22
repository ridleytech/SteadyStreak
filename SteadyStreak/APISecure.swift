//
//  APISecure.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//
import CryptoKit // SHA256
import DeviceCheck // DCAppAttestService
import Foundation

// MARK: - Public API

@available(iOS 14.0, *)
public final class AppAttestClient {
    public struct Config: Sendable {
        /// Base URL of your API (e.g., https://xxxx.execute-api.us-west-2.amazonaws.com/prod)
        public let apiBaseURL: URL
        /// Path for nonce endpoint (default: /nonce)
        public var noncePath: String = "/nonce"
        /// Path for register endpoint (default: /register)
        public var registerPath: String = "/register"
        /// Key used to persist keyId locally (override if you like)
        public var keychainKeyIdKey: String = "AppAttest.keyId"

        public init(apiBaseURL: URL) {
            self.apiBaseURL = apiBaseURL
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case unsupported
        case missingKeyId
        case badHTTPStatus(code: Int)
        case badServerResponse(String)
        case invalidNonce
        case noAttestation
        case noAssertion
        case noKeyIdGenerated

        public var errorDescription: String? {
            switch self {
            case .unsupported: return "App Attest is not supported on this device."
            case .missingKeyId: return "App Attest keyId not found. Call registerIfNeeded() first."
            case .badHTTPStatus(let code): return "Server returned HTTP \(code)."
            case .badServerResponse(let w): return "Invalid server response: \(w)"
            case .invalidNonce: return "Nonce missing or invalid."
            case .noAttestation: return "Failed to create attestation object."
            case .noAssertion: return "Failed to create assertion."
            case .noKeyIdGenerated: return "Failed to generate App Attest keyId."
            }
        }
    }

    public static let shared = AppAttestClient()
    public var config: Config!

    /// Configure once at app start.
    public func configure(_ config: Config) {
        self.config = config
        keyIdStorageKey = config.keychainKeyIdKey
    }

    /// One-time registration (per install). Safe to call repeatedly; it will no-op after success.
    public func registerIfNeeded() async throws {
        guard DCAppAttestService.shared.isSupported else { throw Error.unsupported }
        guard let config else { preconditionFailure("AppAttestClient not configured. Call configure(_:) first.") }

        if keyId != nil { return } // already registered

        // 1) Generate key on device
        let keyId = try await generateKey()
        print("Generated keyId: \(keyId) -- registerIfNeeded")

        // 2) Get attestation nonce (server returns base64url string under "nonce")
        let nonceBytes = try await fetchNonceBytes(purpose: "attestation",
                                                   baseURL: config.apiBaseURL,
                                                   path: config.noncePath)
        // Log in base64 for readability (bytes are source of truth)
        print("Fetched nonceB64: \(nonceBytes.base64EncodedString()) -- registerIfNeeded")

        // 3) Attest the key using the **bytes** from the server
        let clientDataHash = sha256(nonceBytes)
        let attObj = try await attestKey(keyId: keyId, clientDataHash: clientDataHash)
        print("Attestation object size: \(attObj.count) bytes -- registerIfNeeded")

        // 4) Send to server:
        //    - "nonce" as a **string** the server can decode (base64url is fine).
        //    - "clientDataHashB64" as base64 of the 32-byte hash we gave DeviceCheck.
        try await postAttestation(
            baseURL: config.apiBaseURL,
            path: config.registerPath,
            keyId: keyId,
            attestationObject: attObj,
            clientDataHash: clientDataHash,
            publicKey: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0C...\n-----END PUBLIC KEY-----",
            nonceB64Url: nonceBytes.base64URLEncodedString() // send base64url form
        )

        // 5) Persist keyId locally
        setKeyId(keyId)
        print("App Attest registration complete. KeyId saved.")
    }

    /// Produces the headers required by your protected API for the given request.
    ///
    /// - Parameters:
    ///   - method: "GET", "POST", etc.
    ///   - path: request path such as "/protected" (must match what the server reconstructs)
    ///   - body: request body bytes (pass `nil` for GET/HEAD)
    /// - Returns: headers dictionary to attach to your URLRequest
    public func signedHeaders(method: String, path: String, body: Data?) async throws -> [String: String] {
        guard let config else { preconditionFailure("AppAttestClient not configured. Call configure(_:) first.") }
        guard let keyId = keyId else { throw Error.missingKeyId }

        let ts = Int(Date().timeIntervalSince1970)
        let nonceBytes = try await fetchNonceBytes(purpose: "request",
                                                   baseURL: config.apiBaseURL,
                                                   path: config.noncePath)
        let bodyHash = sha256(body ?? Data())

        // payload = method|path|timestamp|bodySHA256|nonce   (all raw bytes)
        var payload = Data()
        payload.append(method.uppercased().data(using: .utf8)!)
        payload.append(0x7C) // '|'
        payload.append(path.data(using: .utf8)!)
        payload.append(0x7C)
        payload.append("\(ts)".data(using: .utf8)!)
        payload.append(0x7C)
        payload.append(bodyHash) // raw 32 bytes
        payload.append(0x7C)
        payload.append(nonceBytes) // raw 32 bytes

        let clientDataHash = sha256(payload)
        let assertion = try await generateAssertion(keyId: keyId, clientDataHash: clientDataHash)

        // Provide both nonce (base64url) and a body hash header the authorizer can use
        var headers: [String: String] = [
            "X-AppAttest-KeyId": keyId,
            "X-AppAttest-Assertion": assertion.base64EncodedString(),
            "X-Req-Nonce": nonceBytes.base64URLEncodedString(), // server will base64url-decode
            "X-Req-Timestamp": "\(ts)",
            "X-Body-SHA256": bodyHash.base64EncodedString() // optional but recommended
        ]
        return headers
    }

    /// Clears the local registration (forces new key & re-attestation next time).
    public func resetLocalRegistration() {
        UserDefaults.standard.removeObject(forKey: keyIdStorageKey)
    }

    // MARK: - Internals

    private let service = DCAppAttestService.shared
    private var keyIdStorageKey = "AppAttest.keyId"

    private var keyId: String? {
        UserDefaults.standard.string(forKey: keyIdStorageKey)
    }

    private func setKeyId(_ id: String) {
        UserDefaults.standard.set(id, forKey: keyIdStorageKey)
    }

    // MARK: DeviceCheck (App Attest) wrappers

    private func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            service.generateKey { keyId, error in
                if let e = error { cont.resume(throwing: e); return }
                guard let keyId else { cont.resume(throwing: Error.noKeyIdGenerated); return }
                cont.resume(returning: keyId)
            }
        }
    }

    private func attestKey(keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            service.attestKey(keyId, clientDataHash: clientDataHash) { attestationObject, error in
                if let e = error { cont.resume(throwing: e); return }
                guard let attestationObject else { cont.resume(throwing: Error.noAttestation); return }
                cont.resume(returning: attestationObject)
            }
        }
    }

    private func generateAssertion(keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
                if let e = error { cont.resume(throwing: e); return }
                guard let assertion else { cont.resume(throwing: Error.noAssertion); return }
                cont.resume(returning: assertion)
            }
        }
    }

    // MARK: Networking

    /// Fetches a fresh nonce and returns the **raw 32 bytes**.
    private func fetchNonceBytes(purpose: String, baseURL: URL, path: String) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "purpose", value: purpose)]

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse else { throw Error.badServerResponse("no HTTP response") }
        guard http.statusCode == 200 else { throw Error.badHTTPStatus(code: http.statusCode) }

        /// Server returns: { nonce: <base64url>, expiresIn: 120 }  (or may also include nonceB64)
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let nonceStr = (obj["nonceB64"] as? String) ?? (obj["nonce"] as? String), // prefer nonceB64 if present
            let nonce = nonceStr.base64URLOrBase64DecodedData(),
            nonce.count >= 32
        else {
            throw Error.invalidNonce
        }
        return nonce
    }

    private func postAttestation(
        baseURL: URL,
        path: String,
        keyId: String,
        attestationObject: Data,
        clientDataHash: Data,
        publicKey: String,
        nonceB64Url: String
    ) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "keyId": keyId,
            "attestationB64": attestationObject.base64EncodedString(), // typical field name is "attestation"
            "clientDataHashB64": clientDataHash.base64EncodedString(),
            "publicKeyPem": publicKey,
            "challenge": nonceB64Url // send the same base64url string we received (server will decode)
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw Error.badServerResponse("no HTTP response")
        }
        print("POST \(path) response status: \(http.statusCode) -- postAttestation")
        guard http.statusCode == 200 else { throw Error.badHTTPStatus(code: http.statusCode) }
    }
}

// MARK: - Utilities

@inline(__always)
private func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
}

private extension Data {
    func base64URLEncodedString() -> String {
        let b64 = base64EncodedString()
        return b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    /// Decodes either **base64url** or **standard base64** into Data.
    func base64URLOrBase64DecodedData() -> Data? {
        // If it already decodes as standard base64, we’re done.
        if let d = Data(base64Encoded: self) { return d }
        // Convert URL-safe -> standard and pad
        var s = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - (s.count % 4)) % 4
        if pad > 0 { s.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: s)
    }

    /// For completeness (kept for compatibility)
    func base64URLDecodedData() -> Data? {
        var s = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (s.count % 4)
        if pad < 4 { s.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: s)
    }
}
