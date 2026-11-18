import SwiftUI
import SwiftData

struct DictationView: View {
    @Environment(DictationStore.self) private var store
    @Environment(\.modelContext) private var context
    @FocusState private var editorFocused: Bool

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 12) {
                statusBar

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $store.draft)
                        .focused($editorFocused)
                        .font(.system(.body, design: .default))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if store.draft.isEmpty && store.engine.partialText.isEmpty {
                        Text("按下麥克風開始口述。\n口令：「換行」「下一段」「句號」「逗號」")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if !store.engine.partialText.isEmpty {
                    Text(store.engine.partialText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }

                controls
            }
            .padding()
            .navigationTitle(store.currentReport == nil ? "新報告" : "編輯報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("新報告", systemImage: "square.and.pencil") { store.newReport() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("複製", systemImage: "doc.on.doc") { store.copyDraft() }
                        .disabled(store.draft.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { editorFocused = false }
                }
            }
            .alert(store.lastMessage ?? "", isPresented: Binding(
                get: { store.lastMessage != nil },
                set: { if !$0 { store.clearMessage() } })) {
                Button("好") { store.clearMessage() }
            }
            .animation(.easeOut(duration: 0.15), value: store.engine.partialText.isEmpty)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch store.engine.state {
            case .recording:
                Label("錄音中（離線）", systemImage: "record.circle").foregroundStyle(.red)
            case .idle:
                Label("待命", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .lineLimit(3)
            }
            Spacer()
            if store.engine.customModelActive {
                Label("個人化模型", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.tint)
            }
        }
        .font(.footnote)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                store.newReport()
            } label: {
                Image(systemName: "trash").font(.title2)
            }
            .disabled(store.draft.isEmpty)
            .accessibilityLabel("清除")

            Button {
                editorFocused = false
                Task { await store.engine.toggle() }
            } label: {
                Image(systemName: store.engine.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(store.engine.isRecording ? Color.red : Color.accentColor, in: Circle())
                    .shadow(radius: store.engine.isRecording ? 8 : 2)
            }
            .accessibilityLabel(store.engine.isRecording ? "停止錄音" : "開始錄音")

            Button {
                editorFocused = false
                store.finalize(context: context)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.seal").font(.title2)
                    Text("定稿").font(.caption2)
                }
            }
            .disabled(store.draft.isEmpty)
        }
        .padding(.bottom, 4)
    }
}
