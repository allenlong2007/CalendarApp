import Foundation

/// Native iOS/Mac Catalyst client in the CalendarApp Google Cloud project.
/// Gmail API is enabled. While OAuth remains in testing mode, accounts must
/// be added under Google Auth Platform > Audience before signing in.
///
/// iOS OAuth clients are "public" clients -- they use PKCE instead of a
/// client secret, so there is no secret to store here or anywhere else.
enum GoogleOAuthConfig {
    static let clientID = "1056359363976-hg1s4aknnhvonhaf2lem5rgvimrqsi26.apps.googleusercontent.com"

    /// Native Google OAuth uses the reversed client ID as its URL scheme,
    /// also declared in project.yml's CFBundleURLTypes.
    static let redirectURI = "com.googleusercontent.apps.1056359363976-hg1s4aknnhvonhaf2lem5rgvimrqsi26:/oauth2redirect"

    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    static var isConfigured: Bool { !clientID.isEmpty }
}
