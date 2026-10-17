import Foundation
import Testing
import PressingCore
import PressingMenuCore

@MainActor
@Suite("Pressing Menu's notifications")
struct PressingMenuNotificationTests {
    @Test("Each new Track identified while connected gets a notification")
    func eachNewTrack() async {
        let world = World()
        let (menu, _, notifier) = world.notifyingPressingMenu()

        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.ballad])

        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.ballad, .rocker])
        #expect(menu.header == .track(.rocker))
    }

    @Test("The Track already playing when Pressing Menu connects gets no notification")
    func alreadyPlayingOnConnect() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        let (menu, _, notifier) = world.notifyingPressingMenu()
        #expect(menu.header == .track(.ballad))
        #expect(notifier.notified.isEmpty)

        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.rocker])
    }

    @Test("The Track playing when Pressing Menu reconnects gets no notification, even one identified while it couldn't reach the phone")
    func alreadyPlayingOnReconnect() async {
        let world = World()
        let (menu, link, notifier) = world.notifyingPressingMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.ballad])

        // Reconnecting while the same Track plays.
        link.drop()
        world.scheduler.advance(by: 1)
        #expect(menu.connection == .connected)
        #expect(notifier.notified == [.ballad])

        // The next Track is identified while Pressing can't be reached.
        world.menuServer.stop()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.connection == .cantBeReached)
        world.menuServer.start()
        #expect(menu.connection == .connected)
        #expect(menu.header == .track(.rocker))
        #expect(notifier.notified == [.ballad])
    }

    @Test("No Track gets a notification while the panel is open, and closing it doesn't post a late one")
    func notWhilePanelOpen() async {
        let world = World()
        let (menu, _, notifier) = world.notifyingPressingMenu()

        menu.isPanelOpen = true
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .track(.ballad))
        #expect(notifier.notified.isEmpty)

        menu.isPanelOpen = false
        #expect(notifier.notified.isEmpty)

        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.rocker])
    }

    @Test("No Track gets a notification while Notify on new Track is off")
    func notWhileSwitchedOff() async {
        let world = World()
        let (menu, _, notifier) = world.notifyingPressingMenu()
        #expect(menu.notifiesOnNewTrack)

        menu.notifiesOnNewTrack = false
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(menu.header == .track(.rocker))
        #expect(notifier.notified.isEmpty)
    }

    @Test("While macOS denies Pressing Menu notifications, none is asked for and Notify on new Track shows off, until they're allowed")
    func notWhileDeniedByMacOS() async {
        let world = World()
        let (menu, _, notifier) = world.notifyingPressingMenu()
        #expect(menu.postsNotifications)

        menu.notificationsAreDenied = true
        #expect(menu.notifiesOnNewTrack)
        #expect(!menu.postsNotifications)
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .track(.ballad))
        #expect(notifier.notified.isEmpty)

        menu.notificationsAreDenied = false
        #expect(menu.postsNotifications)
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(notifier.notified == [.rocker])
    }

    @Test("The same Track gaining its album or cover later gets no second notification")
    func detailsArrivingLater() {
        let world = World()
        let (menu, link, notifier) = world.notifyingPressingMenu()

        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "playing", "track": {"artist": "Kate Bush", "title": "Wuthering Heights"}}"#)
        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "playing", "track": {"artist": "Kate Bush", "title": "Wuthering Heights", "album": "The Kick Inside", "artworkURL": "https://example.com/kick.jpg"}}"#)

        #expect(menu.header == .track(Track(artist: "Kate Bush", title: "Wuthering Heights", album: "The Kick Inside", artworkURL: URL(string: "https://example.com/kick.jpg"))))
        #expect(notifier.notified == [Track(artist: "Kate Bush", title: "Wuthering Heights")])
    }

    @Test("The same Track spelled with other case or accents gets no second notification, as History counts it once")
    func sameTrackOtherSpelling() {
        let world = World()
        let (menu, link, notifier) = world.notifyingPressingMenu()

        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "playing", "track": {"artist": "Björk", "title": "Jóga"}}"#)
        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "playing", "track": {"artist": "Bjork", "title": "Joga"}}"#)
        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "playing", "track": {"artist": "BJÖRK", "title": "jóga"}}"#)

        #expect(menu.header == .track(Track(artist: "BJÖRK", title: "jóga")))
        #expect(notifier.notified == [Track(artist: "Björk", title: "Jóga")])
    }
}

extension World {
    /// A Pressing Menu joined to this world's phone, posting its
    /// notifications to a fake.
    func notifyingPressingMenu() -> (menu: PressingMenu, link: FakeMenuLink, notifier: FakeTrackNotifier) {
        let link = FakeMenuLink(server: menuServer)
        let notifier = FakeTrackNotifier()
        let menu = PressingMenu(link: link, scheduler: scheduler, notifier: notifier)
        menu.start()
        return (menu, link, notifier)
    }
}
