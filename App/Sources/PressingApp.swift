import SwiftUI
import PressingCore

@main
struct PressingApp: App {
    @State private var pressing = Pressing(
        audioInput: AVAudioSessionInput(),
        store: UserDefaultsStore()
    )

    var body: some Scene {
        WindowGroup {
            MainView(pressing: pressing)
                .task { pressing.start() }
                .preferredColorScheme(.dark)
        }
    }
}
