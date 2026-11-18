import Foundation
import Speech

/// 裝置端「自訂語言模型」訓練（iOS 17+ SFCustomLanguageModelData）
/// 訓練資料＝內建詞庫 + 縮寫 + 樣板句 + 個人詞彙 + 已採用規則 + 你所有定稿報告的句子
/// 全部在 iPhone 上完成，不需網路。
enum CustomLMTrainer {
    static let clientIdentifier = "tw.flasg.mskecho"
    static let locale = Locale(identifier: "zh_TW")

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CustomLM", isDirectory: true)
    }
    static var assetURL: URL { directory.appendingPathComponent("training_data.bin") }
    static var languageModelURL: URL { directory.appendingPathComponent("msk.lm") }
    static var vocabularyURL: URL { directory.appendingPathComponent("msk.vocab") }

    static var configuration: SFSpeechLanguageModel.Configuration {
        SFSpeechLanguageModel.Configuration(languageModel: languageModelURL, vocabulary: vocabularyURL)
    }

    static var hasTrainingAsset: Bool { FileManager.default.fileExists(atPath: assetURL.path) }

    struct Input {
        var vocab: VocabBundle
        var userTerms: [String]
        var learnedTargets: [String]
        var finalizedReports: [String]
    }

    struct Summary {
        let phraseCount: Int
        let reportSentences: Int
        let date: Date
    }

    /// 建立訓練資料並編譯模型（數十秒，需在背景執行）
    static func train(_ input: Input) async throws -> (SFSpeechLanguageModel.Configuration, Summary) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let version = String(Int(Date().timeIntervalSince1970))
        let data = SFCustomLanguageModelData(locale: locale, identifier: clientIdentifier, version: version)
        var count = 0
        func add(_ phrase: String, _ n: Int) {
            let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return }
            data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: p, count: n))
            count += 1
        }

        // 權重：個人詞彙 / 已採用修正 > 你的定稿句子 > 內建詞庫 > 樣板句
        input.userTerms.forEach { add($0, 50) }
        input.learnedTargets.forEach { add($0, 30) }
        input.vocab.allTerms.forEach { add($0, 10) }
        input.vocab.expandedTemplates(limit: 3000).forEach { add($0, 1) }

        let sentences = input.finalizedReports.flatMap(splitSentences) + (input.vocab.trainingSentences ?? [])
        sentences.forEach { add($0, 5) }

        try await data.export(to: assetURL)
        try await prepare()
        return (configuration, Summary(phraseCount: count, reportSentences: sentences.count, date: .now))
    }

    /// App 啟動時呼叫：用既有訓練資料重新載入模型（有快取，通常很快）
    static func prepare() async throws {
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(
            for: assetURL,
            clientIdentifier: clientIdentifier,
            configuration: configuration
        )
    }

    static func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "。；;\n!?！？"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 && $0.count <= 120 }
    }
}
