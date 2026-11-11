//
//  ContentView.swift
//  Emotional_Questions
//
//  Created by Prisha Marpu on 10/20/26.
//

import Combine
import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace)    private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow)         private var dismissWindow

    private var session: QuestionSession { appModel.session }

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

                stage
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 560, minHeight: 500)
            .navigationTitle("Emotional Questions")
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        // Stop is always reachable while logging is on. One press ends the session and saves the log.
        .overlay(alignment: .topTrailing) {
            if session.isRunning {
                StopControl(onStop: stopSession)
                    .padding(24)
            }
        }
        .onReceive(clock) { date in
            session.refresh(at: date)
        }
        // The round can also end on its own (last question times out or Finish is pressed).
        .onChange(of: session.phase) { _, phase in
            if phase == .finished {
                Task { await leaveTestRoom() }
            }
        }
    }

    // MARK: - Actions

    private func startSession() {
        session.start()
        Task { await enterTestRoom() }
    }

    private func stopSession() {
        session.stop()   // stops logging and saves the log file automatically
        Task { await leaveTestRoom() }
    }

    private func enterTestRoom() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            // In the room, the timer panel floats above the interviewer, so this
            // window steps aside. The room brings it back when the session ends.
            if session.isRunning {
                appModel.mainWindowHidden = true
                dismissWindow(id: appModel.mainWindowID)
            }
        default:
            appModel.immersiveSpaceState = .closed
        }
    }

    private func leaveTestRoom() async {
        guard appModel.immersiveSpaceState == .open else { return }
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
    }

    // MARK: - Stages

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
                case .countdown:
                    countdownStage
                case .playing:
                    playingStage
                case .finished:
                    finishedStage
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)

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
                Text("Answer out loud. You have twenty seconds for each one, and the interview ends after three minutes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                stat(value: "\(session.questions.count)", caption: "Questions")
                statDivider
                stat(value: "20s", caption: "Each")
                statDivider
                stat(value: "3 min", caption: "Total")
                statDivider
                stat(value: "1–\(session.questions.count)", caption: "Difficulty")
            }
            .padding(.vertical, 6)

            Button(action: startSession) {
                Label("Start", systemImage: "play.fill")
                    .font(.title.weight(.semibold))
                    .frame(minWidth: 300, minHeight: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.extraLarge)
        }
    }

    private var countdownStage: some View {
        VStack(spacing: 20) {
            RecordingBadge()
            Text("Get ready…")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("\(session.countdownValue)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: session.countdownValue)
            Text("Your first question appears in a moment.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var playingStage: some View {
        if let question = session.current {
            let seconds = session.secondsRemaining
            VStack(spacing: 26) {
                RecordingBadge()

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
                    InterviewTimeLeft(seconds: session.interviewSecondsRemaining)
                        .font(.subheadline.weight(.medium))
                }

                // In the interview room the question is spoken in the interviewer's
                // speech bubble; the window only shows it if the room isn't open.
                Group {
                    if appModel.immersiveSpaceState == .open {
                        Label("The interviewer is asking question \(session.index + 1)", systemImage: "bubble.left.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(question.prompt)
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                Text("Session complete")
                    .font(.system(size: 36, weight: .medium, design: .serif))
                Text("\(session.entries.count) of \(session.questions.count) questions shown.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            saveBanner

            Button(action: { session.restart() }) {
                Label("New round", systemImage: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 220, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    private var saveBanner: some View {
        if let url = session.savedLogURL {
            VStack(spacing: 6) {
                Label("Log downloaded", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Files › On My Apple Vision Pro › Emotional_Questions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else if let error = session.saveError {
            Label("Couldn't save the log: \(error)", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
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
}

// MARK: - Start / Stop pieces

struct StopControl: View {
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            Label("Stop", systemImage: "stop.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 110, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .help("End the session and save the log")
    }
}

struct RecordingBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
            Text("Logging")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.red.opacity(0.15), in: Capsule())
        .onAppear { pulse = true }
        .accessibilityLabel("Logging is on")
    }
}

/// "2:45 left" for the whole interview; turns orange in the last 30 seconds.
struct InterviewTimeLeft: View {
    var seconds: Int

    var body: some View {
        let urgent = seconds <= 30
        Label {
            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60)) left")
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: seconds)
        } icon: {
            Image(systemName: "hourglass")
        }
        .foregroundStyle(urgent ? StageStyle.urgent : Color.secondary)
        .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left in the interview")
    }
}

enum StageStyle {
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
        case .countdown:
            "Starting, \(count) questions"
        case .playing:
            "Question \(index + 1) of \(count)"
        case .finished:
            "Round complete, \(count) questions"
        }
    }

    private func fill(for item: Int) -> Color {
        switch phase {
        case .ready, .countdown:
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

struct DifficultyMeter: View {
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

struct CountdownRing: View {
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
        .environment(AppModel())
}
