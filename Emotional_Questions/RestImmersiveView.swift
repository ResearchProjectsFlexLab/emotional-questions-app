//
//  RestImmersiveView.swift
//  Emotional_Questions
//
//  The baseline and recovery rests, the same as in the Follow the Snake app: full immersion
//  under a starry night sky by a moonlit lake. Before the baseline an instructions card with a
//  Start baseline button is shown; during each 1-minute rest only gentle breathing words (first
//  three breaths) and a faint progress line appear. The moon's glow and ripples follow the
//  breathing pace (2 s in, 3 s out).
//
//  After the baseline the interview starts automatically. After the interview the recovery
//  starts automatically, then the window comes back.
//
//  Cards are RealityView attachments (rather than ViewAttachmentComponent) so this runs on visionOS 2.
//

import RealityKit
import SwiftUI

struct RestImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var lake: LakeScene?
    @State private var updates: EventSubscription?
    @State private var leaving = false
    @State private var lastSync: Date?

    private static let cardID = "baselineInstructions"
    private static let hudID = "restHUD"

    private var rest: RestSession { appModel.rest }

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            // Night sky dome and stars.
            root.addChild(LakeScene.makeSkyDome())
            root.addChild(LakeScene.makeStars(count: 700, radius: 30))
            let lake = LakeScene()
            lake.root.components.set(OpacityComponent(opacity: 0))
            root.addChild(lake.root)
            if let card = attachments.entity(for: Self.cardID) {
                card.position = [0, 1.15, -1.6]
                root.addChild(card)
            }
            if let hud = attachments.entity(for: Self.hudID) {
                hud.position = [0, 0.95, -2.6]
                root.addChild(hud)
            }
            content.add(root)
            self.lake = lake
            // Sync every rendered frame rather than relying on SwiftUI observation.
            updates = content.subscribe(to: SceneEvents.Update.self) { _ in
                sync()
            }
        } update: { _, attachments in
            attachments.entity(for: Self.cardID)?.isEnabled = rest.kind == .baseline && rest.phase == .ready && !leaving
            attachments.entity(for: Self.hudID)?.isEnabled = rest.isResting
        } attachments: {
            Attachment(id: Self.cardID) {
                BaselineInstructionsCard(onStart: { rest.start() })
            }
            Attachment(id: Self.hudID) {
                RestHUD(rest: rest)
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            appModel.restSpaceOpen = true
            // The recovery follows the interview straight away, with no card.
            if rest.kind == .recovery, rest.phase == .ready {
                rest.start()
            }
        }
        .onDisappear {
            appModel.restSpaceOpen = false
            updates?.cancel()
            updates = nil
            // Pressing the Digital Crown ends the rest early; what was recorded is still saved.
            rest.cutShort(reason: "exited_immersive")
            if appModel.restHandingOffToInterview {
                appModel.restHandingOffToInterview = false
            } else if appModel.mainWindowHidden {
                appModel.mainWindowHidden = false
                openWindow(id: appModel.mainWindowID)
            }
        }
        .onChange(of: rest.phase) { _, phase in
            guard phase == .done, !leaving else { return }
            leaving = true
            if rest.kind == .baseline {
                goToInterview()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    await dismissImmersiveSpace()
                }
            }
        }
    }

    private func sync() {
        let now = Date()
        let dt = Float(min(0.1, now.timeIntervalSince(lastSync ?? now)))
        lastSync = now
        rest.refresh(at: now)
        guard let lake else { return }
        Self.fade(lake.root, toward: leaving ? 0 : 1, dt: dt)
        if lake.root.isEnabled { lake.update(rest: rest, now: now) }
    }

    private static func fade(_ entity: Entity, toward target: Float, dt: Float) {
        let current: Float = entity.components[OpacityComponent.self]?.opacity ?? 1
        let step: Float = dt * 1.5
        let next: Float = current < target ? min(target, current + step) : max(target, current - step)
        entity.components.set(OpacityComponent(opacity: next))
        entity.isEnabled = next > 0.001
    }

    /// Baseline done: go straight into the interview room (its own 3-2-1 countdown runs as usual).
    private func goToInterview() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            appModel.restHandingOffToInterview = true
            await dismissImmersiveSpace()
            appModel.session.start()
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                appModel.mainWindowHidden = true
            default:
                // The room couldn't open: run the interview in the main window instead.
                appModel.immersiveSpaceState = .closed
                appModel.mainWindowHidden = false
                openWindow(id: appModel.mainWindowID)
            }
        }
    }
}

/// Shown in the lake scene before the baseline: what to do, and a button to begin.
/// Same as the Follow the Snake app.
struct BaselineInstructionsCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Before we begin")
                .font(.largeTitle.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Label("Sit comfortably with your back supported.", systemImage: "chair")
                Label("Rest your hands on your lap and keep still.", systemImage: "hand.raised")
                Label("Look at the moon's reflection on the water.", systemImage: "moon.stars")
                Label("Breathe gently as the moonlight glows and fades.", systemImage: "wind")
            }
            .font(.title3)
            Text("This lasts 1 minute. The interview starts automatically afterwards.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(action: onStart) {
                Label("Start baseline", systemImage: "play.fill")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .buttonBorderShape(.capsule)
        }
        .padding(36)
        .frame(width: 720)
        .glassBackgroundEffect()
    }
}

/// Gentle breathing words for the first few breaths of each rest, then only a faint progress line.
/// Same as the Follow the Snake app.
struct RestHUD: View {
    let rest: RestSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = rest.elapsed(at: context.date)
            let showWords = elapsed < RestSession.breathCycle * 3
            VStack(spacing: 16) {
                Text(rest.kind == .recovery ? "Recovery — relax and breathe" : "Baseline — relax and breathe")
                    .font(.title2)
                    .opacity(elapsed < 6 ? 0.85 : 0)
                Text(rest.isInhaling(at: context.date) ? "Breathe in…" : "Breathe out…")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .opacity(showWords ? 0.8 : 0)
                ProgressView(value: rest.progress(at: context.date))
                    .tint(.teal)
                    .frame(width: 320)
                    .opacity(0.35)
            }
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 1.2), value: showWords)
            .animation(.easeInOut(duration: 0.8), value: rest.isInhaling(at: context.date))
        }
    }
}
