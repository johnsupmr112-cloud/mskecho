import SwiftUI
import SwiftData

struct ReportListView: View {
    @Environment(DictationStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \DictationReport.updatedAt, order: .reverse) private var reports: [DictationReport]
    var onOpen: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(reports) { report in
                    NavigationLink {
                        ReportDetailView(report: report, onOpen: onOpen)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.title).lineLimit(1)
                            HStack {
                                Text(report.updatedAt, format: .dateTime.month().day().hour().minute())
                                if !report.isFinalized { Text("草稿").foregroundStyle(.orange) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { reports[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
            .overlay {
                if reports.isEmpty {
                    ContentUnavailableView("尚無報告", systemImage: "doc.text",
                                           description: Text("口述後按「定稿」就會存在這裡。\n報告貼回 HIS 後可左滑刪除。"))
                }
            }
            .navigationTitle("報告")
        }
    }
}

struct ReportDetailView: View {
    @Environment(DictationStore.self) private var store
    let report: DictationReport
    var onOpen: () -> Void
    @State private var showRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(report.finalText).textSelection(.enabled)
                DisclosureGroup("辨識原文（除錯用）", isExpanded: $showRaw) {
                    Text(report.rawText).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("複製", systemImage: "doc.on.doc") { UIPasteboard.general.string = report.finalText }
            Button("編輯", systemImage: "pencil") { store.load(report); onOpen() }
        }
    }
}
