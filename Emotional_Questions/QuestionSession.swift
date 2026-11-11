//
//  QuestionSession.swift
//  Emotional_Questions
//

import Foundation
import SwiftUI

@Observable
final class QuestionSession {
    enum Phase: Equatable {
        case ready       // before Start is pressed
        case countdown   // Start pressed, logging on, 3-2-1 before the first question
        case playing     // questions on screen
        case finished    // Stop pressed (or round done), logging closed, log saved
    }

    static let secondsPerQuestion = 20
    static let countdownSeconds = 3
    /// The whole interview ends after this long, even if questions remain.
    static let interviewTimeLimit: TimeInterval = 3 * 60

    let questions: [InterviewQuestion]
    private(set) var phase: Phase = .ready
    private(set) var index = 0
    private(set) var secondsRemaining = secondsPerQuestion
    private(set) var countdownValue = 0
    /// Whole seconds left in the interview (counts down from 3:00 once the first question appears).
    private(set) var interviewSecondsRemaining = Int(interviewTimeLimit)
    /// Every question that appeared, in order.
    private(set) var entries: [QuestionLogEntry] = []
    /// Every line written to the log (session start/stop, questions, skips, time-ups).
    private(set) var log: [LogLine] = []
    private(set) var sessionStartDate: Date?
    private(set) var sessionEndDate: Date?
    /// Where the log was written when the session stopped (Files › On My Apple Vision Pro › Emotional_Questions).
    private(set) var savedLogURL: URL?
    private(set) var saveError: String?

    /// True from the moment Start is pressed until Stop is pressed — i.e. while logging is on.
    var isRunning: Bool { phase == .countdown || phase == .playing }

    private let logDirectory: URL?
    private let timeLimit: TimeInterval
    private var deadline: Date?
    /// When the interview ends regardless of how many questions are left.
    private var interviewDeadline: Date?
    private var questionShownAt: Date?

    /// `logDirectory` defaults to the app's Documents folder, which the Files app shows.
    /// `timeLimit` is the total interview length; the default is 3 minutes.
    init(
        questions: [InterviewQuestion] = QuestionBank.all,
        logDirectory: URL? = nil,
        timeLimit: TimeInterval = interviewTimeLimit
    ) {
        self.questions = questions
        self.logDirectory = logDirectory
        self.timeLimit = timeLimit
        self.interviewSecondsRemaining = Int(timeLimit)
    }

    var current: InterviewQuestion? {
        guard phase == .playing, questions.indices.contains(index) else { return nil }
        return questions[index]
    }

    var isLastQuestion: Bool {
        phase == .playing && index == questions.count - 1
    }

    // MARK: - Start / Stop

    /// Starts logging immediately, then shows a countdown before the first question.
    /// Pass `countdown: 0` to show the first question right away.
    func start(at date: Date = .now, countdown: Int = countdownSeconds) {
        guard !isRunning, !questions.isEmpty else { return }
        index = 0
        entries = []
        log = []
        sessionStartDate = date
        sessionEndDate = nil
        savedLogURL = nil
        saveError = nil
        questionShownAt = nil
        secondsRemaining = Self.secondsPerQuestion
        interviewDeadline = nil
        interviewSecondsRemaining = Int(timeLimit)

        addLog(String(
            format: "SESSION START — %d questions, %ds each, %.0fs interview limit",
            questions.count, Self.secondsPerQuestion, timeLimit
        ), at: date)
        QuestionLogger.roundStarted(questionCount: questions.count)

        guard countdown > 0 else {
            beginQuestions(at: date)
            return
        }
        phase = .countdown
        countdownValue = countdown
        deadline = date.addingTimeInterval(TimeInterval(countdown))
    }

    /// Ends the session, closes the log and saves it to Files automatically.
    func stop(at date: Date = .now) {
        guard isRunning else { return }
        end(reason: "stopped", at: date)
    }

    /// Returns to the welcome screen after a finished session.
    func restart() {
        guard !isRunning else { return }
        phase = .ready
        index = 0
        secondsRemaining = Self.secondsPerQuestion
        countdownValue = 0
        deadline = nil
        interviewDeadline = nil
        interviewSecondsRemaining = Int(timeLimit)
    }

    // MARK: - Questions

    /// The participant pressed Next (or Finish on the last question).
    func advance(at date: Date = .now) {
        guard phase == .playing else { return }
        addLog("NEXT PRESSED [\(index + 1)] — after \(elapsed(at: date))", at: date)
        moveOn(at: date)
    }

