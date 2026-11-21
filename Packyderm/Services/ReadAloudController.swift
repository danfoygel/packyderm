import AVFoundation
import Foundation
import Observation
import Speech

enum ReadAloudDefaults {
    /// Multiplier on the system's default speaking rate.
    static let rate = 1.0
    /// Seconds of silence after an answer before the next item.
    static let pause = 0.4
    /// Seconds to wait for an answer.
    static let listenTimeout = 6.0
}

enum VoiceAnswer {
    case yes, no, again, back, stop

    /// Finds the first answer keyword in a transcript.
    static func parse(_ transcript: String) -> VoiceAnswer? {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let text = " " + words.joined(separator: " ") + " "
        let table: [(VoiceAnswer, [String])] = [
            (.no, ["no", "nope", "nah", "not yet", "not", "skip", "later", "negative", "don't", "dont"]),
            (.yes, ["yes", "yeah", "yep", "yup", "ya", "yah", "got it", "got", "packed", "check", "done", "sure", "ok", "okay", "affirmative", "uh huh", "have it"]),
            (.again, ["repeat", "again", "what", "pardon", "sorry", "huh"]),
            (.back, ["back", "previous", "undo"]),
            (.stop, ["stop", "pause", "quit", "exit"]),
        ]
        // Earliest keyword in the transcript wins; "not packed" → no.
        var best: (VoiceAnswer, String.Index)?
        for (answer, keywords) in table {
            for keyword in keywords {
                if let range = text.range(of: " \(keyword) "),
                   best == nil || range.lowerBound < best!.1 {
                    best = (answer, range.lowerBound)
                }
            }
        }
        return best?.0
    }
}

/// Reads unpacked items aloud one at a time and listens for yes / no.
@MainActor
@Observable
final class ReadAloudController: NSObject {
    enum Phase: Equatable {
        case idle, speaking, listening, waiting, paused, finished
    }

    struct Step: Identifiable {
        var id: UUID { itemID }
        var itemID: UUID
        var name: String
        var category: String
        var isCritical: Bool
    }

    private(set) var steps: [Step] = []
    private(set) var index = 0
    private(set) var phase: Phase = .idle
    private(set) var heard = ""
    private(set) var permissionProblem: String?
    private(set) var packedIDs: Set<UUID> = []
    private(set) var skippedIDs: Set<UUID> = []

    var rate = ReadAloudDefaults.rate
    var pause = ReadAloudDefaults.pause
    var listenTimeout = ReadAloudDefaults.listenTimeout
    var voiceEnabled = true

    /// Called with (itemID, packed) whenever an answer is recorded.
    var onAnswer: ((UUID, Bool) -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var speakContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var lastSpokenCategory: String?
    @ObservationIgnored private var generation = 0

    var current: Step? { steps.indices.contains(index) ? steps[index] : nil }

    init(steps: [Step]) {
        self.steps = steps
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Lifecycle

    func start() async {
        if voiceEnabled {
            voiceEnabled = await requestPermissions()
        }
        configureAudioSession()
        await runCurrent()
    }

    func stop() {
        generation += 1
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        finishSpeaking()
        phase = .paused
    }

    func resume() {
        retries = 0
        lastSpokenCategory = nil
        Task { await runCurrent() }
    }

    func shutdown() {
        stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Answers (voice or buttons)

    func answer(_ answer: VoiceAnswer) {
        generation += 1
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        finishSpeaking()
        retries = 0

        switch answer {
        case .yes, .no:
            guard let step = current else { return }
            let packed = answer == .yes
            if packed {
                packedIDs.insert(step.itemID)
                skippedIDs.remove(step.itemID)
            } else {
                skippedIDs.insert(step.itemID)
                packedIDs.remove(step.itemID)
            }
            onAnswer?(step.itemID, packed)
            index += 1
            Task {
                try? await Task.sleep(for: .seconds(pause))
                await runCurrent()
            }
        case .again:
            lastSpokenCategory = nil
            Task { await runCurrent() }
        case .back:
            index = max(index - 1, 0)
            lastSpokenCategory = nil
            Task { await runCurrent() }
        case .stop:
            phase = .paused
        }
    }

    /// Start over with the items answered "no".
    func reviewSkipped() {
        steps = steps.filter { skippedIDs.contains($0.itemID) }
        skippedIDs = []
        index = 0
        lastSpokenCategory = nil
        Task { await runCurrent() }
    }

    func sample() {
        let utterance = makeUtterance("Toothbrush")
        synthesizer.speak(utterance)
    }

    // MARK: Loop

    private func runCurrent() async {
        let myGeneration = generation
        guard let step = current else {
            phase = .finished
            let text = skippedIDs.isEmpty ? "All done." : "Done. \(skippedIDs.count) item\(skippedIDs.count == 1 ? "" : "s") still to pack."
            await speak(text)
            return
        }

        phase = .speaking
        heard = ""
        var text = step.name
        if step.category != lastSpokenCategory {
            text = "\(step.category). \(step.name)"
            lastSpokenCategory = step.category
        }
        if retries > 0 { text = "\(step.name)?" }
        await speak(text)
        guard myGeneration == generation else { return }

        if voiceEnabled {
            listen(generation: myGeneration)
        } else {
            phase = .waiting
        }
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let scaled = base * rate
        utterance.rate = Float(min(max(scaled, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        utterance.postUtteranceDelay = 0.05
        return utterance
    }

    private func speak(_ text: String) async {
        finishSpeaking()
        await withCheckedContinuation { continuation in
            speakContinuation = continuation
            let utterance = makeUtterance(text)
            let id = ObjectIdentifier(utterance)
            currentUtterance = id
            synthesizer.speak(utterance)
            // Watchdog: never hang if the synthesizer fails to report completion.
            let words = Double(text.split(separator: " ").count)
            let estimate = words * 0.5 / max(rate, 0.3) + 2.5
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(estimate))
                guard let self, self.currentUtterance == id else { return }
                self.synthesizer.stopSpeaking(at: .immediate)
                self.finishSpeaking(id)
            }
        }
    }

    private func finishSpeaking(_ utterance: ObjectIdentifier? = nil) {
        // Ignore late callbacks for utterances that were already replaced.
        if let utterance, utterance != currentUtterance { return }
        currentUtterance = nil
        speakContinuation?.resume()
        speakContinuation = nil
    }

    // MARK: Listening

    private func listen(generation myGeneration: Int) {
        guard let recognizer, recognizer.isAvailable else {
            phase = .waiting
            return
        }
        stopListening()
        phase = .listening

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = ["yes", "no", "yep", "nope", "repeat", "back", "stop"]
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            phase = .waiting
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            phase = .waiting
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            let transcript = result?.bestTranscription.formattedString
            Task { @MainActor in
                guard let self, self.generation == myGeneration, let transcript else { return }
                self.heard = transcript
                if let answer = VoiceAnswer.parse(transcript) {
                    self.answer(answer)
                }
            }
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.listenTimeout ?? 6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == myGeneration, self.phase == .listening else { return }
                self.stopListening()
                if self.retries < 1 {
                    self.retries += 1
                    Task { await self.runCurrent() }
                } else {
                    self.retries = 0
                    self.phase = .waiting
                }
            }
        }
    }

    private func stopListening() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        if voiceEnabled {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            permissionProblem = "Speech recognition is off, so use the buttons to answer. You can enable it in Settings."
            return false
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionProblem = "Microphone access is off, so use the buttons to answer. You can enable it in Settings."
            return false
        }
        return true
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishSpeaking(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishSpeaking(id) }
    }
}
