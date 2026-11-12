//
//  RestSession.swift
//  Emotional_Questions
//
//  The 1-minute rest by the moonlit lake (as in the Follow the Snake app), before the interview (baseline) and after it (recovery).
//  It runs on its own and keeps its own log, so the interview is unchanged.
//
//  Breathing is paced at a normal resting rate (12 per minute: 2 s in, 3 s out), not slow
//  paced breathing, so the baseline stays a resting baseline (slow breathing raises HRV).
//

import Foundation

@MainActor
@Observable
final class RestSession {
    enum Kind: String {
        case baseline, recovery

        var title: String { self == .baseline ? "Baseline" : "Recovery" }
    }

    enum Phase: Equatable {
        /// Instructions are showing; waiting for Start.
        case ready
        /// The minute is running.
        case resting
        /// The minute is over and the log is saved.
        case done
    }

    nonisolated static let restSeconds: TimeInterval = 60
    static let inhaleSeconds: TimeInterval = 2
    static let exhaleSeconds: TimeInterval = 3
    static var breathCycle: TimeInterval { inhaleSeconds + exhaleSeconds }

    private(set) var kind: Kind = .baseline
    private(set) var phase: Phase = .ready
    private(set) var startedAt: Date?
    private(set) var endsAt: Date?
    /// True when the minute ended early (the participant left the scene).
    private(set) var wasCutShort = false
    private(set) var savedLogURL: URL?
    private(set) var saveError: String?

    /// One file per participant run: baseline and recovery are written to the same file.
    private var runStartedAt: Date?
    private var log: [LogLine] = []
    private let logDirectory: URL?
    private let duration: TimeInterval

    init(logDirectory: URL? = nil, duration: TimeInterval = restSeconds) {
        self.logDirectory = logDirectory
        self.duration = duration
    }

    var isResting: Bool { phase == .resting }

    // MARK: - Flow

    /// Shows the instructions for a rest. Doesn't start the clock or log anything.
    func prepare(_ kind: Kind) {
        guard phase != .resting else { return }
        self.kind = kind
        phase = .ready
        startedAt = nil
        endsAt = nil
        wasCutShort = false
    }

    /// The participant pressed Start.
    func start(at now: Date = .now) {
        guard phase == .ready else { return }
        if kind == .baseline || runStartedAt == nil {
            // A new run: baseline starts a fresh log file.
            runStartedAt = now
            log = []
            savedLogURL = nil
            addLog("RUN START — rest_s=\(Int(duration)) breathing_per_min=\(Int(60 / Self.breathCycle)) inhale_s=\(Int(Self.inhaleSeconds)) exhale_s=\(Int(Self.exhaleSeconds)) scene=moonlit_lake", at: now)
        }
        phase = .resting
        startedAt = now
        endsAt = now.addingTimeInterval(duration)
        wasCutShort = false
        addLog("\(kind.rawValue.uppercased()) START", at: now)
    }

    /// Called on every clock tick; ends the minute when it's up.
    func refresh(at now: Date) {
        guard phase == .resting, let endsAt, now >= endsAt else { return }
        finish(at: endsAt, reason: nil)
    }

    /// The participant left the scene before the minute was up. What was recorded is still saved.
    func cutShort(reason: String, at now: Date = .now) {
        guard phase == .resting else { return }
        wasCutShort = true
        finish(at: now, reason: reason)
    }

    /// Back to the start for a new participant.
    func reset() {
        guard phase != .resting else { return }
        kind = .baseline
        phase = .ready
        startedAt = nil
        endsAt = nil
        wasCutShort = false
        runStartedAt = nil
        log = []
        savedLogURL = nil
        saveError = nil
    }

    // MARK: - Breathing guide

    func elapsed(at now: Date = .now) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    func progress(at now: Date = .now) -> Double {
        guard phase == .resting else { return phase == .done ? 1 : 0 }
        return min(1, elapsed(at: now) / duration)
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        guard phase == .resting, let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// 0 = fully out, 1 = fully in, eased so the motion never jerks.
    func breath(at now: Date = .now) -> Float {
        let t = elapsed(at: now).truncatingRemainder(dividingBy: Self.breathCycle)
        let x: Double = t < Self.inhaleSeconds
            ? t / Self.inhaleSeconds
            : 1 - (t - Self.inhaleSeconds) / Self.exhaleSeconds
        return Float(x * x * (3 - 2 * x))
    }

    func isInhaling(at now: Date = .now) -> Bool {
        elapsed(at: now).truncatingRemainder(dividingBy: Self.breathCycle) < Self.inhaleSeconds
    }

    // MARK: - Log

    func logText() -> String {
        var lines = [
            "Emotional Questions — rest log (baseline and recovery)",
            "Scene: moonlit lake. Breathing guide: \(Int(60 / Self.breathCycle)) breaths/min (\(Int(Self.inhaleSeconds)) s in, \(Int(Self.exhaleSeconds)) s out).",
            "Each line: local time | unix ms | event",
            "",
        ]
        for line in log {
            lines.append("\(QuestionLogFormat.stamp(line.at))  \(Self.unixMillis(line.at))  \(line.message)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func unixMillis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private func finish(at time: Date, reason: String?) {
        phase = .done
        endsAt = time
        let length = startedAt.map { time.timeIntervalSince($0) } ?? 0
        let note = reason.map { " — cut short: \($0)" } ?? ""
        addLog(String(format: "%@ END — %.1fs%@", kind.rawValue.uppercased(), length, note), at: time)
        save()
    }

    private func save() {
        do {
            let folder = try logDirectory ?? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let url = savedLogURL ?? Self.uniqueURL(in: folder, startedAt: runStartedAt ?? .now)
            try logText().write(to: url, atomically: true, encoding: .utf8)
            savedLogURL = url
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func uniqueURL(in folder: URL, startedAt: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let base = "rest-log_\(f.string(from: startedAt))"
        var url = folder.appendingPathComponent(base).appendingPathExtension("txt")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n)").appendingPathExtension("txt")
            n += 1
        }
        return url
    }

    private func addLog(_ message: String, at date: Date) {
        log.append(LogLine(at: date, message: message))
    }
}
