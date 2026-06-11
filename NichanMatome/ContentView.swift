import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                NavigationStack {
                    FeedListView()
                        .navigationTitle("まとめ・よみきり")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task { await store.refresh() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(store.isLoading)
                            }
                        }
                }
                .tabItem {
                    Label("読む", systemImage: "list.bullet")
                }

                NavigationStack {
                    SavedListView()
                        .navigationTitle("保存")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("保存", systemImage: "bookmark")
                }

                NavigationStack {
                    SourcesView()
                        .navigationTitle("配信元")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("配信元", systemImage: "antenna.radiowaves.left.and.right")
                }

                NavigationStack {
                    SettingsView()
                        .navigationTitle("設定")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
            }

            AdMobBannerSlotView(placement: .bottom)
                .frame(height: 50)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdMobBannerSlotView(placement: .top)
                .frame(height: 50)
        }
        .tint(.matomeAccent)
        .task {
            if store.articles.isEmpty {
                await store.refresh()
            }
        }
    }
}

// MARK: - Feed List

private struct FeedListView: View {
    @EnvironmentObject private var store: FeedStore
    @State private var searchText = ""
    @State private var selectedCategory: ArticleCategory = .all

    private var allArticlesSorted: [Article] {
        store.articles.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private var filteredArticles: [Article] {
        var result = store.articles
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query)
                || $0.sourceName.lowercased().contains(query)
            }
        }
        return result.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private func categoryCount(_ cat: ArticleCategory) -> Int {
        if cat == .all { return store.articles.count }
        return store.articles.filter { $0.category == cat }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category tabs with counts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ArticleCategory.allCases) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            HStack(spacing: 3) {
                                Text(cat.rawValue)
                                    .font(.caption.weight(.bold))
                                let count = categoryCount(cat)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            selectedCategory == cat
                                                ? Color.white.opacity(0.3)
                                                : Color(.systemGray4),
                                            in: Capsule()
                                        )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(selectedCategory == cat ? Color.matomeAccent : .clear)
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(Color.surfaceSecondary)

            // Article count
            HStack {
                Text("\(filteredArticles.count)件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.surfaceSecondary.opacity(0.5))

            // Article list with pull-to-refresh
            List {
                ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                    ArticleRowCompact(article: article)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.visible)

                    if index > 0 && (index + 1).isMultiple(of: 15) {
                        InlineAdRow(placement: (index + 1).isMultiple(of: 30) ? .inline : .detail)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await store.refresh()
            }
        }
        .searchable(text: $searchText, prompt: "検索")
        .alert("読み込みエラー", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Compact Article Row (one-liner style)

private struct ArticleRowCompact: View {
    @EnvironmentObject private var store: FeedStore
    let article: Article
    @State private var showsArticle = false

    var body: some View {
        Button {
            showsArticle = true
        } label: {
            HStack(spacing: 6) {
                // Category badge
                Text(article.category.shortLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32)
                    .padding(.vertical, 2)
                    .background(article.category.color, in: RoundedRectangle(cornerRadius: 3))

                // NEW badge
                if store.isNew(article) {
                    Text("NEW")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.red, in: RoundedRectangle(cornerRadius: 2))
                }

                // Title
                Text(article.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                // Source + time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(article.sourceName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(article.shortTimeText)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 56)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                showsArticle = true
            } label: {
                Label("開く", systemImage: "safari")
            }

            Button {
                store.toggleSaved(article)
            } label: {
                Label(
                    store.isSaved(article) ? "保存を解除" : "あとで読む",
                    systemImage: store.isSaved(article) ? "bookmark.slash" : "bookmark"
                )
            }

            ShareLink(item: article.link) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showsArticle) {
            ArticleDetailSheet(article: article)
        }
    }
}

// MARK: - Article Detail Sheet

private struct ArticleDetailSheet: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    let article: Article

    var body: some View {
        NavigationStack {
            ArticleWebView(url: article.link)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(article.sourceName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: article.link) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            store.toggleSaved(article)
                        } label: {
                            Image(systemName: store.isSaved(article) ? "bookmark.fill" : "bookmark")
                        }
                    }
                }
        }
    }
}

// MARK: - Saved List

private struct SavedListView: View {
    @EnvironmentObject private var store: FeedStore

