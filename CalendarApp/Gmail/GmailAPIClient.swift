import Foundation

struct GmailMessageDetail {
    let id: String
    let subject: String
    let from: String
    let snippet: String
    let bodyText: String
    let internalDate: Date?
}

/// Thin wrapper over the Gmail REST API's message list/get endpoints --
/// read-only, matching the gmail.readonly scope this app requests.
enum GmailAPIClient {
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    static func searchMessages(query: String, accessToken: String, maxResults: Int = 25) async throws -> [String] {
        var components = URLComponents(string: "\(base)/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        guard let url = components.url else { throw GmailError.requestFailed }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GmailError.requestFailed
        }
        let list = try JSONDecoder().decode(GmailMessageListResponse.self, from: data)
        return list.messages?.map(\.id) ?? []
    }

    static func fetchMessage(id: String, accessToken: String) async throws -> GmailMessageDetail {
        var components = URLComponents(string: "\(base)/messages/\(id)")!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        guard let url = components.url else { throw GmailError.requestFailed }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GmailError.requestFailed
        }
        let raw = try JSONDecoder().decode(RawGmailMessage.self, from: data)
        let headers = raw.payload?.headers ?? []
        let subject = headers.first { $0.name.caseInsensitiveCompare("Subject") == .orderedSame }?.value ?? "(no subject)"
        let from = headers.first { $0.name.caseInsensitiveCompare("From") == .orderedSame }?.value ?? ""
        let bodyText = extractPlainText(from: raw.payload) ?? raw.snippet
        let internalDate: Date? = raw.internalDate
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0 / 1000) }

        return GmailMessageDetail(id: raw.id, subject: subject, from: from, snippet: raw.snippet, bodyText: bodyText, internalDate: internalDate)
    }

    private static func extractPlainText(from part: RawGmailPart?) -> String? {
        guard let part else { return nil }
        if part.mimeType == "text/plain", let data = part.body?.data {
            return decodeBase64URL(data)
        }
        for sub in part.parts ?? [] {
            if let text = extractPlainText(from: sub) { return text }
        }
        return nil
    }

    private static func decodeBase64URL(_ string: String) -> String? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageSummary]?
}

private struct GmailMessageSummary: Decodable {
    let id: String
}

private struct RawGmailMessage: Decodable {
    let id: String
    let snippet: String
    let internalDate: String?
    let payload: RawGmailPart?
}

private struct RawGmailPart: Decodable {
    let mimeType: String?
    let headers: [RawGmailHeader]?
    let body: RawGmailBody?
    let parts: [RawGmailPart]?
}

private struct RawGmailHeader: Decodable {
    let name: String
    let value: String
}

private struct RawGmailBody: Decodable {
    let data: String?
}
