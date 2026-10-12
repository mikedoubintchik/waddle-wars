import Foundation

@main
struct AuthenticationPolicyTest {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool) {
            precondition(value())
            checks += 1
        }
        let id = "b19ce5a7-8257-4e02-96d5-4f8e9928bdf4"
        let other = "664b8715-226d-4894-a43d-e8c05d5c97a1"
        let code = String(repeating: "a", count: 41) + "_-"
        let authorized = "\(WWAuthenticationPolicy.origin)/api/commerce/native-auth/authorize-ios-v2?request_id=\(id)"
        let callbackBase = "\(WWAuthenticationPolicy.callbackScheme)://native-auth/return?request_id=\(id)"
        let callback = "\(callbackBase)&code=\(code)"
        check(WWAuthenticationPolicy.origin == "https://waddlewars.io")
        check(WWAuthenticationPolicy.authorizationURL(authorized, requestID: id) != nil)
        check(WWAuthenticationPolicy.callbackCode(URL(string: callback)!, requestID: id) == code)
        check(!WWAuthenticationPolicy.validRequestID(id.uppercased()))
        check(!WWAuthenticationPolicy.validRequestID("not-a-uuid"))
        for bad in [
            authorized.replacingOccurrences(of: "https://", with: "http://"),
            authorized.replacingOccurrences(of: "waddlewars.io", with: "waddlewars.io.attacker.invalid"),
            authorized.replacingOccurrences(of: "waddlewars.io", with: "waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"),
            authorized.replacingOccurrences(of: "authorize-ios-v2", with: "authorize"),
            authorized.replacingOccurrences(of: "authorize-ios-v2", with: "authorize-ios"),
            authorized + "&token=forbidden", authorized + "#fragment",
            authorized.replacingOccurrences(of: "waddlewars.io/", with: "waddlewars.io:443/"),
            authorized.replacingOccurrences(of: id, with: other),
            authorized.replacingOccurrences(of: "https://", with: "https://user:password@"),
        ] { check(WWAuthenticationPolicy.authorizationURL(bad, requestID: id) == nil) }
        for bad in [
            callbackBase,
            callback.replacingOccurrences(of: id, with: other),
            callback + "&token=forbidden", callback + "&request_id=\(id)",
            callback + "&code=\(code)", callback + "&verifier=forbidden",
            callback + "#fragment", callback.replacingOccurrences(of: "/return", with: "/%72eturn"),
            callback.replacingOccurrences(of: "native-auth/", with: "native-auth:443/"),
            callback.replacingOccurrences(of: "native-auth/", with: "attacker.invalid/"),
            callback.replacingOccurrences(of: "://", with: "://user:password@"),
            callback.replacingOccurrences(of: "&code=", with: "&%63ode="),
            callback.replacingOccurrences(of: code, with: "%61" + String(code.dropFirst())),
            callback.replacingOccurrences(of: "request_id=\(id)&code=\(code)", with: "code=\(code)&request_id=\(id)"),
        ] { check(WWAuthenticationPolicy.callbackCode(URL(string: bad)!, requestID: id) == nil) }
        for badCode in ["", String(repeating: "a", count: 42), String(repeating: "a", count: 44),
                        String(repeating: "a", count: 42) + "=", String(repeating: "a", count: 42) + "+",
                        String(repeating: "a", count: 42) + "/", String(repeating: "a", count: 42) + "é"] {
            let url = URL(string: "\(callbackBase)&code=\(badCode)")!
            check(WWAuthenticationPolicy.callbackCode(url, requestID: id) == nil)
        }
        print("\(checks) authentication policy checks passed")
    }
}
