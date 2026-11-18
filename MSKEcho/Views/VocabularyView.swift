import SwiftUI
import SwiftData

struct VocabularyView: View {
    @Environment(DictationStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \UserTerm.createdAt, order: .reverse) private var userTerms: [UserTerm]
    @State private var showAdd = false

    private let categoryNames: [String: String] = [
        "shoulder": "肩", "elbow": "肘", "wrist_hand": "腕／手", "hip": "髖", "knee": "膝",
        "ankle_foot": "踝／足", "nerve": "神經", "finding": "影像描述", "procedure": "處置／注射",
        "impression": "結論用語", "zh": "中文常用", "user": "個人（已併入）"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(userTerms) { term in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.text).bold()
                            if !term.aliases.isEmpty {
                                Text("常被聽成：" + term.aliases.joined(separator: "、"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        idx.map { userTerms[$0] }.forEach { context.delete($0) }
                        try? context.save()
                        store.refreshProcessing(context: context)
                    }
                } header: {
                    Text("我的詞彙（\(userTerms.count)）")
                } footer: {
                    Text("新增後下一段錄音立即生效，並在下次訓練時加入語言模型。")
                }

                Section("內建 MSK 詞庫（\(store.vocab.termCount) 詞）") {
                    ForEach(store.vocab.terms.keys.sorted(), id: \.self) { key in
                        DisclosureGroup("\(categoryNames[key] ?? key)（\(store.vocab.terms[key]?.count ?? 0)）") {
                            ForEach(store.vocab.terms[key] ?? [], id: \.self) { Text($0).font(.callout) }
                        }
                    }
                    DisclosureGroup("縮寫（\(store.vocab.abbreviations.count)）") {
                        ForEach(store.vocab.abbreviations, id: \.abbr) { a in
                            LabeledContent(a.abbr, value: a.expansion).font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("詞庫")
            .toolbar {
                Button("新增", systemImage: "plus") { showAdd = true }
            }
            .sheet(isPresented: $showAdd) {
                AddTermSheet { text, aliases in
                    guard !userTerms.contains(where: { $0.text == text }) else { return }
                    context.insert(UserTerm(text: text, aliases: aliases))
                    try? context.save()
                    store.refreshProcessing(context: context)
                }
            }
        }
    }
}

private struct AddTermSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var aliases = ""
    var onSave: (String, [String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("正確寫法") {
                    TextField("例如：Hoffa's fat pad、旋轉肌袖", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("例如：哈法 fat pad, hofa fat pad", text: $aliases, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("常被辨識成（選填，逗號分隔）")
                } footer: {
                    Text("出現這些錯字時會自動改成正確寫法。")
                }
            }
            .navigationTitle("新增詞彙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let a = aliases.split(whereSeparator: { ",，、\n".contains($0) })
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        onSave(t, a)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