    func refresh(at date: Date) {
        guard isRunning, let deadline else { return }
        let remaining = deadline.timeIntervalSince(date)

        if phase == .countdown {
            if remaining <= 0 {
                beginQuestions(at: deadline)
            } else {
                let shown = max(1, Int(ceil(remaining)))
                if shown != countdownValue { countdownValue = shown }
            }
            return
        }

        if let interviewDeadline, date >= interviewDeadline {
            addLog(String(format: "INTERVIEW TIME LIMIT — %.0fs reached during question %d", timeLimit, index + 1), at: date)
            end(reason: "time limit reached", at: date)
            return
        }
        if let interviewDeadline {
            let left = max(0, Int(ceil(interviewDeadline.timeIntervalSince(date))))
            if left != interviewSecondsRemaining { interviewSecondsRemaining = left }
        }

        if remaining <= 0 {
            addLog("TIME UP [\(index + 1)] — \(Self.secondsPerQuestion)s limit reached", at: date)
            moveOn(at: date)
            return
        }
        let shown = min(Self.secondsPerQuestion, max(1, Int(ceil(remaining))))
        if shown != secondsRemaining {
            secondsRemaining = shown
        }
    }

    func fractionRemaining(at date: Date) -> Double {
        guard phase == .playing, let deadline else {
            return phase == .finished ? 0 : 1
        }
        let remaining = deadline.timeIntervalSince(date)
        return min(1, max(0, remaining / Double(Self.secondsPerQuestion)))
    }

    // MARK: - Log

    var sessionDuration: TimeInterval {
        guard let sessionStartDate else { return 0 }
        return (sessionEndDate ?? .now).timeIntervalSince(sessionStartDate)
    }

    func logText(generatedAt: Date = .now) -> String {
        QuestionLogFormat.text(lines: log, questionsShown: entries.count, generatedAt: generatedAt)
    }

    var suggestedLogFilename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "emotional-log_\(f.string(from: sessionStartDate ?? .now))"
    }

    /// Writes the log into the app's Documents folder, which the Files app shows,
    /// so nothing is asked of the participant after Stop.
    func saveLogToFiles() {
        do {
            let folder = try logDirectory ?? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var url = folder.appendingPathComponent(suggestedLogFilename).appendingPathExtension("txt")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(suggestedLogFilename)-\(n)").appendingPathExtension("txt")
                n += 1
            }
            try logText().write(to: url, atomically: true, encoding: .utf8)
            savedLogURL = url
            saveError = nil
        } catch {
            savedLogURL = nil
            saveError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func beginQuestions(at date: Date) {
        phase = .playing
        countdownValue = 0
        index = 0
        interviewDeadline = date.addingTimeInterval(timeLimit)
        interviewSecondsRemaining = Int(timeLimit)
        reveal(at: date)
    }

    private func moveOn(at date: Date) {
        let next = index + 1
        guard questions.indices.contains(next) else {
            end(reason: "round complete", at: date)
            return
        }
        index = next
        reveal(at: date)
    }

    private func reveal(at date: Date) {
        deadline = date.addingTimeInterval(TimeInterval(Self.secondsPerQuestion))
        questionShownAt = date
        secondsRemaining = Self.secondsPerQuestion
        let question = questions[index]
        let entry = QuestionLogEntry(
            number: index + 1,
            appearedAt: date,
            tier: question.tier.title,
            difficulty: question.difficulty,
            prompt: question.prompt
        )
        entries.append(entry)
        addLog("NEW QUESTION [\(entry.number)] — \(entry.tier) | difficulty \(entry.difficulty) | \(entry.prompt)", at: date)
        QuestionLogger.appeared(entry)
    }

    private func end(reason: String, at date: Date) {
        phase = .finished
        deadline = nil
        interviewDeadline = nil
        interviewSecondsRemaining = 0
        secondsRemaining = 0
        countdownValue = 0
        sessionEndDate = date
        addLog(String(
            format: "SESSION STOP — %@ | questions shown: %d of %d | duration: %.0fs",
            reason, entries.count, questions.count, sessionDuration
        ), at: date)
        QuestionLogger.roundFinished(questionCount: entries.count)
        saveLogToFiles()
    }

    private func elapsed(at date: Date) -> String {
        guard let questionShownAt else { return "0.0s" }
        return String(format: "%.1fs", date.timeIntervalSince(questionShownAt))
    }

    private func addLog(_ message: String, at date: Date) {
        log.append(LogLine(at: date, message: message))
    }
}