    var body: some View {
        Group {
            if store.savedArticles.isEmpty {
                ContentUnavailableView("保存した記事はまだありません", systemImage: "bookmark")
            } else {
                List(store.savedArticles) { article in
                    ArticleRowCompact(article: article)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Inline Ad

private struct InlineAdRow: View {
    let placement: AdPlacement

    var body: some View {
        AdMobBannerSlotView(placement: placement)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Sources View

private struct SourcesView: View {
    @EnvironmentObject private var store: FeedStore
    @State private var searchText = ""
    @State private var editorMode: SourceEditorMode?
    @State private var showsResetConfirmation = false

    private var filteredSources: [FeedSource] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.sources }
        return store.sources.filter {
            $0.name.lowercased().contains(query)
            || $0.feedURL.absoluteString.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { editorMode = .add } label: {
                        Label("追加", systemImage: "plus")
                    }
                    Spacer()
                    Menu {
                        Button("すべてオン") { store.setAllSourcesEnabled(true) }
                        Button("すべてオフ") { store.setAllSourcesEnabled(false) }
                        Button("初期配信元に戻す", role: .destructive) { showsResetConfirmation = true }
                    } label: {
                        Label("一括", systemImage: "ellipsis.circle")
                    }
                }
            }

            Section("\(filteredSources.count)件") {
                ForEach(filteredSources) { source in
                    Toggle(isOn: Binding(
                        get: { source.isEnabled },
                        set: { store.updateSource(source, isEnabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.subheadline.weight(.semibold))
                            Text(source.feedURL.host ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.removeSource(source) } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button { editorMode = .edit(source) } label: {
                            Label("編集", systemImage: "pencil")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "配信元を検索")
        .sheet(item: $editorMode) { mode in
            SourceEditorView(mode: mode)
        }
        .confirmationDialog("初期配信元に戻しますか？", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("初期配信元に戻す", role: .destructive) { store.resetToDefaultSources() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("追加・編集した配信元は消えます。保存した記事とメモは残ります。")
        }
    }
}

private enum SourceEditorMode: Identifiable {
    case add
    case edit(FeedSource)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let source): return source.id.uuidString
        }
    }

    var source: FeedSource? {
        if case .edit(let source) = self { return source }
        return nil
    }
}

private struct SourceEditorView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    let mode: SourceEditorMode
    @State private var name: String
    @State private var urlText: String

    init(mode: SourceEditorMode) {
        self.mode = mode
        _name = State(initialValue: mode.source?.name ?? "")
        _urlText = State(initialValue: mode.source?.feedURL.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("サイト名", text: $name)
                TextField("RSS URL", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle(mode.source == nil ? "追加" : "編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let source = mode.source {
                            if store.updateSource(source, name: name, urlText: urlText) { dismiss() }
                        } else if store.addSource(name: name, urlText: urlText) { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Category Extensions

extension ArticleCategory {
    var shortLabel: String {
        switch self {
        case .all: return "全"
        case .news: return "報"
        case .internet: return "ネ"
        case .entertainment: return "芸"
        case .gameAnime: return "ゲ"
        case .money: return "金"
        case .life: return "暮"
        case .other: return "他"
        }
    }

    var color: Color {
        switch self {
        case .all: return .gray
        case .news: return .red
        case .internet: return .blue
        case .entertainment: return .purple
        case .gameAnime: return .green
        case .money: return .orange
        case .life: return .teal
        case .other: return .gray
        }
    }
}

// MARK: - Article Extension

extension Article {
    var shortTimeText: String {
        guard let publishedAt else { return "" }
        let interval = Date.now.timeIntervalSince(publishedAt)
        if interval < 3600 { return "\(Int(interval / 60))分前" }
        if interval < 86400 { return "\(Int(interval / 3600))時間前" }
        return "\(Int(interval / 86400))日前"
    }
}

// MARK: - Colors (Dark Mode compatible)

extension Color {
    static let matomePaper = Color(.systemBackground)
    static let matomeInk = Color.primary
    static let matomeText = Color.primary
    static let matomeAccent = Color(red: 0.76, green: 0.22, blue: 0.16)

    static var surfaceSecondary: Color {
        Color(.systemGray6)
    }
}

#Preview {
    ContentView()
        .environmentObject(FeedStore())
}
