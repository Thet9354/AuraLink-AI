//
//  VisionActor.swift
//  AuraLink AI
//
//  The vision front-end: consumes the capture layer's frame stream, runs Vision hand + body pose,
//  maps results into framework-free `PoseObservation`s, and extracts `FeatureVector`s into a
//  rolling ring for Phase 3 segmentation.
//
//  Runs on its own `DispatchQueueExecutor`: `VNImageRequestHandler.perform` is synchronous and
//  CPU/ANE-heavy, and must not block a cooperative-pool thread (same reasoning as `CaptureActor`).
//
//  The frame-consumption loop is attached ONCE and lives for the app's lifetime — `AsyncStream` is
//  single-iteration, and cancelling an iterator terminates the stream permanently. Start/stop is
//  controlled upstream by the capture session; when capture is stopped, the loop simply idles.
//
//  Body pose is duty-cycled (every 3rd frame): torso anchors move far slower than hands, and the
//  body request costs as much as the hand request. The latest anchors are carried forward.
//

import Vision
import CoreMedia
import ImageIO
import os

/// Point-in-time vision pipeline metrics for diagnostics and the Phase 2 latency gate.
nonisolated struct VisionStats: Sendable {
    var framesProcessed: Int
    var framesWithHands: Int
    var latencyP50Ms: Double
    var latencyP95Ms: Double
    var latencyMaxMs: Double

    var detectionRate: Double {
        framesProcessed > 0 ? Double(framesWithHands) / Double(framesProcessed) : 0
    }
}

