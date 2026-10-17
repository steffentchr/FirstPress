import AuthenticationServices
import FirstPressCore
import UIKit

/// Production WebAuth: Last.fm's sign-in page in `ASWebAuthenticationSession`,
/// so First Press never sees the listener's password. It shares Safari's
/// cookies, so a listener already signed in to last.fm only has to approve.
@MainActor
final class WebAuthenticationSession: NSObject, WebAuth, ASWebAuthenticationPresentationContextProviding {
    struct Cancelled: Error {}

    /// Held while the sheet is up; the system drops it otherwise.
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                MainActor.assumeIsolated {
                    self?.session = nil
                    if let callback {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: error ?? Cancelled())
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: Cancelled())
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return window
            }
            // No key window yet: a new one on the first scene.
            return ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}
