import Foundation

/// Fill in `clientID` to enable Gmail import. Create it yourself in Google
/// Cloud Console (console.cloud.google.com): APIs & Services > Credentials >
/// Create Credentials > OAuth client ID > iOS, using this app's bundle
/// identifier (com.footsoregnu3115.calendarapp). You'll also need to enable
/// the Gmail API for the project and add your own Google account as a test
/// user under OAuth consent screen while the app is unpublished.
///
/// iOS OAuth clients are "public" clients -- they use PKCE instead of a
/// client secret, so there is no secret to store here or anywhere else.
enum GoogleOAuthConfig {
    static let clientID = ""

    /// Must match a redirect URI registered for the client above, and the
    /// URL scheme declared in project.yml's CFBundleURLTypes.
    static let redirectURI = "com.footsoregnu3115.calendarapp:/oauth2redirect"

    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    static var isConfigured: Bool { !clientID.isEmpty }
}
