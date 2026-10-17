import SwiftUI
import UIKit
import FirstPressCore

@main
struct FirstPressApp: App {
    /// Kept apart from the core too, so the choose-input screen can ask for
    /// microphone access.
    private let audioInput: AVAudioSessionInput
    @State private var firstPress: FirstPress
    @State private var networkReturn = NetworkReturnMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let audioInput = AVAudioSessionInput()
        self.audioInput = audioInput
        _firstPress = State(initialValue: FirstPress(
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
            ),
            menuServer: BonjourMenuServer()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(firstPress: firstPress, audioInput: audioInput)
                .task {
                    // iOS must never lock the phone; blanking is First Press's own.
                    UIApplication.shared.isIdleTimerDisabled = true
                    firstPress.start()
                    networkReturn.start { [firstPress] in firstPress.networkBecameAvailable() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Never come back to a black screen that needs a touch first.
            if phase == .active { firstPress.cameToForeground() }
        }
    }
}
