import Foundation

/// Connecting Last.fm: `auth.getToken`, the browser at last.fm/api/auth,
/// then `auth.getSession`. The session key goes in the Keychain.
extension Pressing {
    /// Intent from Settings: sign in to Last.fm in the browser. Plays that
    /// start from now on are scrobbled; those before never are.
    public func connectLastFm() async {
        guard let api = lastFmAPI, state.lastFm.connection == .disconnected else { return }
        state.lastFm = LastFmState(connection: .connecting)
        do throws(LastFmAPI.Failure) {
            let answer = try await api.post("auth.getToken", [:])
            guard let token = answer["token"] as? String else { throw .unreachable }
            // The desktop flow has no redirect, so a closed sheet may still
            // have been approved: ask for the session either way. If Last.fm
            // does redirect, its callback carries the token to use.
            let callback = try? await lastFmPorts.webAuth.authenticate(url: api.authPage(token: token), callbackScheme: LastFmAPI.callbackScheme)
            let approved = callback
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?
                .first { $0.name == "token" }?.value ?? token
            let session = try await api.post("auth.getSession", ["token": approved])["session"] as? [String: Any]
            guard let username = session?["name"] as? String, let key = session?["key"] as? String else { throw .unreachable }
            let saved = LastFmSession(username: username, key: key)
            lastFmPorts.keychain.saveLastFmSession(saved)
            scrobbling.session = saved
            state.lastFm = LastFmState(connection: .connected(username: username))
            // Plays still owed from before a revoked session go now.
            flushScrobbles()
        } catch {
            // 14: the token wasn't approved; 15: it expired. The listener
            // closed the sheet without approving, which needs no complaint.
            let declined = error == .lastFm(14) || error == .lastFm(15)
            state.lastFm = LastFmState(connection: .disconnected, problem: declined ? nil : .signInFailed)
        }
    }

    /// Intent from Settings: stop scrobbling. The session key is removed, and
    /// Plays not yet sent, the current one included, are never sent.
    public func disconnectLastFm() {
        guard case .connected = state.lastFm.connection else { return }
        lastFmPorts.keychain.deleteLastFmSession()
        state.lastFm = LastFmState(connection: .disconnected)
        let unsent = scrobbling.queue + (scrobbling.current.map { [$0] } ?? [])
        scrobbling.cancelTimers()
        scrobbling = Scrobbling()
        store.saveScrobbleQueue([])
        for id in unsent {
            updatePlay(id) { $0.scrobble = .notScrobbled }
        }
    }

    /// The phone is back online: Plays owed go at once rather than at the
    /// next retry.
    public func networkBecameAvailable() {
        scrobbling.backoff = 0
        flushScrobbles()
    }

    var isLastFmConnected: Bool {
        if case .connected = state.lastFm.connection { return true }
        return false
    }

    var lastFmAPI: LastFmAPI? {
        lastFmPorts.account.map { LastFmAPI(account: $0, http: lastFmPorts.http) }
    }

    /// At launch: connected if the Keychain holds a session, and the Plays
    /// owed from before go.
    func startLastFm() {
        let pending = Set(history.filter { $0.scrobble == .pending }.map(\.id))
        scrobbling.queue = store.loadScrobbleQueue().filter { pending.contains($0) }
        // A pending Play not in the queue was current when the app stopped,
        // and hadn't qualified yet.
        for id in pending.subtracting(scrobbling.queue) {
            updatePlay(id) { $0.scrobble = .notEligible }
        }
        guard lastFmPorts.account != nil else {
            state.lastFm = LastFmState(connection: .unavailable)
            return
        }
        if let session = lastFmPorts.keychain.loadLastFmSession() {
            scrobbling.session = session
            state.lastFm = LastFmState(connection: .connected(username: session.username))
            flushScrobbles()
        }
    }

    /// Changes a kept Play, wherever it shows.
    func updatePlay(_ id: Play.ID, _ change: (inout Play) -> Void) {
        guard var play = history.first(where: { $0.id == id }) else { return }
        change(&play)
        keep(play)
        if state.play?.id == id { state.play = play }
    }
}

/// The scrobbler: now playing and track.getInfo when a Play starts, the
/// moment it qualifies, and the durable queue flushed with track.scrobble.
extension Pressing {
    /// The most `track.scrobble` takes in one request.
    static let scrobbleBatchSize = 50
    /// Tracks this long or shorter are never scrobbled.
    static let shortestScrobbledTrack: TimeInterval = 30
    /// A Play qualifies by this much played time at the latest.
    static let longestQualifyingTime: TimeInterval = 240
    /// The first retry after a failure, doubled each time up to the longest.
    static let firstRetry: TimeInterval = 15
    static let longestRetry: TimeInterval = 15 * 60

    /// How long a Play of a Track this long must run to qualify, or nil if it
    /// never can. With no known length it qualifies at 240 s.
    static func qualifyingTime(duration: TimeInterval?) -> TimeInterval? {
        guard let duration else { return longestQualifyingTime }
        guard duration > shortestScrobbledTrack else { return nil }
        return min(duration / 2, longestQualifyingTime)
    }

