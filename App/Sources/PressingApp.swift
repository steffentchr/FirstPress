import SwiftUI
import UIKit
import PressingCore

@main
struct PressingApp: App {
    @State private var pressing = Pressing(
        audioInput: AVAudioSessionInput(),
        store: UserDefaultsStore(),
        scheduler: MainQueueScheduler(),
        sonos: BonjourSonosNetwork(),
        streamSink: NetworkStreamServer(),
        encoder: LAMEEncoder()
    )

    var body: some Scene {
        WindowGroup {
            MainView(pressing: pressing)
                .task {
                    // iOS must never lock the phone; blanking is Pressing's own.
                    UIApplication.shared.isIdleTimerDisabled = true
                    pressing.start()
                }
                .preferredColorScheme(.dark)
        }
    }
}