actor VisionActor: PoseProducing {

    nonisolated let poses = LatestSlot<PoseObservation>()

    private let _executor: DispatchQueueExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { _executor.asUnownedSerialExecutor() }

    private let handRequest = VNDetectHumanHandPoseRequest()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let bodyDutyCycle = 3

    private var loop: Task<Void, Never>?
    private var lastBody: BodyAnchors?

    // The CGImagePropertyOrientation applied to native (landscape) camera buffers so Vision sees an
    // upright, mirror-correct hand. `.leftMirrored` is the front-camera / portrait default; the pose
    // preview can cycle this live to confirm it on hardware.
    private var orientation: CGImagePropertyOrientation = .leftMirrored
    private static let orientationCycle: [CGImagePropertyOrientation] =
        [.up, .upMirrored, .right, .rightMirrored, .down, .downMirrored, .left, .leftMirrored]

    // Governor-controlled processing rate. Capture is 60 fps; under thermal/battery pressure the
    // governor lowers this and we skip frames, cutting ANE/GPU load with a visible (choppier) effect.
    private var targetHz = 60
    private var frameIndex: UInt64 = 0
    private var featureState = FeatureExtractor.State()
    private var featureRing = RingBuffer<FeatureVector>(capacity: 90)   // ~3 s at 30 Hz inference

    // Feature multicast: AsyncStream is single-iteration, but features have multiple sequential
    // consumers (translation pipeline, enrollment recorder). Each subscriber gets its own bounded
    // stream; a terminated subscriber is pruned on its next yield.
    private var featureSubscribers: [UUID: AsyncStream<FeatureVector>.Continuation] = [:]

    // Capture→pose latency samples (ms), bounded window for percentile computation.
    private var latencies: [Double] = []
    private let latencyWindow = 600
    private var framesProcessed = 0
    private var framesWithHands = 0

    init() {
        _executor = DispatchQueueExecutor(label: "com.thetpine.auralink.vision",
                                          qos: .userInitiated)
        handRequest.maximumHandCount = 2
    }

    /// Attach the lifetime consumption loop to the capture stream. Idempotent; see the header
    /// comment for why this is attach-once rather than start/stop.
    func attach(to frames: AsyncStream<FrameToken>) {
        guard loop == nil else { return }
        loop = Task {
            for await token in frames {
                self.consume(token)
            }
        }
    }

    /// Governor hook: cap the pose-processing rate (frames are skipped to approximate `hz`).
    func setTargetHz(_ hz: Int) {
        targetHz = max(1, min(60, hz))
    }

    /// Advance to the next candidate image orientation (pose-preview tuning). Returns the new one.
    func cycleOrientation() -> CGImagePropertyOrientation {
        let index = Self.orientationCycle.firstIndex(of: orientation) ?? Self.orientationCycle.count - 1
        orientation = Self.orientationCycle[(index + 1) % Self.orientationCycle.count]
        return orientation
    }

    func currentOrientation() -> CGImagePropertyOrientation { orientation }

    /// Applies frame-skipping before the (expensive) `process`.
    private func consume(_ token: FrameToken) {
        frameIndex &+= 1
        let skipInterval = UInt64(max(1, 60 / targetHz))
        guard frameIndex % skipInterval == 0 else { return }
        process(token)
    }

    /// Most recent feature vectors, oldest → newest (Phase 3 segmentation input).
    func recentFeatures() -> [FeatureVector] { featureRing.elements }

    /// A private, bounded stream of feature vectors for one consumer. Latest-biased: if the
    /// consumer lags, oldest buffered features are dropped (`.bufferingNewest`), never queued
    /// unboundedly.
    func subscribeFeatures() -> AsyncStream<FeatureVector> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: FeatureVector.self,
                                                            bufferingPolicy: .bufferingNewest(8))
        featureSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeFeatureSubscriber(id) }
        }
        return stream
    }

    private func removeFeatureSubscriber(_ id: UUID) {
        featureSubscribers[id] = nil
    }

    func stats() -> VisionStats {
        let sorted = latencies.sorted()
        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let idx = min(sorted.count - 1, Int(Double(sorted.count) * p))
            return sorted[idx]
        }
        return VisionStats(framesProcessed: framesProcessed,
                           framesWithHands: framesWithHands,
                           latencyP50Ms: percentile(0.50),
                           latencyP95Ms: percentile(0.95),
                           latencyMaxMs: sorted.last ?? 0)
    }

    func resetStats() {
        latencies.removeAll(keepingCapacity: true)
        framesProcessed = 0
        framesWithHands = 0
    }

    // MARK: - Per-frame processing

    private func process(_ token: FrameToken) {
        let interval = Signposts.latency.beginInterval("captureToPose")
        defer { Signposts.latency.endInterval("captureToPose", interval) }

        framesProcessed += 1
        let runBody = framesProcessed % bodyDutyCycle == 1

        // Vision vends autoreleased observations; drain per frame.
        autoreleasepool {
            // Native landscape buffer → Vision orientation maps it to upright, mirror-correct.
            let handler = VNImageRequestHandler(cvPixelBuffer: token.pixelBuffer, orientation: orientation)
            let requests: [VNRequest] = runBody ? [handRequest, bodyRequest] : [handRequest]
            try? handler.perform(requests)
        }

        let hands = (handRequest.results ?? []).compactMap(Self.mapHand)
        if runBody, let body = bodyRequest.results?.first {
            lastBody = Self.mapBody(body)
        }

        let observation = PoseObservation(hands: hands,
                                          body: lastBody,
                                          timeSeconds: token.pts.seconds,
                                          seq: token.seq)

        if !hands.isEmpty { framesWithHands += 1 }

        let (features, nextState) = FeatureExtractor.extract(from: observation, state: featureState)
        featureState = nextState
        featureRing.append(features)
        for continuation in featureSubscribers.values {
            continuation.yield(features)
        }

        // Capture clock is the host time clock; wall latency = now − presentation timestamp.
        let latencyMs = (CMClockGetTime(CMClockGetHostTimeClock()).seconds - token.pts.seconds) * 1000
        if latencyMs.isFinite, latencyMs >= 0 {
            if latencies.count >= latencyWindow { latencies.removeFirst() }
            latencies.append(latencyMs)
        }

        let poses = self.poses
        Task { await poses.put(observation) }
    }

    // MARK: - Vision → Domain mapping

    private static let jointMap: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip)
    ]

    private static func mapHand(_ observation: VNHumanHandPoseObservation) -> HandPose? {
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var points = [SIMD2<Float>](repeating: .zero, count: HandJoint.count)
        var confidences = [Float](repeating: 0, count: HandJoint.count)
        for (visionName, joint) in jointMap {
            if let p = recognized[visionName] {
                points[joint.rawValue] = SIMD2(Float(p.location.x), Float(p.location.y))
                confidences[joint.rawValue] = Float(p.confidence)
            }
        }
        let chirality: Chirality = switch observation.chirality {
        case .left: .left
        case .right: .right
        case .unknown: .unknown
        @unknown default: .unknown
        }
        return HandPose(points: points, confidences: confidences, chirality: chirality)
    }

    private static func mapBody(_ observation: VNHumanBodyPoseObservation) -> BodyAnchors {
        func point(_ name: VNHumanBodyPoseObservation.JointName) -> SIMD2<Float>? {
            guard let p = try? observation.recognizedPoint(name), p.confidence >= 0.3 else { return nil }
            return SIMD2(Float(p.location.x), Float(p.location.y))
        }
        return BodyAnchors(nose: point(.nose),
                           leftShoulder: point(.leftShoulder),
                           rightShoulder: point(.rightShoulder))
    }
}