    /// Whether a Play that ran this long qualifies at its end. With no known
    /// length, at least 30 s does.
    static func qualifies(played: TimeInterval, duration: TimeInterval?) -> Bool {
        guard duration != nil else { return played >= shortestScrobbledTrack }
        return qualifyingTime(duration: duration).map { played >= $0 } ?? false
    }

    /// A pending Play started: now playing, then track.getInfo for its
    /// length and album; it qualifies once it has run long enough.
    func scrobblePlayStarted(_ play: Play) {
        scrobbling.qualifyTimer?.cancel()
        scrobbling.current = nil
        guard play.scrobble == .pending, let api = lastFmAPI, let session = scrobbling.session else { return }
        scrobbling.current = play.id
        scrobbling.duration = nil
        scheduleQualification(of: play)
        let track = play.track
        Task { [weak self] in
            // Now playing is never retried.
            _ = try? await api.post("track.updateNowPlaying", ["artist": track.artist, "track": track.title, "sk": session.key])
            guard let info = try? await api.get("track.getInfo", ["artist": track.artist, "track": track.title, "autocorrect": "1"]) else { return }
            self?.learned(info["track"] as? [String: Any], about: play.id)
        }
    }

    /// What track.getInfo says: the length in milliseconds (0 when unknown)
    /// and the album.
    private func learned(_ info: [String: Any]?, about id: Play.ID) {
        if let album = (info?["album"] as? [String: Any])?["title"] as? String, !album.isEmpty {
            updatePlay(id) { play in
                if play.track.album == nil { play.track.album = album }
            }
        }
        let milliseconds = LastFmAPI.int(info?["duration"]) ?? 0
        guard milliseconds > 0, scrobbling.current == id, !scrobbling.queue.contains(id),
              let play = history.first(where: { $0.id == id }) else { return }
        scrobbling.duration = TimeInterval(milliseconds) / 1000
        scheduleQualification(of: play)
    }

    /// Checks, when the Play would have run long enough, that it really has.
    private func scheduleQualification(of play: Play) {
        scrobbling.qualifyTimer?.cancel()
        scrobbling.qualifyTimer = nil
        guard let time = Self.qualifyingTime(duration: scrobbling.duration) else { return }
        let due = play.startedAt.addingTimeInterval(time)
        checkQualification(of: play, at: time, after: max(0, due.timeIntervalSince(scheduler.now)))
    }

    private func checkQualification(of play: Play, at time: TimeInterval, after delay: TimeInterval) {
        scrobbling.qualifyTimer = scheduler.schedule(after: delay) { [weak self] in
            guard let self, scrobbling.current == play.id else { return }
            scrobbling.qualifyTimer = nil
            let shortfall = time - surelyPlayed(play)
            if shortfall <= 0 {
                enqueue(play.id)
            } else {
                // The Play may yet end earlier than now: check again once it
                // could have made up the difference.
                checkQualification(of: play, at: time, after: max(shortfall, 1))
            }
        }
    }

    /// How long the current Play has played for certain. Its end can still be
    /// dated back to when the deck went silent (a Flip follows), or to a Gap
    /// the searches haven't confirmed it since (a double miss follows).
    private func surelyPlayed(_ play: Play) -> TimeInterval {
        let end = [scheduler.now, detector.silenceBegan, identifier.earliestEnd].compactMap { $0 }.min() ?? scheduler.now
        return end.timeIntervalSince(play.startedAt)
    }

    /// The status a Play ends with, judged on the time it played: still
    /// pending if it qualified, not eligible if it didn't. A Play queued
    /// while its end was still open, but whose end came earlier, leaves the
    /// queue unless it is already on its way.
    func scrobbleStatusAtEnd(of play: Play) -> ScrobbleStatus {
        guard play.scrobble == .pending else { return play.scrobble }
        var duration: TimeInterval?
        if scrobbling.current == play.id {
            duration = scrobbling.duration
            scrobbling.qualifyTimer?.cancel()
            scrobbling.qualifyTimer = nil
            scrobbling.current = nil
        }
        let played = (play.endedAt ?? scheduler.now).timeIntervalSince(play.startedAt)
        if scrobbling.sending.contains(play.id) { return .pending }
        guard Self.qualifies(played: played, duration: duration) else {
            if scrobbling.queue.contains(play.id) {
                scrobbling.queue.removeAll { $0 == play.id }
                store.saveScrobbleQueue(scrobbling.queue)
            }
            return .notEligible
        }
        enqueue(play.id)
        return .pending
    }

    private func enqueue(_ id: Play.ID) {
        guard !scrobbling.queue.contains(id) else { return }
        scrobbling.queue.append(id)
        store.saveScrobbleQueue(scrobbling.queue)
        flushScrobbles()
    }

