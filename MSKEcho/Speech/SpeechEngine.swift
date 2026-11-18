import Foundation
import Speech
import AVFoundation
import Observation

/// 音訊執行緒與主執行緒之間共用目前的 recognition request
private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = r; lock.unlock() }
    func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); request?.append(buffer); lock.unlock() }
}

/// 裝置端 zh-TW 連續口述引擎
/// - 停頓約 1.5 秒自動「切段」：舊段落送出定稿、同時無縫開始新段落（不漏音）
/// - 套用 contextualStrings 與自訂語言模型
@MainActor
@Observable
final class SpeechEngine {
    enum State: Equatable {
        case idle, recording
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var partialText = ""
    private(set) var onDeviceSupported: Bool
    private(set) var customModelActive = false
    var silenceInterval: Double = 1.5

    /// 每段定稿後回呼（辨識原文）
    var onSegment: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let sink = BufferSink()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    private var partials: [Int: String] = [:]
    private var generation = 0
    private var wantsRecording = false
    private var silenceTimer: Task<Void, Never>?
    private var quickFailures = 0
    private var generationStart = Date()

    private var contextualStrings: [String] = []
    private var languageModel: SFSpeechLanguageModel.Configuration?

    init(localeIdentifier: String = "zh-TW") {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        onDeviceSupported = recognizer?.supportsOnDeviceRecognition ?? false
    }

    var isRecording: Bool { state == .recording }

    func update(contextualStrings: [String]) { self.contextualStrings = contextualStrings }

    func update(languageModel: SFSpeechLanguageModel.Configuration?) {
        self.languageModel = languageModel
        customModelActive = languageModel != nil
    }

    // MARK: - Control

    func toggle() async { isRecording ? stop() : await start() }

    func start() async {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .error("語音辨識暫時無法使用"); return
        }
        onDeviceSupported = recognizer.supportsOnDeviceRecognition
        guard onDeviceSupported else {
            state = .error("此 iPhone 尚未提供「中文（台灣）」離線辨識。請到 設定 › 一般 › 鍵盤，開啟「聽寫」並加入中文（台灣）。")
            return
        }
        guard await Self.requestPermissions() else {
            state = .error("請在 設定 › MSK口述 允許麥克風與語音辨識")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            let sink = self.sink
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                sink.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("無法啟動麥克風：\(error.localizedDescription)")
            return
        }

        wantsRecording = true
        quickFailures = 0
        state = .recording
        beginSegment()
    }

    func stop() {
        wantsRecording = false
        silenceTimer?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()          // 目前段落會送出最後結果
        sink.set(nil)
        request = nil
        if case .error = state {} else { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Segments

    private func beginSegment() {
        guard let recognizer else { return }
        generation += 1
        let gen = generation
        generationStart = Date()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true      // 音訊絕不離開手機
        req.addsPunctuation = true
        req.taskHint = .dictation
        req.contextualStrings = contextualStrings
        if let lm = languageModel { req.customizedLanguageModel = lm }

        request = req
        sink.set(req)
        partialText = ""

        tasks[gen] = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(gen: gen, text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    /// 停頓 → 新段落立即接手收音，舊段落 endAudio 後等它送出最終結果
    private func rollover() {
        guard wantsRecording, let old = request else { return }
        beginSegment()
        old.endAudio()
    }

    private func handle(gen: Int, text: String?, isFinal: Bool, failed: Bool) {
        if let text {
            partials[gen] = text
            if gen == generation {
                partialText = text
                scheduleSilenceTimer(for: gen)
            }
        }

        guard isFinal || failed else { return }

        let segment = (partials.removeValue(forKey: gen) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        tasks.removeValue(forKey: gen)
        if !segment.isEmpty { onSegment?(segment) }

        guard gen == generation else { return }     // 舊段落收尾，不影響目前段落
        partialText = ""

        if wantsRecording {
            // 連續快速失敗（例如模型未就緒）時停止，避免無限重啟
            if failed && segment.isEmpty && Date().timeIntervalSince(generationStart) < 1 {
                quickFailures += 1
                if quickFailures > 3 {
                    stop()
                    state = .error("辨識一直中斷，請稍後再試或重新開啟 App")
                    return
                }
            } else {
                quickFailures = 0
            }
            beginSegment()
        }
    }

    private func scheduleSilenceTimer(for gen: Int) {
        silenceTimer?.cancel()
        let interval = silenceInterval
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self, gen == self.generation,
                  !(self.partials[gen] ?? "").isEmpty else { return }
            self.rollover()
        }
    }

    // MARK: - Permissions

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }
}
