import SwiftUI
import SwiftData

@main
struct MSKEchoApp: App {
    @State private var store = DictationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(for: [DictationReport.self, LearnedRule.self, UserTerm.self])
    }
}

struct RootView: View {
    @Environment(DictationStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DictationView()
                .tabItem { Label("口述", systemImage: "waveform") }
                .tag(0)
            ReportListView(onOpen: { tab = 0 })
                .tabItem { Label("報告", systemImage: "doc.text") }
                .tag(1)
            LearningView()
                .tabItem { Label("學習", systemImage: "brain") }
                .tag(2)
            VocabularyView()
                .tabItem { Label("詞庫", systemImage: "character.book.closed") }
                .tag(3)
        }
        .task { await store.bootstrap(context: context) }
    }
}
