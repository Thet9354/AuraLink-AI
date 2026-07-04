//
//  CaptureDiagnosticsViewModel.swift
//  AuraLink AI
//
//  Drives an on-device self-test for the Phase 1/2 gates: run capture + vision for a few seconds
//  and report measured video fps, delivered/dropped counts, audio samples, and capture→pose
//  latency percentiles. The camera is unavailable in the simulator, so this reports an error
//  there — it is meant to be run on a physical device.
//

import Foundation
import Observation

@MainActor
@Observable
final class CaptureDiagnosticsViewModel {

    struct Report: Sendable {
        var videoFps: Double
        var delivered: Int
        var dropped: Int
        var audioSamples: Int
        var seconds: Double
        var vision: VisionStats
    }

    private(set) var isRunning = false
    private(set) var report: Report?
    private(set) var errorText: String?

    private let capture: CaptureActor
    private let audio: AudioActor
    private let vision: VisionActor

    init(capture: CaptureActor, audio: AudioActor, vision: VisionActor) {
        self.capture = capture
        self.audio = audio
        self.vision = vision
    }

    func run(seconds: Double = 5) {
        guard !isRunning else { return }
        isRunning = true
        report = nil
        errorText = nil

        let capture = self.capture
        let audio = self.audio
        let vision = self.vision
        Task { [weak self] in
            do {
                // The vision loop is the frame consumer (attach is idempotent); its processing
                // rate vs. 60 fps capture is exactly what the dropped-frame counter measures.
                await vision.attach(to: capture.frames)
                await vision.resetStats()
                try await capture.start()
                try await audio.start()

                let videoBefore = await capture.counts()
                let audioBefore = await audio.totalCaptured()
                try await Task.sleep(for: .seconds(seconds))
                let videoAfter = await capture.counts()
                let audioAfter = await audio.totalCaptured()
                let visionStats = await vision.stats()

                await capture.stop()
                await audio.stop()

                let delivered = videoAfter.delivered - videoBefore.delivered
                let dropped = videoAfter.dropped - videoBefore.dropped
                self?.report = Report(videoFps: Double(delivered) / seconds,
                                      delivered: delivered,
                                      dropped: dropped,
                                      audioSamples: audioAfter - audioBefore,
                                      seconds: seconds,
                                      vision: visionStats)
            } catch {
                await capture.stop()
                await audio.stop()
                self?.errorText = String(describing: error)
            }
            self?.isRunning = false
        }
    }
}
