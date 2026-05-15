import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FeedStore

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                NavigationStack {
                    DenseFeedView()
                        .navigationTitle("まとめ・よみきり")
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
                    Label("読む", systemImage: "rectangle.grid.1x2")
                }

                NavigationStack {
                    InsightsView()
                        .navigationTitle("整理")
                }
                .tabItem {
                    Label("整理", systemImage: "chart.line.uptrend.xyaxis")
                }

                NavigationStack {
                    SavedArticleView()
                        .navigationTitle("あとで読む")
                }
                .tabItem {
                    Label("保存", systemImage: "bookmark")
                }

                NavigationStack {
                    SourcesView()
                        .navigationTitle("配信元")
                }
                .tabItem {
                    Label("配信元", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            AdMobBannerSlotView(placement: .bottom)
                .padding(.top, 6)
                .background(Color.matomePaper)
        }
        .tint(.matomeInk)
        .task {
            if store.articles.isEmpty {
                await store.refresh()
            }
        }
    }
}

private struct DenseFeedView: View {
    @EnvironmentObject private var store: FeedStore
    @State private var searchText = ""
    @State private var selectedCategory: ArticleCategory = .all
    @State private var selectedScope: ArticleTimeScope = .all
    @State private var sortMode: ArticleSortMode = .newest
    @State private var compactRows = true
    @State private var hidesFatigue = false

