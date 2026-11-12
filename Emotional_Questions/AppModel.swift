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
    /// The moonlit lake shown for the 1-minute baseline (before) and recovery (after) rests.
    let restSpaceID = "RestSpace"
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

    /// The baseline and recovery rests, with their own log.
    var rest = RestSession()
    /// True while the lake is showing.
    var restSpaceOpen = false
    /// Set when the participant leaves the lake to go straight into the interview room,
    /// so the lake doesn't bring the main window back on its way out.
    var restHandingOffToInterview = false
}
