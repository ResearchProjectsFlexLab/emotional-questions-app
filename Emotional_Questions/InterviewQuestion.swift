//
//  InterviewQuestion.swift
//  Emotional_Questions
//

import Foundation
import os

enum Difficulty: Int, CaseIterable, Comparable {
    case warmup = 1
    case easy
    case medium
    case hard
    case expert

    var title: String {
        switch self {
        case .warmup: "Warm-up"
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        }
    }

    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct InterviewQuestion: Identifiable, Equatable {
    let id = UUID()
    let difficulty: Int
    let tier: Difficulty
    let prompt: String
}

enum QuestionBank {
    /// Ordered so each prompt is strictly harder than the one before it.
    static let all: [InterviewQuestion] = [
        InterviewQuestion(
            difficulty: 1,
            tier: .warmup,
            prompt: "Do you have dreams?"
        ),
        InterviewQuestion(
            difficulty: 2,
            tier: .warmup,
            prompt: "What makes you feel happy?"
        ),
        InterviewQuestion(
            difficulty: 3,
            tier: .warmup,
            prompt: "Who do you miss?"
        ),
        InterviewQuestion(
            difficulty: 4,
            tier: .easy,
            prompt: "Do you have regrets?"
        ),
        InterviewQuestion(
            difficulty: 5,
            tier: .easy,
            prompt: "What are you afraid of?"
        ),
        InterviewQuestion(
            difficulty: 6,
            tier: .easy,
            prompt: "When did you last feel proud of yourself?"
        ),
        InterviewQuestion(
            difficulty: 7,
            tier: .medium,
            prompt: "What is something you wish you had said to someone?"
        ),
        InterviewQuestion(
            difficulty: 8,
            tier: .medium,
            prompt: "When do you feel most alone?"
        ),
        InterviewQuestion(
            difficulty: 9,
            tier: .medium,
            prompt: "Who has hurt you, and have you forgiven them?"
        ),
        InterviewQuestion(
            difficulty: 10,
            tier: .hard,
            prompt: "What do you still carry that you wish you could put down?"
        ),
        InterviewQuestion(
            difficulty: 11,
            tier: .hard,
            prompt: "What part of yourself do you hide from other people?"
        ),
        InterviewQuestion(
            difficulty: 12,
            tier: .hard,
            prompt: "When did you last feel like you were not enough?"
        ),
        InterviewQuestion(
            difficulty: 13,
            tier: .expert,
            prompt: "If you could forgive yourself for one thing, what would it be?"
        ),
        InterviewQuestion(
            difficulty: 14,
            tier: .expert,
            prompt: "What would you want the people you love to know if you could not tell them tomorrow?"
        ),
        InterviewQuestion(
            difficulty: 15,
            tier: .expert,
            prompt: "What feeling have you been avoiding, and what would happen if you let yourself feel it?"
        ),
    ]
}

struct QuestionLogEntry: Identifiable, Equatable {
    let id = UUID()
    let number: Int
    let appearedAt: Date
    let tier: String
    let difficulty: Int
    let prompt: String
}

enum QuestionLogFormat {
    static func text(entries: [QuestionLogEntry], generatedAt: Date) -> String {
        var lines = [
            "Emotional Questions",
            "Generated: \(stamp(generatedAt))",
            "Questions: \(entries.count)",
            "",
        ]

        for entry in entries {
            lines.append(
                "Question \(entry.number) | \(stamp(entry.appearedAt)) | \(entry.tier) | difficulty \(entry.difficulty)"
            )
            lines.append(entry.prompt)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false))
    }
}

enum QuestionLogger {
    private static let logger = Logger(subsystem: "FlexLab.Emotional-Questions", category: "QuestionLog")

    static func roundStarted(questionCount: Int) {
        logger.info("Round started | \(questionCount, privacy: .public) questions")
    }

    static func appeared(_ entry: QuestionLogEntry) {
        let number = entry.number
        let tier = entry.tier
        let difficulty = entry.difficulty
        let prompt = entry.prompt
        logger.info(
            "Question \(number, privacy: .public) appeared | \(tier, privacy: .public) | difficulty \(difficulty, privacy: .public) | \(prompt, privacy: .public)"
        )
    }

    static func roundFinished(questionCount: Int) {
        logger.info("Round finished | \(questionCount, privacy: .public) questions")
    }
}
