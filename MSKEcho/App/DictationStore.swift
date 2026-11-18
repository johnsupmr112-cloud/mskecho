import Foundation
import SwiftData
import Observation
import UIKit

/// 串起：辨識引擎 → 後處理 → 草稿 → 定稿 → 學習
@MainActor
@Observable
final class DictationStore {
    let engine = SpeechEngine()
    let vocab = VocabBundle.shared

    /// 編輯器裡的文字（你可以邊錄邊改）
    var draft = ""
    private(set) var rawText = ""
    private(set) var autoText = ""
    private(set) var currentReport: DictationReport?

    private(set) var processor: PostProcessor
    private(set) var isTraining = false
    private(set) var lastMessage: String?

    @ObservationIgnored
    private let defaults = UserDefaults.standard
    static let retrainEvery = 10

    var lastTrainedAt: Date? {
        get { access(keyPath: \.lastTrainedAt); return defaults.object(forKey: "lastTrainedAt") as? Date }
        set { withMutation(keyPath: \.lastTrainedAt) { defaults.set(newValue, forKey: "lastTrainedAt") } }
    }
    var finalizedSinceTraining: Int {
        get { access(keyPath: \.finalizedSinceTraining); return defaults.integer(forKey: "finalizedSinceTraining") }
        set { withMutation(keyPath: \.finalizedSinceTraining) { defaults.set(newValue, forKey: "finalizedSinceTraining") } }
    }
    var addCJKLatinSpacing: Bool {
        get { access(keyPath: \.addCJKLatinSpacing); return defaults.object(forKey: "cjkSpacing") as? Bool ?? true }
        set { withMutation(keyPath: \.addCJKLatinSpacing) { defaults.set(newValue, forKey: "cjkSpacing") } }
    }

    init() {
        processor = PostProcessor(vocab: VocabBundle.shared)
        engine.onSegment = { [weak self] raw in self?.appendSegment(raw) }
    }

    // MARK: - 啟動

    func bootstrap(context: ModelContext) async {
        refreshProcessing(context: context)
        guard CustomLMTrainer.hasTrainingAsset else { return }
        do {
            try await CustomLMTrainer.prepare()
            engine.update(languageModel: CustomLMTrainer.configuration)
        } catch {
            lastMessage = "自訂語言模型載入失敗，暫用一般模型：\(error.localizedDescription)"
        }
    }

    /// 詞彙或規則變動後呼叫：重建後處理器與 contextualStrings（下一段錄音立即生效）
    func refreshProcessing(context: ModelContext) {
        let rules = (try? context.fetch(FetchDescriptor<LearnedRule>(predicate: #Predicate { $0.isActive }))) ?? []
        let terms = (try? context.fetch(FetchDescriptor<UserTerm>())) ?? []

        let learned = rules.map { PostProcessor.Replacement(from: $0.from, to: $0.to) }
        let aliases = terms.flatMap { t in t.aliases.map { PostProcessor.Replacement(from: $0, to: t.text) } }
        processor = PostProcessor(vocab: vocab, learned: learned, userAliases: aliases,
                                  addCJKLatinSpacing: addCJKLatinSpacing)
        engine.update(contextualStrings: vocab.contextualStrings(userTerms: terms.map(\.text) + rules.map(\.to)))
    }

    // MARK: - 口述

    private func appendSegment(_ raw: String) {
        let processed = processor.process(raw)
        rawText = Self.joinSegment(rawText, raw)
        autoText = Self.joinSegment(autoText, processed)
        draft = Self.joinSegment(draft, processed)
    }

    static func joinSegment(_ base: String, _ addition: String) -> String {
        guard let last = base.last else { return addition }
        guard let first = addition.first else { return base }
        if last.isNewline || first.isNewline { return base + addition }
        if (last.isASCII && (last.isLetter || last.isNumber)) && (first.isASCII && (first.isLetter || first.isNumber)) {
            return base + " " + addition
        }
        return base + addition
    }

    func newReport() {
        if engine.isRecording { engine.stop() }
        draft = ""; rawText = ""; autoText = ""; currentReport = nil
    }

    func load(_ report: DictationReport) {
        if engine.isRecording { engine.stop() }
        currentReport = report
        rawText = report.rawText
        autoText = report.autoText
        draft = report.finalText
    }

    func copyDraft() {
        UIPasteboard.general.string = draft
        lastMessage = "已複製到剪貼簿"
    }

    // MARK: - 定稿 + 學習

    /// 儲存定稿、複製、從你的修改中學規則；每 10 份自動重訓語言模型
    func finalize(context: ModelContext) {
        if engine.isRecording { engine.stop() }
        let finalText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        let report = currentReport ?? DictationReport()
        if currentReport == nil { context.insert(report) }
        report.rawText = rawText
        report.autoText = autoText
        report.finalText = finalText
        report.updatedAt = .now
        let firstTime = !report.isFinalized
        report.isFinalized = true
        currentReport = report

        let candidates = CorrectionLearner.learn(auto: autoText, final: finalText)
        var newCount = 0
        for c in candidates {
            let key = LearnedRule.makeKey(from: c.from, to: c.to)
            let existing = try? context.fetch(FetchDescriptor<LearnedRule>(predicate: #Predicate { $0.key == key })).first
            if let rule = existing {
                rule.hitCount += 1
                rule.lastSeen = .now
            } else {
                context.insert(LearnedRule(from: c.from, to: c.to))
                newCount += 1
            }
        }
        try? context.save()

        UIPasteboard.general.string = finalText
        lastMessage = newCount > 0
            ? "已定稿並複製。學到 \(newCount) 個修正候選，請到「學習」頁確認。"
            : "已定稿並複製。"

        if firstTime { finalizedSinceTraining += 1 }
        if finalizedSinceTraining >= Self.retrainEvery {
            Task { await retrain(context: context) }
        }
    }

    func retrain(context: ModelContext) async {
        guard !isTraining else { return }
        isTraining = true
        defer { isTraining = false }

        let reports = (try? context.fetch(FetchDescriptor<DictationReport>(predicate: #Predicate { $0.isFinalized }))) ?? []
        let rules = (try? context.fetch(FetchDescriptor<LearnedRule>(predicate: #Predicate { $0.isActive }))) ?? []
        let terms = (try? context.fetch(FetchDescriptor<UserTerm>())) ?? []

        let input = CustomLMTrainer.Input(
            vocab: vocab,
            userTerms: terms.map(\.text),
            learnedTargets: rules.map(\.to),
            finalizedReports: reports.map(\.finalText)
        )
        do {
            let (config, summary) = try await CustomLMTrainer.train(input)
            engine.update(languageModel: config)
            lastTrainedAt = summary.date
            finalizedSinceTraining = 0
            lastMessage = "語言模型已更新（\(summary.phraseCount) 個片語，含 \(summary.reportSentences) 句你的定稿）"
        } catch {
            lastMessage = "訓練失敗：\(error.localizedDescription)（仍可使用詞彙偏置與修正規則）"
        }
    }

    func clearMessage() { lastMessage = nil }
}
