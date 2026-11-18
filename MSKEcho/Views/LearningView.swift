import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 「越用越準」控制台：修正規則候選、已採用規則、語言模型訓練
struct LearningView: View {
    @Environment(DictationStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<LearnedRule> { !$0.isActive }, sort: \LearnedRule.hitCount, order: .reverse)
    private var candidates: [LearnedRule]
    @Query(filter: #Predicate<LearnedRule> { $0.isActive }, sort: \LearnedRule.from)
    private var activeRules: [LearnedRule]
    @Query(filter: #Predicate<DictationReport> { $0.isFinalized }) private var finalized: [DictationReport]

    @State private var includeSentences = false
    @State private var exportFile: ExportFile?
    @State private var showImporter = false
    @State private var syncMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    LabeledContent("已定稿報告", value: "\(finalized.count) 份")
                    LabeledContent("距上次訓練新增", value: "\(store.finalizedSinceTraining) / \(DictationStore.retrainEvery)")
                    if let date = store.lastTrainedAt {
                        LabeledContent("上次訓練", value: date.formatted(.dateTime.month().day().hour().minute()))
                    }
                    Button {
                        Task { await store.retrain(context: context) }
                    } label: {
                        HStack {
                            Label("立即重新訓練語言模型", systemImage: "sparkles")
                            if store.isTraining { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(store.isTraining)
                } header: {
                    Text("個人化語言模型")
                } footer: {
                    Text("在 iPhone 本機用詞庫與你的定稿句子訓練，每 \(DictationStore.retrainEvery) 份定稿自動更新一次。")
                }

                Section {
                    if candidates.isEmpty {
                        Text("目前沒有候選。定稿時你修改過的詞會出現在這裡。").foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { rule in
                        RuleRow(rule: rule)
                            .swipeActions(edge: .leading) {
                                Button("採用") { setActive(rule, true) }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("忽略", role: .destructive) { delete(rule) }
                            }
                    }
                } header: {
                    Text("修正候選（右滑採用、左滑忽略）")
                } footer: {
                    Text("左右側、嚴重度、有無等語意詞的修改不會被學成規則，避免改錯臨床內容。")
                }

                Section("已採用規則") {
                    ForEach(activeRules) { rule in
                        RuleRow(rule: rule)
                            .swipeActions {
                                Button("停用") { setActive(rule, false) }.tint(.orange)
                                Button("刪除", role: .destructive) { delete(rule) }
                            }
                    }
                }

                Section {
                    Button {
                        do {
                            exportFile = ExportFile(url: try LearningSync.export(context: context, includeSentences: includeSentences))
                        } catch {
                            syncMessage = "匯出失敗：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("匯出學習資料（AirDrop 到 Mac）", systemImage: "square.and.arrow.up")
                    }
                    Toggle("一併匯出定稿句子", isOn: $includeSentences)
                    Button {
                        showImporter = true
                    } label: {
                        Label("匯入學習資料", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("同步與備份")
                } footer: {
                    Text("匯出：個人詞彙＋修正規則（含未採用候選）。定稿句子可能含臨床內容，只在確認無病人識別資料時才勾選。匯入會合併，不會刪除手機上的資料。")
                }

                Section("格式") {
                    Toggle("中英文之間自動加空白", isOn: $store.addCJKLatinSpacing)
                        .onChange(of: store.addCJKLatinSpacing) { store.refreshProcessing(context: context) }
                }
            }
            .navigationTitle("學習")
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url).presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        syncMessage = try LearningSync.importFile(url, context: context).summary
                        store.refreshProcessing(context: context)
                    } catch {
                        syncMessage = "匯入失敗：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    syncMessage = "無法開啟檔案：\(error.localizedDescription)"
                }
            }
            .alert(syncMessage ?? "", isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } })) {
                Button("好") { syncMessage = nil }
            }
        }
    }

    private func setActive(_ rule: LearnedRule, _ active: Bool) {
        rule.isActive = active
        try? context.save()
        store.refreshProcessing(context: context)
    }

    private func delete(_ rule: LearnedRule) {
        context.delete(rule)
        try? context.save()
        store.refreshProcessing(context: context)
    }
}

private struct RuleRow: View {
    let rule: LearnedRule
    var body: some View {
        HStack {
            Text(rule.from).strikethrough().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption)
            Text(rule.to).bold()
            Spacer()
            Text("×\(rule.hitCount)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
