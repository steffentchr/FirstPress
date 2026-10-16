import Foundation
import Testing
import PressingCore

/// Connecting Last.fm through its own sign-in page, so Pressing never sees
/// the listener's password, and disconnecting it again.
@MainActor
@Suite("Last.fm connection")
struct LastFmConnectionTests {
    @Test("Connecting: auth.getToken, then the browser at last.fm/api/auth, then auth.getSession; the session key goes in the Keychain")
    func connect() async throws {
        let world = World()
        #expect(world.pressing.state.lastFm.connection == .disconnected)

        await world.pressing.connectLastFm()

        #expect(world.lastFm.calls.map(\.method) == ["auth.getToken", "auth.getSession"])
        let opened = try #require(world.webAuth.opened.first)
        let page = try #require(URLComponents(url: opened.url, resolvingAgainstBaseURL: false))
        #expect(page.host == "www.last.fm")
        #expect(page.path == "/api/auth/" || page.path == "/api/auth")
        #expect(page.queryItems?.first { $0.name == "api_key" }?.value == LastFmAccount.test.apiKey)
        #expect(page.queryItems?.first { $0.name == "token" }?.value == "TOKEN")
        #expect(world.lastFm.calls("auth.getSession").first?.params["token"] == "TOKEN")
        #expect(world.keychain.session == LastFmSession(username: "listener", key: "SESSIONKEY"))
        #expect(world.pressing.state.lastFm.connection == .connected(username: "listener"))
        #expect(world.pressing.state.lastFm.problem == nil)
    }

    @Test("api_sig: the parameters sorted by name, each name then value, the secret appended, md5 in lowercase hex")
    func signatureKnownVector() async throws {
        // The example from Last.fm's authentication spec.
        let world = World(account: LastFmAccount(apiKey: "xxxxxxxxxx", secret: "ilovecher"))
        world.lastFm.answers["auth.getToken"] = { _ in .json(#"{"token":"yyyyyy"}"#) }
        world.webAuth.callback = URL(string: "pressing://lastfm-auth?token=yyyyyy")

        await world.pressing.connectLastFm()

        let getSession = try #require(world.lastFm.calls("auth.getSession").first)
        #expect(getSession.httpMethod == "POST")
        #expect(getSession.params["api_sig"] == "b87d61da3cda91a8b6746c4aef55d6f8")
        // JSON is asked for, and `format` is left out of the signature.
        #expect(getSession.params["format"] == "json")
    }

    @Test("Closing the sign-in sheet still asks for the session, since the desktop flow has no redirect")
    func sheetClosed() async {
        let world = World()
        world.webAuth.callback = nil

        await world.pressing.connectLastFm()

        #expect(world.lastFm.calls.map(\.method) == ["auth.getToken", "auth.getSession"])
        #expect(world.pressing.state.lastFm.connection == .connected(username: "listener"))
    }

    @Test("A listener who didn't approve stays disconnected, without a complaint")
    func notApproved() async {
        let world = World()
        world.webAuth.callback = nil
        world.lastFm.answers["auth.getSession"] = { _ in .lastFmError(14, "Unauthorized Token - This token has not been authorized") }

        await world.pressing.connectLastFm()

        #expect(world.pressing.state.lastFm.connection == .disconnected)
        #expect(world.pressing.state.lastFm.problem == nil)
        #expect(world.keychain.session == nil)
    }

    @Test("Sign-in that fails for another reason says so")
    func signInFails() async {
        let world = World()
        world.lastFm.isOffline = true

        await world.pressing.connectLastFm()

        #expect(world.pressing.state.lastFm.connection == .disconnected)
        #expect(world.pressing.state.lastFm.problem == .signInFailed)
        #expect(world.webAuth.opened.isEmpty)
    }

    @Test("The connection survives a restart: the session key is read back from the Keychain")
    func surviveRestart() async {
        let world = World(lastFm: .listener)
        #expect(world.pressing.state.lastFm.connection == .connected(username: "listener"))
        #expect(world.lastFm.requests.isEmpty)
    }

    @Test("Disconnecting removes the session key")
    func disconnect() async {
        let world = World(lastFm: .listener)

        world.pressing.disconnectLastFm()

        #expect(world.keychain.session == nil)
        #expect(world.pressing.state.lastFm.connection == .disconnected)
    }

    @Test("A build without an API key can't connect")
    func noAPIKey() async {
        let world = World(account: nil, lastFm: .listener)
        #expect(world.pressing.state.lastFm.connection == .unavailable)

        await world.pressing.connectLastFm()

        #expect(world.lastFm.requests.isEmpty)
        #expect(world.webAuth.opened.isEmpty)
        #expect(world.pressing.state.lastFm.connection == .unavailable)
    }
}
