//
//  PosePreviewViewModel.swift
//  AuraLink AI
//
//  Drives the live hand-skeleton preview: starts capture, attaches the vision loop, and drains
//  the pose slot onto the main actor for drawing. The Phase 2 on-device verification surface —
//  if the skeleton tracks your hand smoothly, the capture→vision path is alive end to end.
//

import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class PosePreviewViewModel {

    private(set) var pose: PoseObservation?
    private(set) var stats: VisionStats?
    private(set) var isRunning = false
    private(set) var errorText: String?
    private(set) var orientationName = "leftMirrored"

    private let capture: CaptureActor
    private let vision: VisionActor
    private var consumer: Task<Void, Never>?

    init(capture: CaptureActor, vision: VisionActor) {
        self.capture = capture
        self.vision = vision
    }

    /// Cycle the Vision image orientation live (on-device tuning). Pick the one where the skeleton
    /// is upright and mirror-natural, and where "% hands" is highest.
    func cycleOrientation() {
        let vision = self.vision
        Task { [weak self] in
            let next = await vision.cycleOrientation()
            self?.orientationName = Self.name(for: next)
        }
    }

    private static func name(for orientation: CGImagePropertyOrientation) -> String {
        switch orientation {
        case .up: "up"
        case .upMirrored: "upMirrored"
        case .down: "down"
        case .downMirrored: "downMirrored"
        case .left: "left"
        case .leftMirrored: "leftMirrored"
        case .right: "right"
        case .rightMirrored: "rightMirrored"
        @unknown default: "unknown"
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        errorText = nil

        let capture = self.capture
        let vision = self.vision
        consumer = Task { [weak self] in
            do {
                await vision.attach(to: capture.frames)   // idempotent
                await vision.resetStats()
                try await capture.start()
            } catch {
                self?.errorText = "Camera unavailable: \(error)"
                self?.isRunning = false
                return
            }

            var sinceStats = 0
            while !Task.isCancelled {
                guard let pose = await vision.poses.take() else { break }
                self?.pose = pose
                sinceStats += 1
                if sinceStats >= 15 {                     // refresh latency HUD ~2×/s
                    sinceStats = 0
                    self?.stats = await vision.stats()
                }
            }
        }
    }

    func stop() {
        consumer?.cancel()
        consumer = nil
        isRunning = false
        let capture = self.capture
        Task { await capture.stop() }
    }
}
