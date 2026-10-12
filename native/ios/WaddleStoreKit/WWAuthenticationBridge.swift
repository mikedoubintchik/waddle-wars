import AuthenticationServices
import Foundation
import UIKit

@MainActor
private final class WWAuthenticationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Captured from Godot's actual visible view, not an arbitrary scene.
        return window
    }
}

@MainActor
@objc(WWAuthenticationBridge)
public final class WWAuthenticationBridge: NSObject {
    @objc public static let shared = WWAuthenticationBridge()
    @objc public var eventHandler: ((String, String) -> Void)?

    private var session: ASWebAuthenticationSession?
    private var provider: WWAuthenticationAnchor?
    private var requestID: String?
    private var generation: UInt64 = 0

    @objc(beginAuthentication:requestID:anchor:)
    public func beginAuthentication(_ authorization: String, requestID: String, anchor: UIWindow?) {
        guard let url = WWAuthenticationPolicy.authorizationURL(authorization, requestID: requestID) else {
            emit("auth_session_finished", requestID: requestID, outcome: "invalid_request")
            return
        }
        guard session == nil,
              let anchor,
              !anchor.isHidden,
              anchor.rootViewController != nil,
              anchor.windowScene?.activationState == .foregroundActive else {
            emit("auth_session_finished", requestID: requestID, outcome: "unavailable")
            return
        }

        generation &+= 1
        let currentGeneration = generation
        self.requestID = requestID
        provider = WWAuthenticationAnchor(window: anchor)
        let completion: ASWebAuthenticationSession.CompletionHandler = { [weak self] callback, error in
            Task { @MainActor [weak self] in
                self?.complete(callback: callback, error: error, requestID: requestID, generation: currentGeneration)
            }
        }
        let next: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            next = ASWebAuthenticationSession(url: url, callback: .customScheme(WWAuthenticationPolicy.callbackScheme), completionHandler: completion)
        } else {
            next = ASWebAuthenticationSession(url: url, callbackURLScheme: WWAuthenticationPolicy.callbackScheme, completionHandler: completion)
        }
        next.presentationContextProvider = provider
        next.prefersEphemeralWebBrowserSession = true
        session = next
        guard next.canStart, next.start() else {
            clearActive()
            emit("auth_session_finished", requestID: requestID, outcome: "unavailable")
            return
        }
        emit("auth_session_started", requestID: requestID)
    }

    // Called for app cancellation, expiry, logout, or server-token acceptance.
    // Suppress the cancel completion; the caller already chose the outcome.
    @objc(endAuthentication:)
    public func endAuthentication(_ requestID: String) {
        guard self.requestID == requestID else { return }
        let previous = session
        clearActive()
        previous?.cancel()
    }

    @objc public func stop() {
        eventHandler = nil
        let previous = session
        clearActive()
        previous?.cancel()
    }

    private func complete(callback: URL?, error: Error?, requestID: String, generation: UInt64) {
        guard self.generation == generation, self.requestID == requestID, session != nil else { return }
        clearActive()
        if let error {
            let failure = error as NSError
            let outcome = failure.domain == ASWebAuthenticationSessionErrorDomain &&
                failure.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue ? "cancelled" : "unavailable"
            emit("auth_session_finished", requestID: requestID, outcome: outcome)
        } else if let callback, let code = WWAuthenticationPolicy.callbackCode(callback, requestID: requestID) {
            // Private bridge delivery only; never log, persist or display this
            // code. The server requires it together with the app's PKCE proof.
            emit("auth_session_authorized", requestID: requestID, callbackCode: code)
        } else {
            emit("auth_session_finished", requestID: requestID, outcome: "invalid_callback")
        }
    }

    private func clearActive() {
        generation &+= 1
        session = nil
        provider = nil
        requestID = nil
    }

    private func emit(_ event: String, requestID: String, outcome: String? = nil, callbackCode: String? = nil) {
        var payload = ["request_id": requestID]
        if let outcome { payload["outcome"] = outcome }
        if let callbackCode { payload["callback_code"] = callbackCode }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        eventHandler?(event, text)
    }
}
