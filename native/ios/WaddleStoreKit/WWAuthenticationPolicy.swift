import Foundation

// Only the fixed v2 callback may deliver a short-lived code to the app. Never
// accept an access token, verifier, or caller-selected redirect URI here.
enum WWAuthenticationPolicy {
    static let origin = "https://waddlewars.io"
    static let callbackScheme = "com.blubberandbyte.waddlewars.auth"

    static func validRequestID(_ requestID: String) -> Bool {
        guard let uuid = UUID(uuidString: requestID) else { return false }
        return requestID == uuid.uuidString.lowercased()
    }

    static func authorizationURL(_ text: String, requestID: String) -> URL? {
        guard validRequestID(requestID),
              text == "\(origin)/api/commerce/native-auth/authorize-ios-v2?request_id=\(requestID)",
              let url = URL(string: text) else { return nil }
        return url
    }

    static func callbackCode(_ url: URL, requestID: String) -> String? {
        guard validRequestID(requestID),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              code.utf8.count == 43,
              code.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        // Exact equality also rejects userinfo, alternate ports, fragments,
        // encoded values/paths, duplicate fields, and unexpected credentials.
        guard url.absoluteString == "\(callbackScheme)://native-auth/return?request_id=\(requestID)&code=\(code)" else { return nil }
        return code
    }
}
