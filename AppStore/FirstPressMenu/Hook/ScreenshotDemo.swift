// App Store screenshot hook for First Press Menu. AppStore/FirstPressMenu/screenshots.sh
// copies this into Menu/Sources for one build and removes it again; it is
// never committed there. It links First Press Menu to a phone that only sends
// AppStore/FirstPress/demo.json's sample world, renders the real panel and
// Settings window to PNGs, and quits.
import AppKit
import SwiftUI
import FirstPressCore
import FirstPressMenuCore

@MainActor
enum ScreenshotDemo {
    /// Where the renders go. Set by `-FirstPressMenuScreenshot <folder>`; nil
    /// in a normal launch, and then nothing here runs.
    static var output: String? { UserDefaults.standard.string(forKey: "FirstPressMenuScreenshot") }
    /// The sample world: `-FirstPressMenuDemo <AppStore/FirstPress/demo.json>`.
    private static var demoPath: String { UserDefaults.standard.string(forKey: "FirstPressMenuDemo")! }
    /// The sleeves as PNGs, one per cover name: `-FirstPressMenuCovers <folder>`.
    private static var coversPath: String { UserDefaults.standard.string(forKey: "FirstPressMenuCovers")! }

    /// Read by the panel's Rooms switch as it's made (see hook.patch).
    static var showsRooms = false
    /// Renders at three pixels per point, so the framing can scale freely.
    private static let scale: CGFloat = 3
    private static var windows: [NSWindow] = []

    /// The phone, in a screenshot run: one that sends the sample world on
    /// connect and ignores commands. Nil otherwise.
    static var link: (any MenuLink)? { output == nil ? nil : DemoLink(snapshot: snapshot()) }

    private struct Demo: Decodable {
        struct Room: Decodable { var name: String; var on: Bool; var volume: Int }
        struct Item: Decodable { var title: String; var artist: String; var album: String; var cover: String; var minutesAgo: Double? }
        var rooms: [Room]
        var nowPlaying: Item
        var history: [Item]
    }

    private static func track(_ item: Demo.Item) -> Track {
        Track(artist: item.artist, title: item.title, album: item.album,
              artworkURL: URL(fileURLWithPath: coversPath).appendingPathComponent("\(item.cover).png"))
    }

    private static func snapshot() -> MenuSnapshot {
        let demo = try! JSONDecoder().decode(Demo.self, from: Data(contentsOf: URL(fileURLWithPath: demoPath)))
        let now = Date()
        return MenuSnapshot(
            page: .nowPlaying,
            record: .playing,
            track: track(demo.nowPlaying),
            recentPlays: demo.history.prefix(MenuSnapshot.panelHistoryLimit).map {
                MenuSnapshot.Play(track: track($0), startedAt: now.addingTimeInterval(-($0.minutesAgo ?? 0) * 60))
            },
            rooms: demo.rooms.enumerated().map { index, room in
                MenuSnapshot.Room(id: String(format: "RINCON_000E58%06d01400", index), name: room.name, isOn: room.on, volume: room.volume)
            },
            phoneOutput: MenuSnapshot.PhoneOutput(isOn: false, route: PhoneOutputRoute(name: "Speaker", kind: .builtInSpeaker))
        )
    }

    /// Renders each scene, then quits. Called once the app is up.
    static func start(menu: FirstPressMenu, settings: MenuSettings, loginItem: LoginItem, notifications: UserNotifications) {
        guard let output else { return }
        let folder = URL(fileURLWithPath: output)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        drawAsActive()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            // One at a time, each window key while it renders, so its
            // controls draw as active ones do.
            showsRooms = false
            await render(PanelView(menu: menu).environment(settings), titled: nil, to: folder.appendingPathComponent("panel-history.png"))
            showsRooms = true
            await render(PanelView(menu: menu).environment(settings), titled: nil, to: folder.appendingPathComponent("panel-rooms.png"))
            await render(
                SettingsView(menu: menu, settings: settings, loginItem: loginItem, notifications: notifications),
                titled: "First Press Menu Settings", to: folder.appendingPathComponent("settings.png")
            )
            exit(0)
        }
    }

    private static func render(_ view: some View, titled title: String?, to url: URL) async {
        let shown = host(view, titled: title)
        // Time for layout and for any cover to load.
        try? await Task.sleep(for: .seconds(2))
        save(shown, to: url)
        shown.window?.orderOut(nil)
    }

    /// A menu-bar app started from a script isn't brought to the front, and
    /// an inactive app draws its switches and checkboxes grey. For the
    /// renders, AppKit is told the app and its windows are active.
    private static func drawAsActive() {
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        let targets: [(AnyClass, String)] = [
            (NSApplication.self, "isActive"),
            (NSWindow.self, "hasKeyAppearance"),
            (NSWindow.self, "hasMainAppearance"),
            (NSWindow.self, "_hasActiveAppearance"),
            (NSWindow.self, "_hasActiveAppearanceIgnoringKeyFocus"),
            (NSWindow.self, "_hasKeyAppearance"),
            (NSWindow.self, "_hasMainAppearance"),
        ]
        for (type, name) in targets {
            guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)) else { continue }
            method_setImplementation(method, imp_implementationWithBlock(yes))
        }
    }

    /// Puts a view in a window of its own, off screen. A titled window keeps
    /// its title bar, so the render shows it.
    private static func host(_ view: some View, titled title: String?) -> NSView {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: title == nil ? [.borderless] : [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.backgroundColor = title == nil ? .clear : .windowBackgroundColor
        window.isOpaque = title != nil
        window.title = title ?? ""
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        // The title bar lives in the content view's superview, the frame view.
        return title == nil ? hosting : hosting.superview!
    }

    private static func save(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("rendered \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height)) pt")
    }
}

/// A window that draws as the key window, title bar or not, even though a
/// menu-bar app launched from a script isn't brought to the front.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// A phone that sends one snapshot on connect, and ignores every command.
@MainActor
private final class DemoLink: MenuLink {
    private let message: Data
    private var handler: (@MainActor (MenuLinkEvent) -> Void)?

    init(snapshot: MenuSnapshot) { message = MenuWire.encode(snapshot) }

    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void) { self.handler = handler }
    func connect() {
        handler?(.connected)
        handler?(.received(message))
    }
    func send(_ message: Data) {}
}
