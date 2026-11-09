//
//  ImmersiveView.swift
//  Emotional_Questions
//
//  Created by Prisha Marpu on 10/20/26.
//

import SwiftUI
import RealityKit
import CoreGraphics
import Combine

/// A formal interview office shown around the participant while the session runs.
/// The participant sits at a desk facing a seated interviewer, with a city view
/// through the window behind them. The interviewer breathes, blinks and nods
/// each time a new question appears. Everything is built from simple shapes,
/// so no 3D assets are needed.
///
/// Coordinates: the participant is at the origin (floor level), looking down -z.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var interviewer: Entity?

    private var session: QuestionSession { appModel.session }

    var body: some View {
        RealityView { content, attachments in
            let room = InterviewRoom.make()
            content.add(room.root)
            interviewer = room.interviewer
            if let light = await InterviewRoom.makeAmbientLight() {
                room.root.components.set(light)
            }

            // Layout around the interviewer's head (mouth ≈ 1.27 m, centred on x = 0).
            // Attachments are measured in points; ~1360 pt make one metre.
            let pointsPerMeter: Float = 1360

            // Speech bubble: beside the face on the right, its tail tip at mouth
            // height pointing back at the interviewer. Always faces the participant.
            let bubbleBottom: Float = 1.27
            let bubbleHeight = Float(SpeechBubble.frameSize.height) / pointsPerMeter
            if let bubble = attachments.entity(for: SpeechBubble.attachmentID) {
                let width = Float(SpeechBubble.frameSize.width) / pointsPerMeter
                let left: Float = 0.15
                bubble.position = [left + width / 2, bubbleBottom + bubbleHeight / 2, -1.75]
                bubble.components.set(BillboardComponent())
                room.root.addChild(bubble)
            }

            // Timer panel: above the interviewer's head, its bottom edge just clear of
            // the top of the speech bubble. The panel's frame is a fixed size with its
            // content pinned to the bottom, so the bottom edge stays put as content changes.
            if let panel = attachments.entity(for: SessionPanel.attachmentID) {
                let scale = SessionPanel.roomScale
                let height = Float(SessionPanel.frameSize.height) / pointsPerMeter * scale
                let panelBottom = bubbleBottom + bubbleHeight + 0.04
                panel.scale = SIMD3(repeating: scale)
                panel.position = [0, panelBottom + height / 2, -1.95]
                panel.components.set(BillboardComponent())
                room.root.addChild(panel)
            }
        } attachments: {
            Attachment(id: SpeechBubble.attachmentID) {
                SpeechBubble(text: bubbleText, key: bubbleKey)
            }
            Attachment(id: SessionPanel.attachmentID) {
                SessionPanel()
                    .environment(appModel)
            }
        }
        // The main window is hidden while in the room, so the room keeps the timer ticking.
        .onReceive(clock) { date in
            session.refresh(at: date)
        }
        .onChange(of: session.index) { nod() }
        .onChange(of: session.phase) { _, phase in
            if phase == .playing || phase == .finished { nod() }
            if phase == .finished { Task { await leaveRoom() } }
        }
    }

    private let clock = Timer.publish(every: 0.1, tolerance: 0.02, on: .main, in: .common).autoconnect()

    /// Session over (Stop, Finish, or the last question timed out): bring back the
    /// main window with the results and saved-log message, then close the room
    /// after the interviewer's closing line has had a moment on screen.
    private func leaveRoom() async {
        if appModel.mainWindowHidden {
            appModel.mainWindowHidden = false
            openWindow(id: appModel.mainWindowID)
        }
        try? await Task.sleep(for: .seconds(1.5))
        guard appModel.immersiveSpaceState == .open, !session.isRunning else { return }
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
    }

    /// What the interviewer is "saying" right now.
    private var bubbleText: String? {
        switch session.phase {
        case .ready:     return nil
        case .countdown: return "Thanks for coming in today. Let's begin."
        case .playing:   return session.current?.prompt
        case .finished:  return "Thank you, that's everything for today."
        }
    }

    /// Changes whenever a new line is spoken, so the bubble animates in again.
    private var bubbleKey: String {
        switch session.phase {
        case .playing: return "q\(session.index)"
        default:       return "\(session.phase)"
        }
    }

    private func nod() {
        guard let interviewer, var rig = interviewer.components[InterviewerComponent.self] else { return }
        rig.nodStart = rig.time
        interviewer.components.set(rig)
    }
}