    private var filteredArticles: [Article] {
        var result = store.articles

        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }
        result = result.filter { selectedScope.includes($0.publishedAt) }
        if hidesFatigue {
            result = result.filter { store.fatigueScore(for: $0) < 40 }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query)
                || $0.summary.lowercased().contains(query)
                || $0.sourceName.lowercased().contains(query)
            }
        }

        switch sortMode {
        case .newest:
            return result.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        case .source:
            return result.sorted {
                if $0.sourceName == $1.sourceName {
                    return ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
                }
                return $0.sourceName < $1.sourceName
            }
        case .titleLength:
            return result.sorted { ($0.title.count + $0.summary.count) > ($1.title.count + $1.summary.count) }
        }
    }

    var body: some View {
        List {
            Section {
                DashboardPanel(visibleCount: filteredArticles.count)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                FilterPanel(
                    selectedCategory: $selectedCategory,
                    selectedScope: $selectedScope,
                    sortMode: $sortMode,
                    compactRows: $compactRows,
                    hidesFatigue: $hidesFatigue
                )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if filteredArticles.isEmpty {
                ContentUnavailableView(
                    store.isLoading ? "記事を読み込み中" : "記事がありません",
                    systemImage: store.isLoading ? "arrow.triangle.2.circlepath" : "line.3.horizontal.decrease.circle",
                    description: Text(store.isLoading ? "少し待ってから表示します。" : "配信元や通信環境を確認してください。")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                        VStack(spacing: 8) {
                            ArticleRow(article: article, compact: compactRows)

                            if shouldShowInlineAd(after: index) {
                                InlineAdRow(placement: inlineAdPlacement(after: index))
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("記事 \(filteredArticles.count)件")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.matomePaper)
        .searchable(text: $searchText, prompt: "タイトル、要約、サイトで検索")
        .overlay {
            if store.isLoading && !store.articles.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("読み込みエラー", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func shouldShowInlineAd(after index: Int) -> Bool {
        index > 0 && (index + 1).isMultiple(of: 8)
    }

    private func inlineAdPlacement(after index: Int) -> AdPlacement {
        (index + 1).isMultiple(of: 16) ? .inline : .detail
    }
}

private struct DashboardPanel: View {
    @EnvironmentObject private var store: FeedStore
    let visibleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("いま読める記事")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(visibleCount)件")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(Color.matomeText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("配信元 \(store.sources.filter(\.isEnabled).count)")
                    Text("保存 \(store.savedArticles.count)")
                    if let lastUpdatedAt = store.lastUpdatedAt {
                        Text(lastUpdatedAt.formatted(date: .omitted, time: .shortened))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            MetricStrip(items: [
                ("総記事", "\(store.articles.count)"),
                ("今日", "\(store.articles.filter { ArticleTimeScope.today.includes($0.publishedAt) }.count)"),
                ("48時間", "\(store.articles.filter { ArticleTimeScope.twoDays.includes($0.publishedAt) }.count)"),
                ("サイト", "\(store.sourceBreakdown.count)")
            ])

            if !store.categoryBreakdown.isEmpty {
                FlowLine(title: "カテゴリ", values: store.categoryBreakdown.map { "\($0.category.rawValue) \($0.count)" })
            }

            if !store.hotKeywords.isEmpty {
                FlowLine(title: "よく出る言葉", values: store.hotKeywords)
            }

            if !store.sourceBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("サイト別")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(store.sourceBreakdown.prefix(5), id: \.name) { source in
                        HStack(spacing: 8) {
                            Text(source.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color.matomeInk.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.matomeAccent)
                                            .frame(width: proxy.size.width * CGFloat(source.count) / CGFloat(max(store.articles.count, 1)))
                                    }
                            }
                            .frame(height: 8)
                            Text("\(source.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MetricStrip: View {
    let items: [(String, String)]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 2) {
                        Text(item.1)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.matomeText)
                        Text(item.0)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.matomePaper, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct FlowLine: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.matomeText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.matomePaper, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct InsightsView: View {
    @EnvironmentObject private var store: FeedStore
    @State private var fatigueWord = ""

    var body: some View {
        List {
            Section {
                InsightHero()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section("3分まとめ") {
                ForEach(store.threeMinuteArticles) { article in
                    ArticleRow(article: article, compact: true)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 3)
                }
            }

            Section("話題クラスター") {
                if store.topicClusters.isEmpty {
                    ContentUnavailableView("近い話題はまだ見つかりません", systemImage: "square.stack.3d.up")
                } else {
                    ForEach(store.topicClusters.prefix(12)) { cluster in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cluster.title)
                                    .font(.headline)
                                Spacer()
                                Text("熱量 \(cluster.heat)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.matomeAccent)
                            }

                            Text("\(cluster.articles.count)件 / \(cluster.sourceCount)サイト")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(cluster.articles.prefix(3)) { article in
                                Text(article.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(Color.matomeText)
                            }
                        }
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            Section("偏りメーター") {
                ForEach(store.biasMetrics) { metric in
                    HStack(spacing: 10) {
                        Label(metric.category.rawValue, systemImage: metric.category.symbolName)
                            .font(.caption.weight(.semibold))
                            .frame(width: 120, alignment: .leading)

                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.matomeInk.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.matomeAccent)
                                        .frame(width: proxy.size.width * metric.ratio)
                                }
                        }
                        .frame(height: 9)

                        Text("\(metric.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("NGワード") {
                HStack {
                    TextField("例: 炎上", text: $fatigueWord)
                    Button("追加") {
                        store.addFatigueWord(fatigueWord)
                        fatigueWord = ""
                    }
                }

                ForEach(store.fatigueWords, id: \.self) { word in
                    Text(word)
                }
                .onDelete(perform: store.removeFatigueWords)
            }

            Section("読後メモ") {
                Text("記事カードのメモボタンから、自分用のタグや感想を残せます。保存したメモは端末内に残ります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.matomePaper)
    }
}

private struct InsightHero: View {
    @EnvironmentObject private var store: FeedStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RSSを読みやすく整理")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.matomeText)

            Text("話題の重なり、カテゴリの偏り、あとで読みたい記事をまとめて見られます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MetricStrip(items: [
                ("配信元", "\(store.sources.count)"),
                ("有効", "\(store.sources.filter(\.isEnabled).count)"),
                ("クラスター", "\(store.topicClusters.count)"),
                ("メモ", "\(store.articleNotes.count)")
            ])
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FilterPanel: View {
    @Binding var selectedCategory: ArticleCategory
    @Binding var selectedScope: ArticleTimeScope
    @Binding var sortMode: ArticleSortMode
    @Binding var compactRows: Bool
    @Binding var hidesFatigue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ArticleCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(category.rawValue, systemImage: category.symbolName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(selectedCategory == category ? Color.matomeInk : .white, in: Capsule())
                                .foregroundStyle(selectedCategory == category ? .white : Color.matomeText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Picker("期間", selection: $selectedScope) {
                    ForEach(ArticleTimeScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)

                Picker("並び", selection: $sortMode) {
                    ForEach(ArticleSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Toggle(isOn: $compactRows) {
                    Image(systemName: compactRows ? "list.bullet" : "text.alignleft")
                }
                .labelsHidden()

                Toggle(isOn: $hidesFatigue) {
                    Image(systemName: "moon.zzz")
                }
                .labelsHidden()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SavedArticleView: View {
    @EnvironmentObject private var store: FeedStore

    var body: some View {
        Group {
            if store.savedArticles.isEmpty {
                ContentUnavailableView("保存した記事はまだありません", systemImage: "bookmark")
            } else {
                List(store.savedArticles) { article in
                    ArticleRow(article: article, compact: false)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 3)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.matomePaper)
    }
}

private struct InlineAdRow: View {
    let placement: AdPlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("広告")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            AdMobBannerSlotView(placement: placement)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

private struct ArticleRow: View {
    @EnvironmentObject private var store: FeedStore
    let article: Article
    let compact: Bool
    @State private var showsArticle = false
    @State private var showsNote = false

    var body: some View {
        Button {
            showsArticle = true
        } label: {
            VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                HStack(spacing: 7) {
                    Label(article.category.rawValue, systemImage: article.category.symbolName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.matomeInk, in: Capsule())

                    Text(article.sourceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.matomeAccent)
                        .lineLimit(1)

                    Text(article.relativeDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        store.toggleSaved(article)
                    } label: {
                        Image(systemName: store.isSaved(article) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.matomeAccent)

                    Button {
                        showsNote = true
                    } label: {
                        Image(systemName: store.note(for: article).isEmpty ? "note.text" : "note.text.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.matomeInk)
                }

                Text(article.title)
                    .font(compact ? .subheadline.weight(.bold) : .headline)
                    .foregroundStyle(Color.matomeText)
                    .lineLimit(compact ? 2 : 3)
                    .multilineTextAlignment(.leading)

                if !compact, !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 10) {
                    Label(article.hostText, systemImage: "link")
                    Label("\(article.estimatedReadMinutes)分", systemImage: "clock")
                    if store.fatigueScore(for: article) >= 40 {
                        Label("疲れ \(store.fatigueScore(for: article))", systemImage: "moon.zzz")
                    }
                    if let publishedAt = article.publishedAt {
                        Text(publishedAt.formatted(date: .numeric, time: .shortened))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(compact ? 11 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsArticle) {
            ArticleWebView(url: article.link)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsNote) {
            NoteEditorView(article: article)
        }
    }
}

private struct NoteEditorView: View {
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    let article: Article
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("記事") {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                }

                Section("メモ") {
                    TextEditor(text: $note)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("読後メモ")
            .onAppear {
                note = store.note(for: article)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateNote(note, for: article)
                        dismiss()
                    }
                }
            }
        }
    }
}

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
        Form {
            Section("操作") {
                HStack {
                    Button {
                        editorMode = .add
                    } label: {
                        Label("追加", systemImage: "plus")
                    }

                    Spacer()

                    Menu {
                        Button("すべてオン") {
                            store.setAllSourcesEnabled(true)
                        }

                        Button("すべてオフ") {
                            store.setAllSourcesEnabled(false)
                        }

                        Button("初期配信元に戻す", role: .destructive) {
                            showsResetConfirmation = true
                        }
                    } label: {
                        Label("一括", systemImage: "ellipsis.circle")
                    }
                }

                LabeledContent("登録数", value: "\(store.sources.count)件")
                LabeledContent("有効", value: "\(store.sources.filter(\.isEnabled).count)件")
            }

            Section("一覧") {
                if filteredSources.isEmpty {
                    ContentUnavailableView("配信元が見つかりません", systemImage: "magnifyingglass")
                } else {
                    ForEach(filteredSources) { source in
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { source.isEnabled },
                                set: { store.updateSource(source, isEnabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(source.feedURL.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Button {
                                editorMode = .edit(source)
                            } label: {
                                Image(systemName: "pencil")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                store.removeSource(source)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("データの扱い") {
                Text("RSSの見出し、要約、リンクを読み込みます。記事本文は元サイトで開きます。保存記事とメモは端末内に保存します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "配信元を検索")
        .scrollContentBackground(.hidden)
        .background(Color.matomePaper)
        .sheet(item: $editorMode) { mode in
            SourceEditorView(mode: mode)
        }
        .confirmationDialog("初期配信元に戻しますか？", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("初期配信元に戻す", role: .destructive) {
                store.resetToDefaultSources()
            }
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
        case .add:
            return "add"
        case .edit(let source):
            return source.id.uuidString
        }
    }

    var source: FeedSource? {
        if case .edit(let source) = self {
            return source
        }
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
        let source = mode.source
        _name = State(initialValue: source?.name ?? "")
        _urlText = State(initialValue: source?.feedURL.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("配信元") {
                    TextField("サイト名", text: $name)
                    TextField("RSS URL", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("RSS URLは http または https で始まるものを入力してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode.source == nil ? "配信元を追加" : "配信元を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let source = mode.source {
                            if store.updateSource(source, name: name, urlText: urlText) {
                                dismiss()
                            }
                        } else if store.addSource(name: name, urlText: urlText) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

extension Color {
    static let matomePaper = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let matomeInk = Color(red: 0.14, green: 0.20, blue: 0.18)
    static let matomeText = Color(red: 0.10, green: 0.11, blue: 0.10)
    static let matomeAccent = Color(red: 0.76, green: 0.22, blue: 0.16)
}

#Preview {
    ContentView()
        .environmentObject(FeedStore())
}
