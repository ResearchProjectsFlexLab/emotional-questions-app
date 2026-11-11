//
//  Emotional_QuestionsTests.swift
//  Emotional_QuestionsTests
//
//  Created by Prisha Marpu on 10/20/26.
//

import Foundation
import Testing
@testable import Emotional_Questions

@MainActor
struct Emotional_QuestionsTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func questionsGetHarderInOrder() {
        let questions = QuestionBank.all
        #expect(questions.map(\.difficulty) == Array(1...questions.count))
        let tiers = questions.map(\.tier)
        #expect(tiers == tiers.sorted())
    }

    @Test func eachQuestionLastsTwentySeconds() {
        #expect(QuestionSession.secondsPerQuestion == 20)
    }

    @Test func startingLogsSessionStartAndTheQuestionThatAppears() {
        let session = makeSession()
        session.start(at: start, countdown: 0)

        #expect(session.isRunning)
        #expect(session.entries.count == 1)
        #expect(session.entries[0].number == 1)
        #expect(session.entries[0].prompt == "First prompt")
        #expect(session.entries[0].appearedAt == start)
        #expect(session.secondsRemaining == 20)
        #expect(session.log.first?.message.hasPrefix("SESSION START") == true)
    }

    @Test func startShowsCountdownWithLoggingOnBeforeFirstQuestion() {
        let session = makeSession()
        session.start(at: start)

        #expect(session.phase == .countdown)
        #expect(session.isRunning)
        #expect(session.countdownValue == 3)
        #expect(session.entries.isEmpty)
        #expect(session.log.count == 1)

        session.refresh(at: start.addingTimeInterval(1.5))
        #expect(session.countdownValue == 2)

        session.refresh(at: start.addingTimeInterval(3))
        #expect(session.phase == .playing)
        #expect(session.entries.count == 1)
        #expect(session.entries[0].appearedAt == start.addingTimeInterval(3))
    }

    @Test func startingTwiceDoesNotLogTwice() {
        let session = makeSession()
        session.start(at: start, countdown: 0)
        session.start(at: start.addingTimeInterval(1), countdown: 0)
        #expect(session.entries.count == 1)
    }

    @Test func timerLogsTheNextQuestionWhenTwentySecondsElapse() {
        let session = makeSession()
        session.start(at: start, countdown: 0)

        session.refresh(at: start.addingTimeInterval(19.1))
        #expect(session.entries.count == 1)
        #expect(session.secondsRemaining == 1)

        session.refresh(at: start.addingTimeInterval(20))
        #expect(session.entries.count == 2)
        #expect(session.current?.prompt == "Second prompt")
        #expect(session.secondsRemaining == 20)
        #expect(session.log.contains { $0.message.hasPrefix("TIME UP [1]") })

        session.refresh(at: start.addingTimeInterval(21))
        #expect(session.entries.count == 2)
        #expect(session.secondsRemaining == 19)
    }

    @Test func skippingAheadLogsTheNewQuestion() {
        let session = makeSession()
        session.start(countdown: 0)
        session.advance()
        #expect(session.entries.map(\.prompt) == ["First prompt", "Second prompt"])
        #expect(session.log.contains { $0.message.hasPrefix("NEXT PRESSED [1]") })
    }

    @Test func stopEndsSessionAndSavesLogAutomatically() throws {
        let dir = try tempDirectory()
        let session = makeSession(logDirectory: dir)
        session.start(at: start, countdown: 0)
        session.stop(at: start.addingTimeInterval(7))

        #expect(session.phase == .finished)
        #expect(!session.isRunning)
        #expect(session.log.last?.message.hasPrefix("SESSION STOP — stopped") == true)

        let url = try #require(session.savedLogURL)
        #expect(url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("SESSION START"))
        #expect(saved.contains("First prompt"))
        #expect(saved.contains("SESSION STOP"))
        #expect(session.saveError == nil)
    }

    @Test func stoppingDuringCountdownStillSavesLog() throws {
        let session = makeSession(logDirectory: try tempDirectory())
        session.start(at: start)
        session.stop(at: start.addingTimeInterval(1))

        #expect(session.phase == .finished)
        #expect(session.entries.isEmpty)
        #expect(session.savedLogURL != nil)
    }

    @Test func interviewStopsAtThreeMinutesEvenWithQuestionsLeft() throws {
        let session = QuestionSession(logDirectory: try tempDirectory())
        #expect(QuestionSession.interviewTimeLimit == 180)
        #expect(session.questions.count * QuestionSession.secondsPerQuestion > 180)

        session.start(at: start)                                   // 3s countdown first
        let firstQuestion = start.addingTimeInterval(TimeInterval(QuestionSession.countdownSeconds))
        // Tick like the app does, every 0.1s, until just before the limit.
        var t = start
        while t < firstQuestion.addingTimeInterval(179.9) {
            t = t.addingTimeInterval(0.1)
            session.refresh(at: t)
        }
        #expect(session.phase == .playing)
        #expect(session.interviewSecondsRemaining == 1)

        session.refresh(at: firstQuestion.addingTimeInterval(180))

        #expect(session.phase == .finished)
        #expect(session.entries.count < session.questions.count)
        #expect(session.log.contains { $0.message.hasPrefix("INTERVIEW TIME LIMIT") })
        #expect(session.log.last?.message.hasPrefix("SESSION STOP — time limit reached") == true)
        #expect(session.savedLogURL != nil)
    }

    @Test func timeLimitCountsDownFromFirstQuestionNotStart() {
        let session = QuestionSession(questions: sampleQuestions(), timeLimit: 30)
        session.start(at: start, countdown: 3)
        #expect(session.interviewSecondsRemaining == 30)

        session.refresh(at: start.addingTimeInterval(3))           // first question appears
        session.refresh(at: start.addingTimeInterval(13))
        #expect(session.interviewSecondsRemaining == 20)

        session.restart()   // no-op while running
        session.stop(at: start.addingTimeInterval(14))
        session.restart()
        #expect(session.interviewSecondsRemaining == 30)
    }

    @Test func finishingTheRoundSavesLogWithoutAnExtraQuestion() {
        let session = makeSession()
        session.start(at: start, countdown: 0)
        session.refresh(at: start.addingTimeInterval(20))
        session.refresh(at: start.addingTimeInterval(40))

        #expect(session.phase == .finished)
        #expect(session.entries.count == 2)
        #expect(session.current == nil)
        #expect(session.log.last?.message.hasPrefix("SESSION STOP — round complete") == true)
        #expect(session.savedLogURL != nil)
    }

    @Test func newRoundAfterStopStartsAFreshLog() {
        let session = makeSession()
        session.start(at: start, countdown: 0)
        session.stop(at: start.addingTimeInterval(2))
        session.restart()
        #expect(session.phase == .ready)

        session.start(at: start.addingTimeInterval(10), countdown: 0)
        #expect(session.entries.count == 1)
        #expect(session.log.count == 2)
        #expect(session.savedLogURL == nil)
    }

    @Test func logTextContainsEveryEvent() {
        let session = makeSession()
        session.start(at: start, countdown: 0)
        session.advance(at: start.addingTimeInterval(5))

        let generated = Date(timeIntervalSince1970: 1_700_000_100)
        let text = session.logText(generatedAt: generated)

        #expect(text.contains("Questions shown: 2"))
        #expect(text.contains("SESSION START"))
        #expect(text.contains("NEW QUESTION [1]"))
        #expect(text.contains("First prompt"))
        #expect(text.contains("NEW QUESTION [2]"))
        #expect(text.contains("Second prompt"))
        #expect(text.contains("Warm-up"))
        #expect(text.contains("Easy"))
        #expect(text.contains(QuestionLogFormat.stamp(generated)))
    }

    private func makeSession(logDirectory: URL? = nil) -> QuestionSession {
        let dir = logDirectory ?? (try? tempDirectory())
        return QuestionSession(questions: sampleQuestions(), logDirectory: dir)
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emotional-log-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleQuestions() -> [InterviewQuestion] {
        [
            InterviewQuestion(difficulty: 1, tier: .warmup, prompt: "First prompt"),
            InterviewQuestion(difficulty: 2, tier: .easy, prompt: "Second prompt"),
        ]
    }
}