    /// Sends the oldest Plays owed, up to 50, unless a batch is on its way.
    func flushScrobbles() {
        guard scrobbling.sending.isEmpty, let api = lastFmAPI, let session = scrobbling.session else { return }
        scrobbling.retryTimer?.cancel()
        scrobbling.retryTimer = nil
        let owed = scrobbling.queue
            .compactMap { id in history.first { $0.id == id && $0.scrobble == .pending } }
            .sorted { $0.startedAt < $1.startedAt }
        if owed.count != scrobbling.queue.count {
            scrobbling.queue = owed.map(\.id)
            store.saveScrobbleQueue(scrobbling.queue)
        }
        guard !owed.isEmpty else { return }
        let batch = Array(owed.prefix(Self.scrobbleBatchSize))
        var params = ["sk": session.key]
        for (index, play) in batch.enumerated() {
            params["artist[\(index)]"] = play.track.artist
            params["track[\(index)]"] = play.track.title
            // When the Play started, in whole UTC seconds.
            params["timestamp[\(index)]"] = String(Int(play.startedAt.timeIntervalSince1970))
            if let album = play.track.album, !album.isEmpty {
                params["album[\(index)]"] = album
            }
        }
        scrobbling.sending = Set(batch.map(\.id))
        Task { [weak self] in
            let outcome: Result<[String: Any], LastFmAPI.Failure>
            do throws(LastFmAPI.Failure) {
                outcome = .success(try await api.post("track.scrobble", params))
            } catch {
                outcome = .failure(error)
            }
            guard let self else { return }
            scrobbling.sending = []
            sent(batch.map(\.id), outcome)
        }
    }

    private func sent(_ ids: [Play.ID], _ outcome: Result<[String: Any], LastFmAPI.Failure>) {
        switch outcome {
        case .success(let answer):
            if case .misconfigured = state.lastFm.problem { state.lastFm.problem = nil }
            // One item per scrobble, each with its own ignoredMessage code.
            // An answer that can't be read item by item was still accepted.
            let items = LastFmAPI.list((answer["scrobbles"] as? [String: Any])?["scrobble"])
            let codes = items.flatMap { items in
                items.count == ids.count ? items.map { LastFmAPI.int(($0["ignoredMessage"] as? [String: Any])?["code"]) ?? 0 } : nil
            } ?? ids.map { _ in 0 }
            var dailyLimitReached = false
            for (id, code) in zip(ids, codes) {
                switch code {
                case 0: settle(id, as: .scrobbled)
                // The daily scrobble limit: try again later.
                case 5: dailyLimitReached = true
                // Artist or track ignored, timestamp too old or too new.
                default: settle(id, as: .rejected)
                }
            }
            store.saveScrobbleQueue(scrobbling.queue)
            if dailyLimitReached {
                retryLater()
            } else {
                scrobbling.backoff = 0
                flushScrobbles()
            }
        case .failure(let failure) where failure.isSessionInvalid:
            // Plays owed stay queued until Last.fm is connected again.
            lastFmPorts.keychain.deleteLastFmSession()
            scrobbling.session = nil
            scrobbling.cancelTimers()
            state.lastFm = LastFmState(connection: .disconnected, problem: .sessionRevoked)
        case .failure(.lastFm(let code)) where LastFmAPI.Failure.lastFm(code).isMisconfigured:
            // Nothing gets through until the build is fixed; the next Play,
            // restart or return of the network tries again.
            state.lastFm.problem = .misconfigured(code: code)
        case .failure(let failure) where failure.isTransient:
            retryLater()
        case .failure:
            // Malformed, as far as Last.fm is concerned: not worth retrying.
            for id in ids { settle(id, as: .rejected) }
            store.saveScrobbleQueue(scrobbling.queue)
            flushScrobbles()
        }
    }

    private func settle(_ id: Play.ID, as status: ScrobbleStatus) {
        scrobbling.queue.removeAll { $0 == id }
        updatePlay(id) { $0.scrobble = status }
    }

    private func retryLater() {
        scrobbling.backoff = scrobbling.backoff == 0 ? Self.firstRetry : min(scrobbling.backoff * 2, Self.longestRetry)
        scrobbling.retryTimer?.cancel()
        scrobbling.retryTimer = scheduler.schedule(after: scrobbling.backoff) { [weak self] in
            self?.flushScrobbles()
        }
    }
}

/// The Plays owed to Last.fm and how they are being sent.
@MainActor
struct Scrobbling {
    /// Whose profile Plays go to; nil while Last.fm isn't connected.
    var session: LastFmSession?
    /// Plays that qualified and wait for Last.fm, by id. Kept in the Store.
    var queue: [Play.ID] = []
    /// The current Play, while it is pending and hasn't qualified yet.
    var current: Play.ID?
    /// The current Play's Track length from track.getInfo; nil while unknown.
    var duration: TimeInterval?
    var qualifyTimer: (any ScheduledWork)?
    /// The Plays in the batch on its way to Last.fm, if one is.
    var sending: Set<Play.ID> = []
    var retryTimer: (any ScheduledWork)?
    /// The wait before the next retry; 0 after a success.
    var backoff: TimeInterval = 0

    func cancelTimers() {
        qualifyTimer?.cancel()
        retryTimer?.cancel()
    }
}