// MARK: - Speech bubble

/// The interviewer's line, shown as a comic-style speech bubble in the room.
/// Sized to read comfortably from the participant's seat about two metres away.
struct SpeechBubble: View {
    static let attachmentID = "speechBubble"
    /// Fixed frame; the bubble is pinned to its bottom-left corner (the tail).
    static let frameSize = CGSize(width: 760, height: 400)

    let text: String?
    let key: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let text {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 46, weight: .medium, design: .serif))
                        .foregroundStyle(Color(white: 0.1))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 36)
                        .frame(width: 760, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 48, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

                    // Tail pointing down and left, toward the interviewer's head.
                    BubbleTail()
                        .fill(Color.white)
                        .frame(width: 90, height: 70)
                        .padding(.leading, 70)
                        .offset(y: -1)
                }
                .id(key)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .frame(width: Self.frameSize.width, height: Self.frameSize.height, alignment: .bottomLeading)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: key)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.map { "Interviewer: \($0)" } ?? "")
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                       control: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.45))
        p.closeSubpath()
        return p
    }
}

// MARK: - Interviewer animation

/// State for the interviewer's idle animation (breathing, blinking, small head
/// movements) and the nod that plays when a new question appears.
struct InterviewerComponent: Component {
    var time: Float = 0
    var nodStart: Float? = nil
    var nextBlink: Float = 2.5
    var blinkStart: Float? = nil
}

struct InterviewerSystem: System {
    static let query = EntityQuery(where: .has(InterviewerComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var rig = entity.components[InterviewerComponent.self] else { continue }
            rig.time += dt
            let t = rig.time

            // Breathing: the upper body rises and falls very slightly.
            if let torso = entity.findEntity(named: "upperBody") {
                let breath = sin(t * 2 * .pi / 4.2)
                torso.scale = [1 + 0.006 * breath, 1 + 0.012 * breath, 1 + 0.008 * breath]
            }

            // Head: slow, small drift plus a nod when a question appears.
            if let head = entity.findEntity(named: "headPivot") {
                let yaw = 0.05 * sin(t * 0.31) + 0.02 * sin(t * 0.83)
                var pitch = 0.025 * sin(t * 0.47)
                let tilt = 0.02 * sin(t * 0.23)
                if let start = rig.nodStart {
                    let p = (t - start) / 1.1
                    if p >= 1 {
                        rig.nodStart = nil
                    } else {
                        // Two gentle dips, the second smaller.
                        pitch += 0.16 * sin(p * 2 * .pi) * (1 - p) * (sin(p * 2 * .pi) > 0 ? 1 : 0.5)
                    }
                }
                head.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                    * simd_quatf(angle: pitch, axis: [1, 0, 0])
                    * simd_quatf(angle: tilt, axis: [0, 0, 1])
            }

            // Blinking every few seconds.
            if rig.blinkStart == nil, t >= rig.nextBlink {
                rig.blinkStart = t
            }
            var eyeOpen: Float = 1
            if let start = rig.blinkStart {
                let p = (t - start) / 0.16
                if p >= 1 {
                    rig.blinkStart = nil
                    rig.nextBlink = t + Float.random(in: 2.5...5.5)
                } else {
                    eyeOpen = max(0.08, abs(1 - 2 * p))
                }
            }
            for name in ["eyeL", "eyeR"] {
                if let eye = entity.findEntity(named: name) {
                    eye.scale = [1, eyeOpen, 1]
                }
            }

            entity.components.set(rig)
        }
    }
}

// MARK: - Room

enum InterviewRoom {

    struct Built {
        let root: Entity
        let interviewer: Entity
    }

    static func make() -> Built {
        let root = Entity()
        root.name = "InterviewRoom"

        addShell(to: root)
        addWindowView(to: root)
        addLights(to: root)
        addDesk(to: root)
        addFurniture(to: root)

        let interviewer = makeInterviewer()
        interviewer.position = [0, 0, -1.85]
        root.addChild(interviewer)

        return Built(root: root, interviewer: interviewer)
    }

