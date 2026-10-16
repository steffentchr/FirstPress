import SwiftUI
import UIKit
import PressingCore

@main
struct PressingApp: App {
    /// Kept apart from the core too, so the choose-input screen can ask for
    /// microphone access.
    private let audioInput: AVAudioSessionInput
    @State private var pressing: Pressing
    @State private var networkReturn = NetworkReturnMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let audioInput = AVAudioSessionInput()
        self.audioInput = audioInput
        _pressing = State(initialValue: Pressing(
            audioInput: audioInput,
            store: PhoneStore(),
            scheduler: MainQueueScheduler(),
            sonos: BonjourSonosNetwork(),
            streamSink: NetworkStreamServer(),
            encoder: LAMEEncoder(),
            phoneOutput: AVAudioPhoneOutput(input: audioInput),
            recognizer: ShazamRecognizer(),
            artwork: URLSessionArtworkDownloader(),
            lastFm: LastFmPorts(
                account: .fromBundle,
                http: URLSessionLastFmHTTP(),
                webAuth: WebAuthenticationSession(),
                keychain: KeychainCredentials()
            )
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(pressing: pressing, audioInput: audioInput)
                .task {
                    // iOS must never lock the phone; blanking is Pressing's own.
                    UIApplication.shared.isIdleTimerDisabled = true
                    pressing.start()
                    networkReturn.start { [pressing] in pressing.networkBecameAvailable() }
                }
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // Never come back to a black screen that needs a touch first.
            if phase == .active { pressing.cameToForeground() }
        }
    }
}
