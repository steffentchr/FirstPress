import SwiftUI
import FirstPressCore

/// Settings: connect Last.fm through its own sign-in page, or disconnect it.
struct LastFmSection: View {
    let firstPress: FirstPress

    private var lastFm: LastFmState { firstPress.state.lastFm }

    var body: some View {
        Section {
            switch lastFm.connection {
            case .unavailable:
                Text("Not available in this build")
                    .foregroundStyle(.secondary)
            case .disconnected:
                Button("Connect Last.fm") {
                    Task { await firstPress.connectLastFm() }
                }
            case .connecting:
                HStack {
                    Text("Connecting…")
                    Spacer()
                    ProgressView()
                }
            case .connected(let username):
                LabeledContent("Scrobbling as", value: username)
                Button("Disconnect Last.fm", role: .destructive) {
                    firstPress.disconnectLastFm()
                }
            }
        } header: {
            Text("Last.fm")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if let problem = lastFm.problem {
            Text(Self.text(problem)).foregroundStyle(.orange)
        } else {
            switch lastFm.connection {
            case .unavailable:
                Text("The build has no Last.fm API key. See the README.")
            case .connected:
                Text("Each Track is scrobbled once it has played for half its length or 4 minutes. Disconnecting stops scrobbling; Plays not yet sent are never sent.")
            default:
                Text("You sign in on Last.fm's own page; First Press never sees your password. Plays from before you connect are never sent.")
            }
        }
    }

    private static func text(_ problem: LastFmState.Problem) -> String {
        switch problem {
        case .signInFailed:
            "Signing in to Last.fm didn't work. Check the network and try again."
        case .sessionRevoked:
            "Last.fm no longer accepts First Press's sign-in. Connect again to send the Plays still waiting."
        case .misconfigured(let code):
            "Last.fm refuses this build's API key (error \(code)). Plays wait until it is fixed."
        }
    }
}
