import SwiftUI
import UIKit
import PressingCore

@main
struct PressingApp: App {
    @State private var pressing = Pressing(
        audioInput: AVAudioSessionInput(),
        store: PhoneStore(),
        scheduler: MainQueueScheduler(),
        sonos: BonjourSonosNetwork(),
        streamSink: NetworkStreamServer(),
        encoder: LAMEEncoder(),
        recognizer: ShazamRecognizer(),
        artwork: URLSessionArtworkDownloader(),
        lastFm: LastFmPorts(
            account: .fromBundle,
            http: URLSessionLastFmHTTP(),
            webAuth: WebAuthenticationSession(),
            keychain: KeychainCredentials()
        )
    )
    @State private var networkReturn = NetworkReturnMonitor()

    var body: some Scene {
        WindowGroup {
            // Swipe left from the main screen to History, right to come back.
            TabView {
                MainView(pressing: pressing)
                HistoryView(pressing: pressing)
                    .screenBlanker(pressing)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task {
                // iOS must never lock the phone; blanking is Pressing's own.
                UIApplication.shared.isIdleTimerDisabled = true
                pressing.start()
                networkReturn.start { [pressing] in pressing.networkBecameAvailable() }
            }
            .preferredColorScheme(.dark)
        }
    }
}