    /// Soft, even ambient light so shaded surfaces never go black.
    static func makeAmbientLight() async -> ImageBasedLightComponent? {
        guard let image = ambientGradient(),
              let resource = try? await EnvironmentResource(equirectangular: image) else { return nil }
        return ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.4)
    }

    // MARK: Walls, floor, ceiling

    private static let roomHalfWidth: Float = 3.6
    private static let backWallZ: Float = -4.2
    private static let frontWallZ: Float = 2.8
    private static let ceiling: Float = 2.9

    private static func addShell(to root: Entity) {
        let wall = pbr(0.86, 0.84, 0.80, rough: 0.9)
        let accentWall = pbr(0.36, 0.42, 0.48, rough: 0.85)
        let depth = frontWallZ - backWallZ
        let midZ = (frontWallZ + backWallZ) / 2

        // Floor: warm oak boards, with a darker rug under the desk.
        let floor = box([roomHalfWidth * 2, 0.02, depth], pbr(0.52, 0.38, 0.26, rough: 0.7), at: [0, -0.01, midZ])
        root.addChild(floor)
        for i in stride(from: -roomHalfWidth + 0.18, to: roomHalfWidth, by: 0.36) {
            root.addChild(box([0.004, 0.001, depth], pbr(0.40, 0.29, 0.20, rough: 0.8), at: [i, 0.0005, midZ]))
        }
        root.addChild(box([3.0, 0.012, 3.0], pbr(0.30, 0.33, 0.38, rough: 1), at: [0, 0.006, -1.3]))
        root.addChild(box([2.8, 0.013, 2.8], pbr(0.38, 0.41, 0.46, rough: 1), at: [0, 0.007, -1.3]))

        // Ceiling with recessed light panels.
        root.addChild(box([roomHalfWidth * 2, 0.02, depth], pbr(0.93, 0.93, 0.92, rough: 1), at: [0, ceiling, midZ]))
        for x: Float in [-1.6, 1.6] {
            for z: Float in [-2.6, -0.4, 1.6] {
                root.addChild(box([0.6, 0.01, 0.6], unlit(1.0, 0.98, 0.93), at: [x, ceiling - 0.015, z]))
            }
        }

        // Side and front walls.
        root.addChild(box([0.05, ceiling, depth], wall, at: [-roomHalfWidth, ceiling / 2, midZ]))
        root.addChild(box([0.05, ceiling, depth], accentWall, at: [roomHalfWidth, ceiling / 2, midZ]))
        root.addChild(box([roomHalfWidth * 2, ceiling, 0.05], wall, at: [0, ceiling / 2, frontWallZ]))

        // Skirting boards.
        let trim = pbr(0.95, 0.95, 0.94, rough: 0.6)
        root.addChild(box([0.02, 0.1, depth], trim, at: [-roomHalfWidth + 0.03, 0.05, midZ]))
        root.addChild(box([0.02, 0.1, depth], trim, at: [roomHalfWidth - 0.03, 0.05, midZ]))

        // Back wall, built around a wide window opening.
        let sill: Float = 0.85, head: Float = 2.55, halfOpening: Float = 2.4
        root.addChild(box([roomHalfWidth * 2, sill, 0.1], wall, at: [0, sill / 2, backWallZ]))
        root.addChild(box([roomHalfWidth * 2, ceiling - head, 0.1], wall, at: [0, (head + ceiling) / 2, backWallZ]))
        let sideWidth = roomHalfWidth - halfOpening
        for side: Float in [-1, 1] {
            root.addChild(box([sideWidth, head - sill, 0.1], wall,
                              at: [side * (halfOpening + sideWidth / 2), (sill + head) / 2, backWallZ]))
        }

        // Window frame and mullions.
        let frame = pbr(0.18, 0.19, 0.21, rough: 0.4, metal: 0.6)
        root.addChild(box([halfOpening * 2, 0.06, 0.14], frame, at: [0, sill, backWallZ]))
        root.addChild(box([halfOpening * 2, 0.06, 0.14], frame, at: [0, head, backWallZ]))
        for x in stride(from: -halfOpening, through: halfOpening, by: halfOpening / 2) {
            root.addChild(box([0.06, head - sill, 0.14], frame, at: [x, (sill + head) / 2, backWallZ]))
        }
        root.addChild(box([halfOpening * 2, 0.04, 0.12], frame, at: [0, 1.95, backWallZ]))
    }

    // MARK: View out of the window

    private static func addWindowView(to root: Entity) {
        // Sky.
        let skyZ: Float = -60
        let bands: [(Float, SIMD3<Float>)] = [
            (-6, [0.80, 0.86, 0.92]), (6, [0.74, 0.83, 0.93]), (18, [0.62, 0.76, 0.92]), (30, [0.52, 0.69, 0.90]),
        ]
        for (y, c) in bands {
            root.addChild(box([160, 12.5, 0.1], unlit(c.x, c.y, c.z), at: [0, y, skyZ]))
        }

        // City skyline: rows of towers, lighter (hazier) the further away.
        var rng = SeededRandom(seed: 7)
        let rows: [(z: Float, shade: Float, count: Int, height: ClosedRange<Float>)] = [
            (-50, 0.70, 26, 8...26), (-38, 0.60, 22, 6...20), (-26, 0.50, 16, 4...14), (-16, 0.42, 10, 3...9),
        ]
        for row in rows {
            let span: Float = 120
            for i in 0..<row.count {
                let w = Float(rng.next(in: 2.5...6))
                let h = Float(rng.next(in: Double(row.height.lowerBound)...Double(row.height.upperBound)))
                let x = -span / 2 + span * (Float(i) + 0.5) / Float(row.count) + Float(rng.next(in: -1.5...1.5))
                let s = row.shade + Float(rng.next(in: -0.05...0.05))
                let tower = box([w, h, w], unlit(s * 0.92, s * 0.96, s * 1.05), at: [x, h / 2 - 6, row.z])
                root.addChild(tower)
                // A few lit window strips on the nearer towers.
                if row.z > -30 {
                    var y: Float = 1.2
                    while y < h - 0.6 {
                        root.addChild(box([w * 0.8, 0.12, 0.02], unlit(s + 0.18, s + 0.2, s + 0.16),
                                          at: [x, y - 6, row.z + w / 2 + 0.02]))
                        y += 1.1
                    }
                }
            }
        }
        // Ground plane outside, below the building.
        root.addChild(box([200, 0.1, 60], unlit(0.42, 0.45, 0.48), at: [0, -6, -35]))
    }

    // MARK: Lights

    private static func addLights(to root: Entity) {
        // Daylight coming in from the window, slightly from above.
        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: .init(red: 1, green: 0.97, blue: 0.92, alpha: 1),
                                                     intensity: 2600))
        sun.look(at: [0.5, 0, 1.5], from: [0, 3, -4], relativeTo: nil)
        root.addChild(sun)

        // Ceiling lights.
        for p: SIMD3<Float> in [[-1.6, 2.7, -2.6], [1.6, 2.7, -2.6], [0, 2.7, -0.6], [0, 2.7, 1.4]] {
            let lamp = Entity()
            lamp.position = p
            lamp.components.set(PointLightComponent(color: .init(red: 1, green: 0.96, blue: 0.9, alpha: 1),
                                                    intensity: 18000, attenuationRadius: 6))
            root.addChild(lamp)
        }
    }

    // MARK: Desk

    private static func addDesk(to root: Entity) {
        let walnut = pbr(0.33, 0.21, 0.13, rough: 0.45)
        let walnutDark = pbr(0.24, 0.15, 0.09, rough: 0.6)
        let deskTopY: Float = 0.74

        // Top, side panels and a front panel facing the participant.
        root.addChild(box([1.8, 0.045, 0.85], walnut, at: [0, deskTopY - 0.0225, -1.0], radius: 0.01))
        for x: Float in [-0.86, 0.86] {
            root.addChild(box([0.05, deskTopY - 0.05, 0.8], walnutDark, at: [x, (deskTopY - 0.05) / 2, -1.0]))
        }
        root.addChild(box([1.68, 0.5, 0.03], walnutDark, at: [0, 0.44, -0.66]))

        // Interviewer's side: open laptop (lid back facing the participant).
        let aluminium = pbr(0.78, 0.79, 0.81, rough: 0.3, metal: 0.9)
        let laptop = Entity()
        laptop.position = [0.48, deskTopY, -1.22]
        laptop.orientation = simd_quatf(angle: 0.25, axis: [0, 1, 0])
        laptop.addChild(box([0.32, 0.014, 0.22], aluminium, at: [0, 0.007, 0], radius: 0.004))
        let lid = box([0.32, 0.21, 0.008], aluminium, at: [0, 0.105, 0.11], radius: 0.004)
        lid.orientation = simd_quatf(angle: -0.22, axis: [1, 0, 0])
        laptop.addChild(lid)
        root.addChild(laptop)

        // Notepad and pen in front of the interviewer.
        let notepad = box([0.21, 0.008, 0.29], pbr(0.97, 0.96, 0.9, rough: 0.9), at: [-0.12, deskTopY + 0.004, -1.2])
        notepad.orientation = simd_quatf(angle: -0.12, axis: [0, 1, 0])
        root.addChild(notepad)
        for i in 0..<8 {
            root.addChild(box([0.17, 0.0005, 0.003], pbr(0.55, 0.7, 0.9, rough: 1),
                              at: [-0.12, deskTopY + 0.0085, -1.1 - Float(i) * 0.028]))
        }
        let pen = cylinder(height: 0.14, radius: 0.0045, pbr(0.08, 0.08, 0.1, rough: 0.3, metal: 0.4),
                           at: [0.01, deskTopY + 0.006, -1.16])
        pen.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) * simd_quatf(angle: 0.5, axis: [1, 0, 0])
        root.addChild(pen)

        // Participant's side: their CV in a folder.
        let folder = box([0.24, 0.006, 0.32], pbr(0.85, 0.74, 0.5, rough: 0.9), at: [-0.32, deskTopY + 0.003, -0.84])
        folder.orientation = simd_quatf(angle: 0.08, axis: [0, 1, 0])
        root.addChild(folder)
        let paper = box([0.2, 0.002, 0.28], pbr(0.98, 0.98, 0.97, rough: 1), at: [-0.32, deskTopY + 0.007, -0.84])
        paper.orientation = folder.orientation
        root.addChild(paper)

        // Two glasses of water.
        let glass = transparent(0.85, 0.92, 0.95, opacity: 0.35)
        let water = transparent(0.7, 0.85, 0.95, opacity: 0.5)
        for p: SIMD3<Float> in [[-0.66, deskTopY, -1.25], [0.55, deskTopY, -0.8]] {
            root.addChild(cylinder(height: 0.12, radius: 0.035, glass, at: p + [0, 0.06, 0]))
            root.addChild(cylinder(height: 0.08, radius: 0.031, water, at: p + [0, 0.042, 0]))
        }

        // Small brass nameplate facing the participant.
        let plate = box([0.26, 0.06, 0.012], pbr(0.75, 0.6, 0.3, rough: 0.25, metal: 1), at: [0.1, deskTopY + 0.035, -0.74])
        plate.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
        root.addChild(plate)
    }

    // MARK: Other furniture

    private static func addFurniture(to root: Entity) {
        // Low credenza under the window behind the interviewer.
        let oak = pbr(0.42, 0.29, 0.18, rough: 0.55)
        root.addChild(box([2.4, 0.7, 0.45], oak, at: [0, 0.35, backWallZ + 0.32], radius: 0.01))
        for x: Float in [-0.6, 0, 0.6] {
            root.addChild(box([0.01, 0.6, 0.005], pbr(0.3, 0.2, 0.12, rough: 0.6), at: [x, 0.35, backWallZ + 0.55]))
        }
        // Items on the credenza: books, a lamp, a small plant.
        var rng = SeededRandom(seed: 3)
        var x: Float = -1.0
        for _ in 0..<7 {
            let h = Float(rng.next(in: 0.2...0.28))
            let c = bookColor(&rng)
            root.addChild(box([0.04, h, 0.18], pbr(c.x, c.y, c.z, rough: 0.8), at: [x, 0.7 + h / 2, backWallZ + 0.3]))
            x += 0.045
        }
        root.addChild(cylinder(height: 0.4, radius: 0.012, pbr(0.2, 0.2, 0.2, rough: 0.3, metal: 0.8),
                               at: [0.8, 0.9, backWallZ + 0.3]))
        root.addChild(cylinder(height: 0.16, radius: 0.1, pbr(0.95, 0.92, 0.85, rough: 1), at: [0.8, 1.15, backWallZ + 0.3]))
        addPlant(to: root, at: [0.35, 0.7, backWallZ + 0.3], scale: 0.45)

        // Bookshelf on the left wall.
        let shelfX = -roomHalfWidth + 0.2
        let shelfZ: Float = -1.6
        let shelfWood = pbr(0.28, 0.2, 0.14, rough: 0.6)
        root.addChild(box([0.35, 2.1, 1.4], shelfWood, at: [shelfX, 1.05, shelfZ]))
        for i in 0..<5 {
            let y = 0.12 + Float(i) * 0.42
            root.addChild(box([0.3, 0.37, 1.32], pbr(0.2, 0.14, 0.1, rough: 0.8), at: [shelfX + 0.03, y + 0.2, shelfZ]))
            var z = shelfZ - 0.6
            while z < shelfZ + 0.55 {
                let w = Float(rng.next(in: 0.03...0.06))
                let h = Float(rng.next(in: 0.22...0.33))
                if rng.next(in: 0...1) > 0.12 {
                    let c = bookColor(&rng)
                    root.addChild(box([0.22, h, w], pbr(c.x, c.y, c.z, rough: 0.8), at: [shelfX + 0.08, y + 0.02 + h / 2, z]))
                }
                z += w + 0.005
            }
        }

        // Tall plant in the back right corner.
        addPlant(to: root, at: [roomHalfWidth - 0.5, 0, backWallZ + 0.6], scale: 1.4)

        // Framed artwork on the right wall.
        let artX = roomHalfWidth - 0.04
        root.addChild(box([0.04, 0.9, 1.3], pbr(0.12, 0.12, 0.12, rough: 0.4), at: [artX, 1.6, -1.6]))
        root.addChild(box([0.01, 0.8, 1.2], pbr(0.95, 0.94, 0.9, rough: 1), at: [artX - 0.025, 1.6, -1.6]))
        root.addChild(box([0.01, 0.5, 0.35], pbr(0.85, 0.55, 0.35, rough: 1), at: [artX - 0.032, 1.65, -1.85]))
        root.addChild(box([0.01, 0.35, 0.4], pbr(0.3, 0.45, 0.6, rough: 1), at: [artX - 0.032, 1.55, -1.45]))
        root.addChild(box([0.01, 0.15, 0.6], pbr(0.2, 0.25, 0.3, rough: 1), at: [artX - 0.032, 1.38, -1.6]))

        // Wall clock above the bookshelf.
        let clock = cylinder(height: 0.04, radius: 0.18, pbr(0.97, 0.97, 0.95, rough: 0.8), at: [-roomHalfWidth + 0.05, 2.4, -1.6])
        clock.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        root.addChild(clock)
        let hand1 = box([0.01, 0.12, 0.012], pbr(0.1, 0.1, 0.1, rough: 0.5), at: [-roomHalfWidth + 0.08, 2.44, -1.6])
        root.addChild(hand1)
        let hand2 = box([0.01, 0.012, 0.1], pbr(0.1, 0.1, 0.1, rough: 0.5), at: [-roomHalfWidth + 0.08, 2.4, -1.56])
        root.addChild(hand2)

        // Door on the front wall, behind and to the right of the participant.
        root.addChild(box([1.0, 2.15, 0.06], pbr(0.45, 0.32, 0.2, rough: 0.5), at: [2.3, 1.075, frontWallZ - 0.03]))
        root.addChild(sphere(0.03, pbr(0.75, 0.6, 0.3, rough: 0.2, metal: 1), at: [1.95, 1.0, frontWallZ - 0.08]))
    }

    private static func addPlant(to root: Entity, at base: SIMD3<Float>, scale s: Float) {
        root.addChild(cylinder(height: 0.4 * s, radius: 0.16 * s, pbr(0.9, 0.9, 0.88, rough: 0.6),
                               at: base + [0, 0.2 * s, 0]))
        root.addChild(cylinder(height: 0.02 * s, radius: 0.15 * s, pbr(0.25, 0.18, 0.12, rough: 1),
                               at: base + [0, 0.4 * s, 0]))
        var rng = SeededRandom(seed: UInt64(abs(base.x * 1000)) + 11)
        for _ in 0..<14 {
            let off = SIMD3<Float>(Float(rng.next(in: -0.18...0.18)), Float(rng.next(in: 0.5...1.0)),
                                   Float(rng.next(in: -0.18...0.18))) * s
            let g = Float(rng.next(in: 0.3...0.45))
            root.addChild(sphere(Float(rng.next(in: 0.08...0.14)) * s, pbr(0.12, g, 0.15, rough: 0.8), at: base + off))
        }
    }

    // MARK: Interviewer

    private static func makeInterviewer() -> Entity {
        let person = Entity()
        person.name = "Interviewer"
        person.components.set(InterviewerComponent())

        let suit = pbr(0.13, 0.16, 0.24, rough: 0.75)
        let shirt = pbr(0.95, 0.96, 0.98, rough: 0.8)
        let tie = pbr(0.45, 0.1, 0.14, rough: 0.5)
        let skin = pbr(0.80, 0.62, 0.50, rough: 0.6)
        let hair = pbr(0.16, 0.11, 0.08, rough: 0.9)
        let leather = pbr(0.08, 0.08, 0.09, rough: 0.5)

        // Office chair.
        person.addChild(box([0.52, 0.09, 0.5], leather, at: [0, 0.47, -0.05], radius: 0.03))
        let back = box([0.5, 0.75, 0.08], leather, at: [0, 0.92, -0.3], radius: 0.04)
        back.orientation = simd_quatf(angle: -0.1, axis: [1, 0, 0])
        person.addChild(back)
        person.addChild(cylinder(height: 0.4, radius: 0.025, pbr(0.6, 0.6, 0.62, rough: 0.3, metal: 0.9), at: [0, 0.22, -0.05]))
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            let leg = box([0.3, 0.03, 0.04], pbr(0.2, 0.2, 0.22, rough: 0.4, metal: 0.6),
                          at: [cos(a) * 0.15, 0.04, -0.05 + sin(a) * 0.15])
            leg.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            person.addChild(leg)
        }

        // Upper body (breathes). Leans slightly toward the participant.
        let upper = Entity()
        upper.name = "upperBody"
        upper.position = [0, 0.52, -0.05]
        upper.orientation = simd_quatf(angle: 0.06, axis: [1, 0, 0])
        person.addChild(upper)

        upper.addChild(box([0.4, 0.2, 0.3], suit, at: [0, 0.02, 0.02], radius: 0.08))   // hips / lap
        upper.addChild(box([0.42, 0.56, 0.24], suit, at: [0, 0.32, 0], radius: 0.1))     // torso
        upper.addChild(box([0.13, 0.2, 0.01], shirt, at: [0, 0.48, 0.118]))               // shirt V
        upper.addChild(box([0.045, 0.24, 0.012], tie, at: [0, 0.42, 0.126], radius: 0.005))
        upper.addChild(box([0.06, 0.04, 0.014], tie, at: [0, 0.55, 0.126], radius: 0.006)) // knot
        for side: Float in [-1, 1] {
            let lapel = box([0.06, 0.24, 0.012], suit, at: [side * 0.075, 0.47, 0.124])
            lapel.orientation = simd_quatf(angle: side * 0.28, axis: [0, 0, 1])
            upper.addChild(lapel)
        }

        // Arms resting on the desk, hands together near the notepad.
        for side: Float in [-1, 1] {
            let shoulder: SIMD3<Float> = [side * 0.2, 0.53, 0]
            let elbow: SIMD3<Float> = [side * 0.25, 0.25, 0.2]
            let wrist: SIMD3<Float> = [side * 0.11, 0.25, 0.48]
            upper.addChild(sphere(0.085, suit, at: shoulder))
            upper.addChild(limb(from: shoulder, to: elbow, radius: 0.058, suit))
            upper.addChild(sphere(0.058, suit, at: elbow))
            upper.addChild(limb(from: elbow, to: wrist, radius: 0.05, suit))
            upper.addChild(cylinder(height: 0.02, radius: 0.046, shirt, at: wrist + [0, 0, 0.005], axis: wrist - elbow))
            let hand = sphere(0.048, skin, at: wrist + [-side * 0.02, -0.005, 0.06])
            hand.scale = [0.85, 0.5, 1.25]
            upper.addChild(hand)
        }

        // Neck and head.
        upper.addChild(cylinder(height: 0.1, radius: 0.052, skin, at: [0, 0.62, 0.0]))
        upper.addChild(box([0.15, 0.04, 0.11], shirt, at: [0, 0.585, 0.01], radius: 0.02)) // collar

        let headPivot = Entity()
        headPivot.name = "headPivot"
        headPivot.position = [0, 0.66, 0.0]
        upper.addChild(headPivot)

        let head = sphere(0.105, skin, at: [0, 0.12, 0.01])
        head.scale = [0.88, 1.08, 0.95]
        headPivot.addChild(head)
        let jaw = sphere(0.075, skin, at: [0, 0.06, 0.035])
        jaw.scale = [1, 0.8, 0.9]
        headPivot.addChild(jaw)
        let hairCap = sphere(0.108, hair, at: [0, 0.145, -0.012])
        hairCap.scale = [0.9, 0.95, 0.97]
        headPivot.addChild(hairCap)
        for side: Float in [-1, 1] {
            let ear = sphere(0.022, skin, at: [side * 0.092, 0.115, 0.0])
            ear.scale = [0.5, 1, 0.8]
            headPivot.addChild(ear)

            let eye = sphere(0.011, pbr(0.1, 0.07, 0.05, rough: 0.2), at: [side * 0.034, 0.128, 0.095])
            eye.name = side < 0 ? "eyeL" : "eyeR"
            headPivot.addChild(eye)
            let white = sphere(0.016, pbr(0.95, 0.94, 0.92, rough: 0.3), at: [side * 0.034, 0.128, 0.088])
            white.scale = [1, 0.7, 0.6]
            headPivot.addChild(white)

            let brow = box([0.034, 0.007, 0.01], hair, at: [side * 0.036, 0.155, 0.093], radius: 0.003)
            brow.orientation = simd_quatf(angle: side * -0.1, axis: [0, 0, 1])
            headPivot.addChild(brow)
        }
        let nose = sphere(0.016, skin, at: [0, 0.105, 0.105])
        nose.scale = [0.8, 1.2, 1]
        headPivot.addChild(nose)
        headPivot.addChild(box([0.03, 0.004, 0.006], pbr(0.6, 0.38, 0.35, rough: 0.6), at: [0, 0.07, 0.1], radius: 0.002))

        return person
    }

    // MARK: Building blocks

    private static func pbr(_ r: Float, _ g: Float, _ b: Float, rough: Float = 0.6, metal: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1))
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    private static func transparent(_ r: Float, _ g: Float, _ b: Float, opacity: Float) -> PhysicallyBasedMaterial {
        var m = pbr(r, g, b, rough: 0.05)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }

    private static func unlit(_ r: Float, _ g: Float, _ b: Float) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1))
    }

    private static func box(_ size: SIMD3<Float>, _ material: any RealityKit.Material, at p: SIMD3<Float>, radius: Float = 0) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material])
        e.position = p
        return e
    }

    private static func sphere(_ r: Float, _ material: any RealityKit.Material, at p: SIMD3<Float>) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [material])
        e.position = p
        return e
    }

    private static func cylinder(height: Float, radius: Float, _ material: any RealityKit.Material, at p: SIMD3<Float>,
                                 axis: SIMD3<Float>? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
        e.position = p
        if let axis { e.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(axis)) }
        return e
    }

    /// A cylinder stretched between two points (arms).
    private static func limb(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, _ material: any RealityKit.Material) -> ModelEntity {
        cylinder(height: simd_length(b - a), radius: radius, material, at: (a + b) / 2, axis: b - a)
    }

    private static func bookColor(_ rng: inout SeededRandom) -> SIMD3<Float> {
        let palette: [SIMD3<Float>] = [
            [0.55, 0.15, 0.15], [0.15, 0.25, 0.45], [0.2, 0.38, 0.28], [0.75, 0.65, 0.45],
            [0.3, 0.3, 0.32], [0.6, 0.4, 0.2], [0.85, 0.83, 0.78], [0.35, 0.2, 0.35],
        ]
        return palette[Int(rng.next(in: 0...Double(palette.count) - 0.001))]
    }

    /// A small warm-to-cool vertical gradient used as ambient image-based light.
    private static func ambientGradient() -> CGImage? {
        let width = 64, height = 32
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let t = Float(y) / Float(height - 1)          // 0 = up, 1 = down
            let top: SIMD3<Float> = [1.0, 0.98, 0.94]
            let bottom: SIMD3<Float> = [0.45, 0.38, 0.32]
            let c = top + (bottom - top) * t
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(c.x * 255); pixels[i + 1] = UInt8(c.y * 255); pixels[i + 2] = UInt8(c.z * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Deterministic random numbers so the room looks the same every time.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
