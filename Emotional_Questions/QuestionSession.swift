//
//  QuestionSession.swift
//  Emotional_Questions
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class QuestionSession {
    enum Phase: Equatable {
        case ready
        case playing
        case finished
    }

    static let secondsPerQuestion = 20

    let questions: [InterviewQuestion]
    private(set) var phase: Phase = .ready
    private(set) var index = 0
    private(set) var secondsRemaining = secondsPerQuestion
    private(set) var entries: [QuestionLogEntry] = []
    private var deadline: Date?

    init(questions: [InterviewQuestion] = QuestionBank.all) {
        self.questions = questions
    }

    var current: InterviewQuestion? {
        guard phase == .playing, questions.indices.contains(index) else { return nil }
        return questions[index]
    }

    var isLastQuestion: Bool {
        phase == .playing && index == questions.count - 1
    }

    func start(at date: Date = .now) {
        guard phase == .ready, !questions.isEmpty else { return }
        index = 0
        phase = .playing
        reveal(at: date)
    }

    func advance(at date: Date = .now) {
        guard phase == .playing else { return }
        let next = index + 1
        guard questions.indices.contains(next) else {
            finish()
            return
        }
        index = next
        reveal(at: date)
    }

    func refresh(at date: Date) {
        guard phase == .playing, let deadline else { return }
        let remaining = deadline.timeIntervalSince(date)
        if remaining <= 0 {
            advance(at: date)
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

    func restart() {
        phase = .ready
        index = 0
        secondsRemaining = Self.secondsPerQuestion
        deadline = nil
        entries = []
    }

    func logText(generatedAt: Date = .now) -> String {
        QuestionLogFormat.text(entries: entries, generatedAt: generatedAt)
    }

    private func reveal(at date: Date) {
        deadline = date.addingTimeInterval(TimeInterval(Self.secondsPerQuestion))
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
        QuestionLogger.appeared(entry)
    }

    private func finish() {
        phase = .finished
        deadline = nil
        secondsRemaining = 0
    }
}

nonisolated struct LogFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
