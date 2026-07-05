//
//  AudioListener.swift
//  AuraLink AI
//
//  The Phase 4 ambient-audio subsystem. Owns an AVAudioEngine whose single tap fans out (via the
//  audited AudioTapProcessor) to: the ring buffer (DSP/prosody), SoundAnalysis (sound events), and
//  on-device speech recognition (captions). A DSP loop drains the ring into per-window features,
//  runs VAD, and drives the continuous haptic prosody channel.
//
//  Runs isolated code on its own DispatchQueueExecutor (blocking engine start/stop must not borrow
//  the cooperative pool). Zero-network: speech recognition is FORCED on-device and refuses rather
//  than falling back to a server.
//

import AVFoundation
import SoundAnalysis
import Speech
import CoreMedia

actor AudioListener {

    enum ListenError: Error { case microphoneDenied }

    /// Latest prosody envelope for the UI meter.
    nonisolated let prosody = LatestSlot<ProsodyEnvelope>()
    /// Curated environmental sound events.
    nonisolated let soundEvents: AsyncStream<SoundEvent>
    /// Live speech captions (partial + final).
    nonisolated let captions: AsyncStream<CaptionDTO>

    private let soundEventsContinuation: AsyncStream<SoundEvent>.Continuation
    private let captionsContinuation: AsyncStream<CaptionDTO>.Continuation

    private let haptics: HapticsActor
    private let ring = AudioRingBuffer(capacity: 48_000)
    private let engine = AVAudioEngine()

    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: SoundClassificationObserver?
    private var speechRecognizer: SFSpeechRecognizer?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?

    private var vad = VoiceActivityDetector()
    private var dspLoop: Task<Void, Never>?
    private var sampleRate: Double = 48_000
    private let windowSize = 2048
    private var running = false
    private var audioObservers: [NSObjectProtocol] = []

    private let _executor = DispatchQueueExecutor(label: "com.thetpine.auralink.audio.listener",
                                                  qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { _executor.asUnownedSerialExecutor() }

    init(haptics: HapticsActor) {
        self.haptics = haptics
        var soundCont: AsyncStream<SoundEvent>.Continuation!
        soundEvents = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { soundCont = $0 }
        soundEventsContinuation = soundCont
        var captionCont: AsyncStream<CaptionDTO>.Continuation!
        captions = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { captionCont = $0 }
        captionsContinuation = captionCont
    }

    func start(hapticsEnabled: Bool = true) async throws {
        guard !running else { return }
        guard await CaptureAuthorization.ensureMicrophone() else { throw ListenError.microphoneDenied }
        await haptics.start()
        await haptics.setEnabled(hapticsEnabled)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        setupSoundAnalysis(format: format)
        await setupSpeech()

        let processor = AudioTapProcessor(ring: ring, analyzer: analyzer, speechRequest: speechRequest)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            processor.process(buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
        registerAudioObservers()
        startDSPLoop()
    }

    func stop() async {
        guard running else { return }
        running = false
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioObservers.removeAll()
        dspLoop?.cancel()
        dspLoop = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechTask = nil
        speechRequest = nil
        analyzer?.completeAnalysis()
        analyzer = nil
        observer = nil
        await haptics.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Setup

    private func setupSoundAnalysis(format: AVAudioFormat) {
        let analyzer = SNAudioStreamAnalyzer(format: format)
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
            self.analyzer = analyzer
            return
        }
        let continuation = soundEventsContinuation
        let haptics = self.haptics
        let observer = SoundClassificationObserver { event in
            continuation.yield(event)
            Task { await haptics.playEvent(event) }
        }
        try? analyzer.add(request, withObserver: observer)
        self.analyzer = analyzer
        self.observer = observer
    }

    private func setupSpeech() async {
        guard await CaptureAuthorization.ensureSpeech() else {
            emitSpeechUnavailable("Speech access denied")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else {
            emitSpeechUnavailable("On-device captions unavailable")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true      // zero-network invariant
        request.shouldReportPartialResults = true

        let continuation = captionsContinuation
        speechRecognizer = recognizer
        speechRequest = request
        speechTask = recognizer.recognitionTask(with: request) { result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            guard !text.isEmpty else { return }
            continuation.yield(CaptionDTO(
                spans: [StyledSpan(text: text, weight: result.isFinal ? .confident : .tentative)],
                band: result.isFinal ? .high : .medium,
                latencyMs: 0,
                source: .speech,
                timestamp: .now))
        }
    }

    private func emitSpeechUnavailable(_ message: String) {
        captionsContinuation.yield(CaptionDTO(spans: [StyledSpan(text: message, weight: .tentative)],
                                              band: .low, latencyMs: 0, source: .speech, timestamp: .now))
    }

    // MARK: - Interruption / route-change recovery

    private func registerAudioObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                                 object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw), type == .ended else { return }
            Task { await self?.restartEngine() }   // interruption ended (call/Siri) → resume
        })

        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                 object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
                Task { await self?.restartEngine() }   // headphones (un)plugged, Bluetooth switch
            }
        })
    }

    private func restartEngine() async {
        guard running else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
        } catch {
            // Leave stopped; the next interruption-end / route change retries.
        }
    }

    // MARK: - DSP loop

    private func startDSPLoop() {
        dspLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.processAvailableWindows()
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func processAvailableWindows() async {
        var window = [Float](repeating: 0, count: windowSize)
        while ring.availableToRead >= windowSize {
            let read = window.withUnsafeMutableBufferPointer { ring.read(into: $0) }
            guard read == windowSize else { break }

            let time = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            var features = AudioDSP.features(window, sampleRate: sampleRate, timeSeconds: time)
            let voiced = vad.process(energyDB: features.energyDB)
            features.isVoiced = voiced && features.f0Hz != nil

            let envelope = ProsodyMapper.envelope(from: features)
            await prosody.put(envelope)
            await haptics.updateProsody(envelope.parameters)
        }
    }
}
