import Foundation
import Network
import PressingCore

/// Tells the core when the phone gets a network path back, so scrobbles
/// owed go at once instead of at the next retry.
@MainActor
final class NetworkReturnMonitor {
    private let monitor = NWPathMonitor()
    private var wasSatisfied = true

    func start(_ onReturn: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if satisfied && !self.wasSatisfied { onReturn() }
                self.wasSatisfied = satisfied
            }
        }
        monitor.start(queue: .main)
    }
}

extension LastFmAccount {
    /// The API key and secret from the build configuration
    /// (`Config/LastFm.xcconfig`, via Info.plist). Nil when the build has none.
    static var fromBundle: LastFmAccount? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let key = info["LastFmAPIKey"] as? String, let secret = info["LastFmAPISecret"] as? String,
              !key.isEmpty, !secret.isEmpty else { return nil }
        return LastFmAccount(apiKey: key, secret: secret)
    }
}
