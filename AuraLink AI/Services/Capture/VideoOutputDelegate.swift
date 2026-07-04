//
//  VideoOutputDelegate.swift
//  AuraLink AI
//
//  The nonisolated bridge from AVFoundation's capture callback into the Swift concurrency world.
//  It does exactly one thing per frame: wrap the pixel buffer in a `FrameToken` and yield it to the
//  latest-value stream. No processing happens here — that would block the capture queue.
//
//  `@unchecked Sendable` justification: `NSObject` is not `Sendable`, and `seq` is mutable. Both are
//  safe because AVFoundation invokes this delegate exclusively on the single serial `delegateQueue`
//  it is registered with — all mutable state is confined to that queue. This is the second and
//  final audited unsafe boundary alongside `FrameToken` and `AudioRingBuffer`.
//

import AVFoundation
import CoreMedia

nonisolated final class VideoOutputDelegate: NSObject,
                                             AVCaptureVideoDataOutputSampleBufferDelegate,
                                             @unchecked Sendable {

    private let continuation: AsyncStream<FrameToken>.Continuation
    private let counters: CaptureCounters
    private var seq: UInt64 = 0   // confined to the capture delegate queue

    init(continuation: AsyncStream<FrameToken>.Continuation, counters: CaptureCounters) {
        self.continuation = continuation
        self.counters = counters
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Drain autoreleased CoreMedia/CoreVideo objects per frame so they don't accumulate for the
        // whole capture burst and spike peak memory.
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            seq &+= 1
            counters.recordDelivered()
            let token = FrameToken(pixelBuffer: pixelBuffer,
                                   pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                   seq: seq)
            // `.bufferingNewest(1)` drops the previously buffered frame if the consumer hasn't taken
            // it — that is the back-pressure, counted here for the drop-rate gate.
            if case .dropped = continuation.yield(token) {
                counters.recordDropped()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        counters.recordDropped()
    }
}
