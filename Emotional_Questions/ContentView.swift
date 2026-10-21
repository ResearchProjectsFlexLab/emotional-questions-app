//
//  ContentView.swift
//  Emotional_Questions
//
//  Created by Prisha Marpu on 10/20/26.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var session = QuestionSession()
    @State private var exportText = ""
    @State private var isExporting = false
    @State private var exportStatus: String?

    private let clock = Timer.publish(every: 0.1, tolerance: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                RadialGradient(
                    colors: [StageStyle.accent.opacity(0.20), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 460
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    stage
                    exportStatusText
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 640, minHeight: 560)
            .navigationTitle("Emotional Questions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: beginExport) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(session.entries.isEmpty)
                }
            }
        }
        .onReceive(clock) { date in
            session.refresh(at: date)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: LogFile(text: exportText),
            contentType: .plainText,
            defaultFilename: "emotional-questions"
        ) { result in
            switch result {
            case .success:
                exportStatus = "Saved."
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue {
                    exportStatus = nil
                } else {
                    exportStatus = error.localizedDescription
                }
            }
        }
    }

    private var stage: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 0)

            RoundProgress(
                count: session.questions.count,
                phase: session.phase,
                index: session.index
            )

            Group {
                switch session.phase {
                case .ready:
                    readyStage
                case .playing:
                    playingStage
                case .finished:
                    finishedStage
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyStage: some View {
        VStack(spacing: 28) {
            Image(systemName: "quote.opening")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(StageStyle.accent)
                .frame(width: 72, height: 72)
                .background(StageStyle.accent.opacity(0.14), in: Circle())

            VStack(spacing: 10) {
                Text("\(session.questions.count) questions, each one harder than the last.")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Answer out loud. You have twenty seconds for each one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                stat(value: "\(session.questions.count)", caption: "Questions")
                statDivider
                stat(value: "20s", caption: "Each")
                statDivider
                stat(value: "1–\(session.questions.count)", caption: "Difficulty")
            }
            .padding(.vertical, 6)

            Button(action: { session.start() }) {
                Label("Start round", systemImage: "play.fill")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
    }

    @ViewBuilder
    private var playingStage: some View {
        if let question = session.current {
            let seconds = session.secondsRemaining
            VStack(spacing: 26) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    CountdownRing(
                        fraction: session.fractionRemaining(at: timeline.date),
                        seconds: seconds,
                        urgent: seconds <= 5
                    )
                }

                VStack(spacing: 10) {
                    Text("Question \(session.index + 1) of \(session.questions.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        DifficultyMeter(current: question.tier)
                        Text(question.tier.title)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Text(question.prompt)
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                    .id(session.index)
                    .transition(.opacity)

                Button(action: { session.advance() }) {
                    Label(
                        session.isLastQuestion ? "Finish" : "Next question",
                        systemImage: session.isLastQuestion ? "flag.checkered" : "forward.fill"
                    )
                    .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
            .animation(.smooth(duration: 0.35), value: session.index)
        }
    }

    private var finishedStage: some View {
        VStack(spacing: 26) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(StageStyle.accent)
                .frame(width: 72, height: 72)
                .background(StageStyle.accent.opacity(0.14), in: Circle())

            VStack(spacing: 10) {
                Text("Round complete")
                    .font(.system(size: 36, weight: .medium, design: .serif))
                Text("\(session.entries.count) questions. Save a copy, or start a new round.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(action: beginExport) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .disabled(session.entries.isEmpty)

                Button(action: startOver) {
                    Label("New round", systemImage: "arrow.counterclockwise")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
        }
    }

    private func stat(value: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 36)
    }

    @ViewBuilder
    private var exportStatusText: some View {
        if let exportStatus {
            Text(exportStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func beginExport() {
        guard !session.entries.isEmpty else { return }
        exportText = session.logText()
        isExporting = true
    }

    private func startOver() {
        session.restart()
        exportStatus = nil
    }
}

private enum StageStyle {
    static let accent = Color(red: 0.33, green: 0.42, blue: 0.96)
    static let urgent = Color(red: 0.92, green: 0.42, blue: 0.28)
}

private struct RoundProgress: View {
    var count: Int
    var phase: QuestionSession.Phase
    var index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { item in
                Capsule()
                    .fill(fill(for: item))
                    .frame(width: width(for: item), height: 8)
            }
        }
        .animation(.snappy(duration: 0.35), value: index)
        .animation(.snappy(duration: 0.35), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch phase {
        case .ready:
            "Ready to start, \(count) questions"
        case .playing:
            "Question \(index + 1) of \(count)"
        case .finished:
            "Round complete, \(count) questions"
        }
    }

    private func fill(for item: Int) -> Color {
        switch phase {
        case .ready:
            Color.primary.opacity(0.28)
        case .finished:
            StageStyle.accent
        case .playing where item < index:
            StageStyle.accent.opacity(0.55)
        case .playing where item == index:
            StageStyle.accent
        default:
            Color.primary.opacity(0.22)
        }
    }

    private func width(for item: Int) -> CGFloat {
        phase == .playing && item == index ? 26 : 14
    }
}

private struct DifficultyMeter: View {
    var current: Difficulty

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Difficulty.allCases, id: \.self) { tier in
                Capsule()
                    .fill(tier <= current ? StageStyle.accent : Color.primary.opacity(0.14))
                    .frame(width: tier == current ? 18 : 8, height: 6)
            }
        }
        .accessibilityLabel("\(current.title), difficulty \(current.rawValue) of \(Difficulty.allCases.count)")
    }
}

private struct CountdownRing: View {
    var fraction: Double
    var seconds: Int
    var urgent: Bool

    private var ink: Color {
        urgent ? StageStyle.urgent : StageStyle.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(ink.opacity(0.08))
                .padding(16)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(ink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ink.opacity(0.35), radius: 6, y: 1)

            VStack(spacing: 0) {
                Text("\(seconds)")
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? ink : Color.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: seconds)
                Text("sec")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.1)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seconds) seconds remaining")
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
