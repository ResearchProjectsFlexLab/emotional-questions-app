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
            ViewThatFits(in: .horizontal) {
                panel(sideBySide: true)
                panel(sideBySide: false)
            }
            .padding(28)
            .frame(minWidth: 820, minHeight: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Emotional Questions")
        }
        .onReceive(clock) { date in
            session.refresh(at: date)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: LogFile(text: exportText),
            contentType: .plainText,
            defaultFilename: "emotional-question-log"
        ) { result in
            switch result {
            case .success:
                exportStatus = "Log saved."
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

    private func panel(sideBySide: Bool) -> some View {
        let stack = sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return stack {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            logPanel
                .frame(maxWidth: sideBySide ? 340 : .infinity, maxHeight: sideBySide ? .infinity : 300)
        }
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: 22) {
            progressHeader

            switch session.phase {
            case .ready:
                readyStage
            case .playing:
                playingStage
            case .finished:
                finishedStage
            }

            Spacer(minLength: 0)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Emotional Gauntlet")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(session.entries.count) of \(session.questions.count) logged")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(session.entries.count),
                total: Double(max(session.questions.count, 1))
            )
            .accessibilityLabel("Questions logged")
        }
    }

    private var readyStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(session.questions.count) questions. Twenty seconds each. Every question is harder than the last.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Answer out loud. When a question appears, it is written to the session log.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { session.start() }) {
                Label("Start round", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var playingStage: some View {
        if let question = session.current {
            let seconds = session.secondsRemaining
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 24) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        CountdownRing(
                            fraction: session.fractionRemaining(at: timeline.date),
                            seconds: seconds,
                            urgent: seconds <= 5
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Question \(session.index + 1) of \(session.questions.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        tierPips(current: question.tier)
                        Text("\(question.tier.title) · difficulty \(question.difficulty)")
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                }

                Text(question.prompt)
                    .font(.title2)
                    .fixedSize(horizontal: false, vertical: true)

                if let latest = session.entries.last {
                    Label(
                        "Logged question \(latest.number) at \(latest.appearedAt.formatted(date: .omitted, time: .standard))",
                        systemImage: "text.badge.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button(action: { session.advance() }) {
                    Label(
                        session.isLastQuestion ? "Finish" : "Next question",
                        systemImage: session.isLastQuestion ? "flag.checkered" : "forward.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var finishedStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Round complete")
                .font(.title.weight(.semibold))
            Text("\(session.entries.count) questions appeared, and each one is in the log. Save it before you start a new round.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: beginExport) {
                    Label("Download log", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.entries.isEmpty)

                Button(action: startOver) {
                    Label("New round", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            exportStatusText
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session log")
                    .font(.headline)
                Spacer()
                Text("\(session.entries.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Written each time a question appears.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: beginExport) {
                Label("Download log", systemImage: "arrow.down.doc")
            }
            .disabled(session.entries.isEmpty)

            exportStatusText

            Divider()

            if session.entries.isEmpty {
                Text("The first question will show up here as soon as the round starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(session.entries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                                if entry.id != session.entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .onChange(of: session.entries.count) { _, _ in
                        guard let id = session.entries.last?.id else { return }
                        withAnimation(.snappy) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func logRow(_ entry: QuestionLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Q\(entry.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(entry.tier)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(entry.appearedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(entry.prompt)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tierPips(current: Difficulty) -> some View {
        HStack(spacing: 6) {
            ForEach(Difficulty.allCases, id: \.self) { tier in
                Text(tier.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(tier == current ? Color.primary : Color.secondary)
                    .background(
                        tier == current
                            ? Color.accentColor.opacity(0.22)
                            : Color.primary.opacity(tier < current ? 0.08 : 0.04),
                        in: Capsule()
                    )
            }
        }
    }

    @ViewBuilder
    private var exportStatusText: some View {
        if let exportStatus {
            Text(exportStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct CountdownRing: View {
    var fraction: Double
    var seconds: Int
    var urgent: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    urgent ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(seconds)")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: seconds)
                Text("sec")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seconds) seconds remaining")
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
