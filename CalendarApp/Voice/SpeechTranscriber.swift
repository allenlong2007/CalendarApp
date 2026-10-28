import AVFoundation
import Observation
import Speech

/// Microphone -> live text, using Apple's on-device speech recognition when the
/// phone supports it (nothing is sent anywhere) and the system's otherwise.
///
/// It only produces a transcript. Turning words into an event is
/// VoiceEventParser's job, and showing it is VoiceEventView's.
@Observable
@MainActor
final class SpeechTranscriber {
    enum Access { case unknown, granted, denied }

    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var isFinalizing = false
    private(set) var access: Access = .unknown
    private(set) var errorMessage: String?

    /// Words the recognizer should be biased toward -- calendar names, places.
    /// Used only for on-device recognition (see start()).
    var contextualStrings: [String] = []
    /// Called once a pause follows speech, or when stopped, with the final text.
    var onFinished: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var buffer = SpeechTranscriptBuffer()
    private let feed = RequestBox()
    private var segmentID = UUID()
    private var tapInstalled = false

    /// How long a pause ends the sentence.
    private let silenceTimeout: Duration = .seconds(4)

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Permission

    func requestAccess() async {
        let speech = await Self.requestSpeechAuthorization()
        let microphone = await Self.requestMicrophonePermission()
        access = (speech && microphone) ? .granted : .denied
    }

    // Apple calls these completion handlers on a background queue. A closure
    // written inside a main-actor method is itself main-actor, and Swift 6
    // traps (crashes) when it's called off the main thread -- which is exactly
    // what happened when the permission prompt was answered. So they live here,
    // outside the actor.
    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Listening

    func start() {
        guard !isListening, !isFinalizing else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        errorMessage = nil
        transcript = ""
        buffer = SpeechTranscriptBuffer()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isListening = true
            startSegment(using: recognizer)
            Self.installTap(on: engine.inputNode, feeding: feed)
            tapInstalled = true
            engine.prepare()
            try engine.start()
            armSilenceTimer()
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
        }
    }

    private func startSegment(using recognizer: SFSpeechRecognizer) {
        segmentID = UUID()
        let id = segmentID
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Keep private vocabulary on device; preserve the system fallback on
        // devices that cannot perform local speech recognition.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            request.contextualStrings = VoiceVocabulary.hints(calendars: [], places: contextualStrings)
        }
        self.request = request
        feed.replace(with: request)
        task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failure in
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failure: failure, segment: id) }
        }
    }

    /// End audio first, then allow the recognizer to deliver the last words.
    /// Cancelling immediately here used to throw away the final transcription.
    func stop() {
        guard isListening else { return }
        isListening = false
        isFinalizing = true
        silenceTask?.cancel()
        stopAudio()
        feed.replace(with: nil)
        request?.endAudio()
        finalizationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func cancel() { errorMessage = nil; tearDown() }

    private func handle(text: String?, isFinal: Bool, failure: String?, segment: UUID) {
        guard segment == segmentID, isListening || isFinalizing else { return }
        if let text, !text.isEmpty {
            let previous = buffer.text
            buffer.update(text)
            transcript = VoiceVocabulary.correctPlaces(buffer.text)
            if isListening, previous != buffer.text { armSilenceTimer() }
        }
        if isFinal {
            if isFinalizing { finish() }
            else if let recognizer {
                // Apple's tasks can finalize mid-dictation. Preserve that
                // segment and keep feeding the microphone into a fresh task.
                buffer.commitSegment()
                startSegment(using: recognizer)
            }
        } else if let failure {
            if transcript.isEmpty { errorMessage = failure; tearDown() }
            else { finish() }
        }
    }

    private func finish() {
        guard isListening || isFinalizing else { return }
        let heard = VoiceVocabulary.correctPlaces(buffer.text).trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = heard
        tearDown()
        if !heard.isEmpty { onFinished?(heard) }
    }

    private func armSilenceTimer() {
        silenceTask?.cancel()
        let delay: Duration = transcript.isEmpty ? .seconds(15) : silenceTimeout
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func tearDown() {
        segmentID = UUID()
        silenceTask?.cancel(); silenceTask = nil
        finalizationTask?.cancel(); finalizationTask = nil
        stopAudio()
        feed.replace(with: nil)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isListening = false
        isFinalizing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The audio tap and the recognition callback both run on background
    // queues, so they're built outside the main actor.

    private final class RequestBox: @unchecked Sendable {
        // The audio render callback and MainActor swap/append under one lock.
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func replace(with request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); defer { lock.unlock() }
            self.request = request
        }
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            request?.append(buffer)
        }
    }

    private nonisolated static func installTap(on node: AVAudioInputNode, feeding box: RequestBox) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
        }
    }

    private nonisolated static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error?.localizedDescription)
        }
    }
}
