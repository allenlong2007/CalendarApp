import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OSLog
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

enum GoogleOAuthCallback {
    static func matchesRedirect(_ url: URL) -> Bool {
        guard let expected = URL(string: GoogleOAuthConfig.redirectURI) else { return false }
        return url.scheme == expected.scheme && url.host == expected.host && url.path == expected.path
            && url.user == nil && url.password == nil && url.port == nil
    }

    static func code(from url: URL, expectedState: String) throws -> String {
        guard matchesRedirect(url), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState else { throw GmailError.badRedirect }
        if items.contains(where: { $0.name == "error" }) { throw GmailError.cancelled }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw GmailError.noCode }
        return code
    }
}

/// OAuth 2.0 Authorization Code + PKCE flow for Gmail's read-only scope --
/// the standard flow for a native/public client (no client secret). The
/// refresh token is the only long-lived credential and lives in the
/// Keychain; the access token is kept in memory only.
@Observable
@MainActor
final class GoogleOAuthService: NSObject {
    static let shared = GoogleOAuthService()
    private static let logger = Logger(subsystem: "com.footsoregnu3115.calendarapp", category: "GmailOAuth")
    var isSignedIn: Bool { !accounts.isEmpty }
    private(set) var accounts: [String] = []
    private var credentials = GmailAccountCredentials(storedValue: nil)
    private var accessTokens: [String: (value: String, expiry: Date)] = [:]
    private var webAuthSession: ASWebAuthenticationSession?
    private var browserContinuation: CheckedContinuation<URL, Error>?
    private var browserState: String?
    private(set) var isAuthenticating = false
    private var storageError: Error?
    weak var presentationWindow: UIWindow?

    private override init() {
        super.init()
        do { credentials = GmailAccountCredentials(storedValue: try KeychainTokenStore.load()) }
        catch { storageError = error }
        accounts = credentials.tokens.keys.sorted()
    }

    func signIn() async throws {
        if let storageError { throw storageError }
        guard !isAuthenticating else { throw GmailError.requestFailed }
        guard GoogleOAuthConfig.isConfigured else { throw GmailError.notConfigured }
        guard let scheme = URL(string: GoogleOAuthConfig.redirectURI)?.scheme else {
            throw GmailError.badRedirect
        }

        let verifier = Self.randomURLSafeString(length: 64)
        let state = Self.randomURLSafeString(length: 32)
        let challenge = Self.codeChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
        ]
        guard let authURL = components.url else { throw GmailError.badRedirect }

        isAuthenticating = true
        defer {
            webAuthSession = nil
            browserContinuation = nil
            browserState = nil
            isAuthenticating = false
        }
        #if targetEnvironment(macCatalyst)
        // Use the normal browser on Mac so existing Google sessions are
        // available. SwiftUI forwards the registered custom-scheme callback.
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            browserContinuation = continuation
            browserState = state
            UIApplication.shared.open(authURL, options: [:]) { opened in
                Task { @MainActor in
                    if !opened { self.finishBrowserSignIn(.failure(GmailError.requestFailed)) }
                }
            }
        }
        #else
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    let failure = error as NSError?
                    Self.logger.error("Google authorization ended with code: \(failure?.code ?? -1)")
                    continuation.resume(throwing: error ?? GmailError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            let started = session.start()
            Self.logger.info("Google authorization session started: \(started)")
            if !started { continuation.resume(throwing: GmailError.cancelled) }
        }
        #endif

        let code = try GoogleOAuthCallback.code(from: callbackURL, expectedState: state)
        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    func signOut(account: String? = nil) throws {
        var updated = credentials
        if let account {
            updated.tokens.removeValue(forKey: account)
        } else {
            updated.tokens = [:]
        }
        try persistAccounts(updated)
        if let account { accessTokens.removeValue(forKey: account) }
        else { accessTokens = [:] }
    }

    func cancelSignIn() {
        webAuthSession?.cancel()
        finishBrowserSignIn(.failure(GmailError.cancelled))
    }

    func handleCallback(_ url: URL) {
        guard GoogleOAuthCallback.matchesRedirect(url), let browserState,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        // Unsolicited or mismatched callbacks must not consume a pending login.
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == browserState else { return }
        finishBrowserSignIn(.success(url))
    }

    private func finishBrowserSignIn(_ result: Result<URL, Error>) {
        guard let continuation = browserContinuation else { return }
        browserContinuation = nil
        continuation.resume(with: result)
    }

    /// Returns a valid access token, transparently refreshing via the stored
    /// refresh token when the in-memory one has expired (or after a relaunch).
    func validAccessToken(account: String? = nil) async throws -> String {
        guard let account = account ?? accounts.first else { throw GmailError.notSignedIn }
        if let cached = accessTokens[account], cached.expiry > .now.addingTimeInterval(60) {
            return cached.value
        }
        guard let refreshToken = credentials.tokens[account] else { throw GmailError.notSignedIn }
        return try await refreshAccessToken(refreshToken: refreshToken, account: account)
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
        let email = try await GmailAPIClient.accountEmail(accessToken: token.accessToken)
        guard let refreshToken = token.refreshToken ?? credentials.tokens[email] else { throw GmailError.tokenExchangeFailed }
        var updated = credentials
        updated.tokens[email] = refreshToken
        try persistAccounts(updated)
        accessTokens[email] = (token.accessToken, .now.addingTimeInterval(TimeInterval(token.expiresIn)))
    }

    private func refreshAccessToken(refreshToken: String, account: String) async throws -> String {
        let params = [
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        let token = try await requestToken(params: params)
        // A disconnect during the network request must not restore an account.
        guard credentials.tokens[account] == refreshToken else { throw GmailError.notSignedIn }
        var email = account
        if account == GmailAccountCredentials.legacyAccount {
            email = try await GmailAPIClient.accountEmail(accessToken: token.accessToken)
            guard credentials.tokens[account] == refreshToken else { throw GmailError.notSignedIn }
            var updated = credentials
            updated.tokens.removeValue(forKey: account)
            updated.tokens[email] = refreshToken
            try persistAccounts(updated)
        }
        accessTokens[email] = (token.accessToken, .now.addingTimeInterval(TimeInterval(token.expiresIn)))
        return token.accessToken
    }

    private func persistAccounts(_ updated: GmailAccountCredentials) throws {
        if let storageError { throw storageError }
        if updated.tokens.isEmpty { try KeychainTokenStore.delete() }
        else { try KeychainTokenStore.save(updated.encoded()) }
        credentials = updated
        accounts = credentials.tokens.keys.sorted()
        Self.logger.info("Saved Gmail account connections: \(self.accounts.count)")
    }

    private func requestToken(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            Self.logger.error("Google token exchange failed with HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
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
        if let presentationWindow { return presentationWindow }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive && $0.session.role == .windowApplication }
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
