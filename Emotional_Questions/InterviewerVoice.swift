//
//  InterviewerVoice.swift
//  Emotional_Questions
//

import AVFoundation

/// Speaks the interviewer's lines out loud with the system text-to-speech voice.
/// Saying a new line cuts off whatever the interviewer was still saying, so each
/// question starts the moment it appears.
@MainActor
final class InterviewerVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    init() {
        // Prefer the best-quality English voice installed on the device.
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        voice = english.max { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality.rawValue < rhs.quality.rawValue }
            // Same quality: prefer US English.
            return lhs.language != "en-US" && rhs.language == "en-US"
        } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func say(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        activateAudio()
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95   // calm, unhurried
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private var audioActive = false

    private func activateAudio() {
        guard !audioActive else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
        audioActive = true
    }
}
