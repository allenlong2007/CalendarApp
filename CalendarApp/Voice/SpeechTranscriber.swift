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
    private(set) var access: Access = .unknown
    private(set) var errorMessage: String?

    /// Words the recognizer should be biased toward -- calendar names, places.
    var contextualStrings: [String] = []
    /// Called once a pause follows speech, or when stopped, with the final text.
    var onFinished: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    /// How long a pause ends the sentence.
    private let silenceTimeout: Duration = .milliseconds(1700)

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
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        errorMessage = nil
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = false
            request.contextualStrings = contextualStrings
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            Self.installTap(on: engine.inputNode, feeding: RequestBox(request))
            engine.prepare()
            try engine.start()

            task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failure in
                Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failure: failure) }
            }
            isListening = true
            armSilenceTimer()
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
        }
    }

    /// Stops listening and reports what was heard.
    func stop() {
        guard isListening else { return }
        let heard = transcript
        tearDown()
        if !heard.trimmingCharacters(in: .whitespaces).isEmpty { onFinished?(heard) }
    }

    func cancel() { tearDown() }

    // MARK: - Internals

    private func handle(text: String?, isFinal: Bool, failure: String?) {
        guard isListening else { return }
        if let text, !text.isEmpty {
            transcript = text
            armSilenceTimer()
        }
        if isFinal { stop() }
        else if let failure, transcript.isEmpty { errorMessage = failure; tearDown() }
    }

    /// A pause after speech means the sentence is done; before any speech it
    /// just keeps waiting (up to a longer limit).
    private func armSilenceTimer() {
        silenceTask?.cancel()
        let waitForSpeech = transcript.isEmpty
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: waitForSpeech ? .seconds(8) : self?.silenceTimeout ?? .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stop() }
        }
    }

    private func tearDown() {
        silenceTask?.cancel()
        silenceTask = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The audio tap and the recognition callback both run on background
    // queues, so they're built outside the main actor.

    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    private nonisolated static func installTap(on node: AVAudioInputNode, feeding box: RequestBox) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
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
