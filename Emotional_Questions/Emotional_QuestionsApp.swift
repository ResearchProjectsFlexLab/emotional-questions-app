//
//  Emotional_QuestionsApp.swift
//  Emotional_Questions
//
//  Created by Prisha Marpu on 10/20/26.
//

import SwiftUI
import RealityKit

@main
struct Emotional_QuestionsApp: App {

    @State private var appModel = AppModel()

    init() {
        InterviewerComponent.registerComponent()
        InterviewerSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 680, height: 620)
        // Sit the question window low and close, like papers on the desk,
        // so the interviewer across the desk stays in view.
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        // The moonlit lake for the baseline and recovery minutes.
        ImmersiveSpace(id: appModel.restSpaceID) {
            RestImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
