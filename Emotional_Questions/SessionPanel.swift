//
//  SessionPanel.swift
//  Emotional_Questions
//

import SwiftUI

/// The compact timer panel shown in the interview room, floating above the
/// interviewer and their speech bubble. It carries everything the main window
/// shows during a session except the question itself (that's in the bubble):
/// logging status, countdown, timer, question number, difficulty, Next and Stop.
struct SessionPanel: View {
    static let attachmentID = "sessionPanel"
    /// Fixed frame with content pinned to the bottom, so the panel's bottom edge
    /// stays just above the interviewer's head whatever it's showing.
    static let frameSize = CGSize(width: 620, height: 360)
    /// How much larger the panel is drawn in the room.
    static let roomScale: Float = 1.5

    @Environment(AppModel.self) private var appModel
    private var session: QuestionSession { appModel.session }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                RecordingBadge()
                Spacer()
                StopControl(onStop: { session.stop() })
            }

            switch session.phase {
            case .countdown:
                countdown
            case .playing:
                if let question = session.current {
                    playing(question)
                }
            case .ready, .finished:
                EmptyView()
            }
        }
        .padding(30)
        .frame(width: Self.frameSize.width)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .frame(width: Self.frameSize.width, height: Self.frameSize.height, alignment: .bottom)
        .animation(.smooth(duration: 0.3), value: session.phase)
    }

    private var countdown: some View {
        HStack(spacing: 14) {
            Text("Get ready…")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("\(session.countdownValue)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: session.countdownValue)
        }
        .frame(maxWidth: .infinity)
    }

    private func playing(_ question: InterviewQuestion) -> some View {
        let seconds = session.secondsRemaining
        return VStack(spacing: 18) {
            HStack(spacing: 24) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    CountdownRing(
                        fraction: session.fractionRemaining(at: timeline.date),
                        seconds: seconds,
                        urgent: seconds <= 5
                    )
                }
                .scaleEffect(0.95)
                .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Question \(session.index + 1) of \(session.questions.count)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    HStack(spacing: 8) {
                        DifficultyMeter(current: question.tier)
                        Text(question.tier.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    InterviewTimeLeft(seconds: session.interviewSecondsRemaining)
                        .font(.title3.weight(.medium))
                }
                Spacer(minLength: 0)
            }

            Button(action: { session.advance() }) {
                Label(
                    session.isLastQuestion ? "Finish" : "Next question",
                    systemImage: session.isLastQuestion ? "flag.checkered" : "forward.fill"
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
    }
}
