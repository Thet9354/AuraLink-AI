//
//  CaptureActor.swift
//  AuraLink AI
//
//  Owns the `AVCaptureSession`. Runs its isolated code on a dedicated `DispatchQueueExecutor` so the
//  blocking session-configuration and start/stop calls never borrow a cooperative-pool thread.
//  Produces `FrameToken`s through a `.bufferingNewest(1)` stream (latest-frame, drop-stale).
//

import AVFoundation
import CoreMedia

actor CaptureActor: FrameProducing {

    enum CaptureError: Error {
        case cameraNotAuthorized
        case noCamera
        case cannotAddInput
        case cannotAddOutput
    }

    nonisolated let frames: AsyncStream<FrameToken>
    private let continuation: AsyncStream<FrameToken>.Continuation
    private let counters = CaptureCounters()

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let delegateQueue = DispatchQueue(label: "com.thetpine.auralink.capture.video",
                                              qos: .userInteractive)
    private var delegate: VideoOutputDelegate?
    private let position: AVCaptureDevice.Position
    private var isConfigured = false

    private let _executor: DispatchQueueExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { _executor.asUnownedSerialExecutor() }

    init(position: AVCaptureDevice.Position = .front) {
        self.position = position
        _executor = DispatchQueueExecutor(label: "com.thetpine.auralink.capture.actor",
                                          qos: .userInteractive)
        var continuation: AsyncStream<FrameToken>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        self.continuation = continuation
    }

    func start() async throws {
        guard await CaptureAuthorization.ensureVideo() else { throw CaptureError.cameraNotAuthorized }
        try configureIfNeeded()
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// Snapshot of delivered / dropped frame counters, for diagnostics and the fps gate.
    func counts() -> CaptureCounts { counters.snapshot() }

    // MARK: - Configuration

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Let the device's active format govern (we set 60 fps explicitly below).
        session.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        let delegate = VideoOutputDelegate(continuation: continuation, counters: counters)
        self.delegate = delegate
        videoOutput.setSampleBufferDelegate(delegate, queue: delegateQueue)
        guard session.canAddOutput(videoOutput) else { throw CaptureError.cannotAddOutput }
        session.addOutput(videoOutput)

        // Buffers are delivered in the camera's native (landscape) orientation; the VisionActor
        // supplies the correct CGImagePropertyOrientation so Vision analyzes an upright hand.
        // (Rotating the connection here as well caused a double transform → slanted skeleton.)

        configure60fps(on: device)
        isConfigured = true
    }

    /// Selects a 60 fps-capable format (preferring ~720p to keep bandwidth reasonable) and pins the
    /// frame duration. Non-fatal: if no such format exists the current one is kept.
    private func configure60fps(on device: AVCaptureDevice) {
        let target = 60.0
        let candidates = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= target }
        }
        let chosen = candidates.min { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return abs(Int(da.width) - 1280) < abs(Int(db.width) - 1280)
        }
        guard let format = chosen, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(target))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }
}
