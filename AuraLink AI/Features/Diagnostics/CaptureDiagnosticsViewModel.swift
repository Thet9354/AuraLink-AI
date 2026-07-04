//
//  CaptureDiagnosticsViewModel.swift
//  AuraLink AI
//
//  Drives an on-device self-test for the Phase 1 capture gate: run capture for a few seconds,
//  drain frames at full speed, and report measured video fps, delivered/dropped counts, and audio
//  samples captured. The camera is unavailable in the simulator, so this reports an error there —
//  it is meant to be run on a physical device.
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
    }

    private(set) var isRunning = false
    private(set) var report: Report?
    private(set) var errorText: String?

    private let capture: CaptureActor
    private let audio: AudioActor

    init(capture: CaptureActor, audio: AudioActor) {
        self.capture = capture
        self.audio = audio
    }

    func run(seconds: Double = 5) {
        guard !isRunning else { return }
        isRunning = true
        report = nil
        errorText = nil

        let capture = self.capture
        let audio = self.audio
        Task { [weak self] in
            do {
                try await capture.start()
                try await audio.start()

                // Drain frames as fast as they arrive so buffering drops reflect the pipeline, not
                // an artificially stalled consumer.
                let drain = Task {
                    for await _ in capture.frames {
                        if Task.isCancelled { break }
                    }
                }

                let videoBefore = await capture.counts()
                let audioBefore = await audio.totalCaptured()
                try await Task.sleep(for: .seconds(seconds))
                let videoAfter = await capture.counts()
                let audioAfter = await audio.totalCaptured()

                drain.cancel()
                await capture.stop()
                await audio.stop()

                let delivered = videoAfter.delivered - videoBefore.delivered
                let dropped = videoAfter.dropped - videoBefore.dropped
                self?.report = Report(videoFps: Double(delivered) / seconds,
                                      delivered: delivered,
                                      dropped: dropped,
                                      audioSamples: audioAfter - audioBefore,
                                      seconds: seconds)
            } catch {
                await capture.stop()
                await audio.stop()
                self?.errorText = String(describing: error)
            }
            self?.isRunning = false
        }
    }
}
