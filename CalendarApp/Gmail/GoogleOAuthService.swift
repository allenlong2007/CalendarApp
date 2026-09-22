import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

enum GmailError: LocalizedError {
    case notConfigured
    case badRedirect
    case cancelled
    case noCode
    case tokenExchangeFailed
    case notSignedIn
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Gmail import needs a Google OAuth client ID configured first."
        case .badRedirect: return "The OAuth redirect URI is misconfigured."
        case .cancelled: return "Sign-in was cancelled."
        case .noCode: return "Google didn't return an authorization code."
        case .tokenExchangeFailed: return "Couldn't complete sign-in with Google."
        case .notSignedIn: return "Not signed in to Gmail."
        case .requestFailed: return "The Gmail request failed."
        }
    }
}

/// OAuth 2.0 Authorization Code + PKCE flow for Gmail's read-only scope --
/// the standard flow for a native/public client (no client secret). The
/// refresh token is the only long-lived credential and lives in the
/// Keychain; the access token is kept in memory only.
@Observable
@MainActor
final class GoogleOAuthService: NSObject {
    private(set) var isSignedIn: Bool = false
    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var webAuthSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        isSignedIn = KeychainTokenStore.load() != nil
    }

    func signIn() async throws {
        guard GoogleOAuthConfig.isConfigured else { throw GmailError.notConfigured }
        guard let scheme = URL(string: GoogleOAuthConfig.redirectURI)?.scheme else {
            throw GmailError.badRedirect
        }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let authURL = components.url else { throw GmailError.badRedirect }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? GmailError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GmailError.noCode
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    func signOut() {
        KeychainTokenStore.delete()
        accessToken = nil
        accessTokenExpiry = nil
        isSignedIn = false
    }

    /// Returns a valid access token, transparently refreshing via the stored
    /// refresh token when the in-memory one has expired (or after a relaunch).
    func validAccessToken() async throws -> String {
        if let accessToken, let expiry = accessTokenExpiry, expiry > .now.addingTimeInterval(60) {
            return accessToken
        }
        guard let refreshToken = KeychainTokenStore.load() else { throw GmailError.notSignedIn }
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        let params = [
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI,
        ]
        let token = try await requestToken(params: params)
        accessToken = token.accessToken
        accessTokenExpiry = Date.now.addingTimeInterval(TimeInterval(token.expiresIn))
        if let refreshToken = token.refreshToken {
            KeychainTokenStore.save(refreshToken)
        }
        isSignedIn = true
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        let params = [
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        do {
            let token = try await requestToken(params: params)
            accessToken = token.accessToken
            accessTokenExpiry = Date.now.addingTimeInterval(TimeInterval(token.expiresIn))
            isSignedIn = true
            return token.accessToken
        } catch {
            isSignedIn = false
            throw error
        }
    }

    private func requestToken(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GmailError.tokenExchangeFailed
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        return params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64URLEncodedString()
    }
}

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        // Last-resort fallback (should never be hit -- a key window always
        // exists by the time sign-in can be triggered from the UI).
        guard let scene = scenes.first else {
            preconditionFailure("No window scene available to present Google sign-in.")
        }
        return UIWindow(windowScene: scene)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
