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

    @Test func questionsGetHarderInOrder() {
        let questions = QuestionBank.all
        #expect(questions.map(\.difficulty) == Array(1...questions.count))
        let tiers = questions.map(\.tier)
        #expect(tiers == tiers.sorted())
    }

    @Test func eachQuestionLastsTwentySeconds() {
        #expect(QuestionSession.secondsPerQuestion == 20)
    }

    @Test func startingLogsTheQuestionThatAppears() {
        let session = QuestionSession(questions: sampleQuestions())
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        session.start(at: start)

        #expect(session.entries.count == 1)
        #expect(session.entries[0].number == 1)
        #expect(session.entries[0].prompt == "First prompt")
        #expect(session.entries[0].appearedAt == start)
        #expect(session.secondsRemaining == 20)
    }

    @Test func startingTwiceDoesNotLogTwice() {
        let session = QuestionSession(questions: sampleQuestions())
        session.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        session.start(at: Date(timeIntervalSince1970: 1_700_000_001))
        #expect(session.entries.count == 1)
    }

    @Test func timerLogsTheNextQuestionWhenTwentySecondsElapse() {
        let session = QuestionSession(questions: sampleQuestions())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        session.start(at: start)

        session.refresh(at: start.addingTimeInterval(19.1))
        #expect(session.entries.count == 1)
        #expect(session.secondsRemaining == 1)

        session.refresh(at: start.addingTimeInterval(20))
        #expect(session.entries.count == 2)
        #expect(session.current?.prompt == "Second prompt")
        #expect(session.secondsRemaining == 20)

        session.refresh(at: start.addingTimeInterval(21))
        #expect(session.entries.count == 2)
        #expect(session.secondsRemaining == 19)
    }

    @Test func skippingAheadLogsTheNewQuestion() {
        let session = QuestionSession(questions: sampleQuestions())
        session.start()
        session.advance()
        #expect(session.entries.map(\.prompt) == ["First prompt", "Second prompt"])
    }

    @Test func finishingTheRoundDoesNotLogAnExtraQuestion() {
        let session = QuestionSession(questions: sampleQuestions())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        session.start(at: start)
        session.refresh(at: start.addingTimeInterval(20))
        session.refresh(at: start.addingTimeInterval(40))

        #expect(session.phase == .finished)
        #expect(session.entries.count == 2)
        #expect(session.current == nil)
    }

    @Test func downloadedLogContainsEveryQuestionThatAppeared() {
        let session = QuestionSession(questions: sampleQuestions())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        session.start(at: start)
        session.advance(at: start.addingTimeInterval(5))

        let generated = Date(timeIntervalSince1970: 1_700_000_100)
        let text = session.logText(generatedAt: generated)

        #expect(text.contains("Questions: 2"))
        #expect(text.contains("Question 1"))
        #expect(text.contains("First prompt"))
        #expect(text.contains("Question 2"))
        #expect(text.contains("Second prompt"))
        #expect(text.contains("Warm-up"))
        #expect(text.contains("Easy"))
        #expect(text.contains(QuestionLogFormat.stamp(generated)))
    }

    private func sampleQuestions() -> [InterviewQuestion] {
        [
            InterviewQuestion(difficulty: 1, tier: .warmup, prompt: "First prompt"),
            InterviewQuestion(difficulty: 2, tier: .easy, prompt: "Second prompt"),
        ]
    }
}
