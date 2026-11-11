//
//  AppModel.swift
//  Emotional_Questions
//
//  Created by Prisha Marpu on 10/20/26.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let mainWindowID = "Main"
    /// True while the main window is put away during a session in the room.
    var mainWindowHidden = false
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// Shared so both the question window and the interview room react to it.
    var session = QuestionSession()
    /// Reads the interviewer's lines aloud in the room.
    @ObservationIgnored let interviewerVoice = InterviewerVoice()
}
