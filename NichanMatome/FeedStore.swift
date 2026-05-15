import Foundation

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var articles: [Article] = []
    @Published var sources: [FeedSource] = []
    @Published var savedArticles: [Article] = []
    @Published var fatigueWords: [String] = []
    @Published var articleNotes: [String: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?

    private let sourcesKey = "matome.sources.v2"
    private let savedKey = "matome.savedArticles.v2"
    private let fatigueWordsKey = "matome.fatigueWords.v2"
    private let articleNotesKey = "matome.articleNotes.v2"
    private let refreshBatchSize = 6
    private let refreshSourceLimit = 14

    init() {
        if let savedSources = Self.load([FeedSource].self, key: sourcesKey) {
            sources = Self.merged(savedSources, with: FeedSource.defaults)
        } else {
            sources = FeedSource.defaults
        }
        savedArticles = Self.load([Article].self, key: savedKey) ?? []
        fatigueWords = Self.load([String].self, key: fatigueWordsKey) ?? ["炎上", "逮捕", "悲報", "批判", "事故"]
        articleNotes = Self.load([String: String].self, key: articleNotesKey) ?? [:]
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let enabledSources = Array(sources.filter(\.isEnabled).prefix(refreshSourceLimit))
        guard !enabledSources.isEmpty else {
            articles = []
            return
        }

        var fetchedArticles: [Article] = []
        var failures: [String] = []

        for startIndex in stride(from: 0, to: enabledSources.count, by: refreshBatchSize) {
            let endIndex = min(startIndex + refreshBatchSize, enabledSources.count)
            let batch = Array(enabledSources[startIndex..<endIndex])

            await withTaskGroup(of: Result<[Article], Error>.self) { group in
                for source in batch {
                    group.addTask {
                        do {
                            let request = URLRequest(url: source.feedURL, timeoutInterval: 7)
                            let (data, response) = try await URLSession.shared.data(for: request)
                            if let httpResponse = response as? HTTPURLResponse,
                               !(200..<400).contains(httpResponse.statusCode) {
                                throw URLError(.badServerResponse)
                            }
                            let parsed = try FeedParser(sourceName: source.name).parse(data)
                            return .success(parsed)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case .success(let items):
                        fetchedArticles.append(contentsOf: items)
                    case .failure(let error):
                        failures.append(error.localizedDescription)
                    }
                }
            }
        }

        articles = fetchedArticles
            .uniquedByLink()
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(160)
            .map { $0 }
        lastUpdatedAt = Date()

        if articles.isEmpty, !failures.isEmpty {
            errorMessage = "記事を読み込めませんでした。通信環境を確認して、もう一度お試しください。"
        }
    }

    @discardableResult
    func addSource(name: String, urlText: String) -> Bool {
        guard let url = validatedFeedURL(from: urlText) else {
            errorMessage = "RSSのURLを確認してください。"
            return false
        }

        guard !sources.contains(where: { $0.feedURL == url }) else {
            errorMessage = "このRSSはすでに追加されています。"
            return false
        }

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sources.append(FeedSource(name: displayName.isEmpty ? url.host ?? "RSS" : displayName, feedURL: url))
        persistSources()
        return true
    }

    func removeSources(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        persistSources()
    }

    func removeSource(_ source: FeedSource) {
        sources.removeAll { $0.id == source.id }
        persistSources()
    }

    func updateSource(_ source: FeedSource, isEnabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].isEnabled = isEnabled
        persistSources()
    }

    @discardableResult
    func updateSource(_ source: FeedSource, name: String, urlText: String) -> Bool {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return false }
        guard let url = validatedFeedURL(from: urlText) else {
            errorMessage = "RSSのURLを確認してください。"
            return false
        }

        if sources.contains(where: { $0.id != source.id && $0.feedURL == url }) {
            errorMessage = "このRSSはすでに追加されています。"
            return false
        }

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[index].name = displayName.isEmpty ? url.host ?? "RSS" : displayName
        sources[index].feedURL = url
        persistSources()
        return true
    }

    func resetToDefaultSources() {
        sources = FeedSource.defaults
        persistSources()
    }

    func setAllSourcesEnabled(_ isEnabled: Bool) {
        sources = sources.map { source in
            var copy = source
            copy.isEnabled = isEnabled
            return copy
        }
        persistSources()
    }

    func toggleSaved(_ article: Article) {
        if let index = savedArticles.firstIndex(where: { $0.id == article.id }) {
            savedArticles.remove(at: index)
        } else {
            savedArticles.insert(article, at: 0)
        }
        persistSaved()
    }

    func isSaved(_ article: Article) -> Bool {
        savedArticles.contains(where: { $0.id == article.id })
    }

    func fatigueScore(for article: Article) -> Int {
        let text = article.analysisText
        let fatigueHits = fatigueWords.filter { !$0.isEmpty && text.contains($0.lowercased()) }.count
        let hotWords = ["炎上", "批判", "速報", "悲報", "事件", "事故", "拡散", "終了", "逮捕"]
        let hotHits = hotWords.filter { text.contains($0.lowercased()) }.count
        return min(100, fatigueHits * 30 + hotHits * 12)
    }

    func heatScore(for article: Article) -> Int {
        let newestBonus: Int
        if let publishedAt = article.publishedAt {
            let hours = Date().timeIntervalSince(publishedAt) / 3600
            newestBonus = max(0, 30 - Int(hours * 2))
        } else {
            newestBonus = 0
        }
        let text = article.analysisText
        let hotWords = ["速報", "炎上", "話題", "悲報", "発表", "衝撃", "急増", "逮捕", "終了"]
        let hotHits = hotWords.filter { text.contains($0.lowercased()) }.count
        return min(100, newestBonus + hotHits * 14 + article.title.count / 3)
    }

    var threeMinuteArticles: [Article] {
        articles
            .sorted { heatScore(for: $0) > heatScore(for: $1) }
            .prefix(10)
            .map { $0 }
    }

    var topicClusters: [ArticleTopicCluster] {
        let grouped = Dictionary(grouping: articles) { article in
            clusterKey(for: article)
        }

        return grouped
            .filter { !$0.key.isEmpty && $0.value.count >= 2 }
            .map { key, items in
                ArticleTopicCluster(id: key, title: key, articles: items.sorted { heatScore(for: $0) > heatScore(for: $1) })
            }
            .sorted {
                if $0.heat == $1.heat { return $0.articles.count > $1.articles.count }
                return $0.heat > $1.heat
            }
    }

    var biasMetrics: [BiasMetric] {
        let total = max(articles.count, 1)
        return Dictionary(grouping: articles, by: \.category)
            .map { BiasMetric(category: $0.key, count: $0.value.count, ratio: Double($0.value.count) / Double(total)) }
            .sorted { $0.count > $1.count }
    }

    func note(for article: Article) -> String {
        articleNotes[article.id] ?? ""
    }

    func updateNote(_ note: String, for article: Article) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            articleNotes.removeValue(forKey: article.id)
        } else {
            articleNotes[article.id] = trimmed
        }
        persistNotes()
    }

    func addFatigueWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !fatigueWords.contains(trimmed) else { return }
        fatigueWords.append(trimmed)
        persistFatigueWords()
    }

    func removeFatigueWords(at offsets: IndexSet) {
        fatigueWords.remove(atOffsets: offsets)
        persistFatigueWords()
    }

    var sourceBreakdown: [(name: String, count: Int)] {
        Dictionary(grouping: articles, by: \.sourceName)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var categoryBreakdown: [(category: ArticleCategory, count: Int)] {
        Dictionary(grouping: articles, by: \.category)
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var hotKeywords: [String] {
        let ignored = Set(["これ", "それ", "さん", "する", "した", "速報", "画像", "動画", "ニュース", "まとめ"])
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let words = articles
            .flatMap { $0.title.components(separatedBy: separators) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && !ignored.contains($0) }

        return Dictionary(grouping: words, by: { $0 })
            .map { (word: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.word < $1.word }
                return $0.count > $1.count
            }
            .prefix(12)
            .map(\.word)
    }

    private func persistSources() {
        Self.save(sources, key: sourcesKey)
    }

    private func persistSaved() {
        Self.save(savedArticles, key: savedKey)
    }

    private func persistFatigueWords() {
        Self.save(fatigueWords, key: fatigueWordsKey)
    }

    private func persistNotes() {
        Self.save(articleNotes, key: articleNotesKey)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func validatedFeedURL(from text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedText),
              url.scheme == "https" || url.scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func merged(_ savedSources: [FeedSource], with defaultSources: [FeedSource]) -> [FeedSource] {
        var mergedSources = savedSources.filter { source in
            !source.name.contains("?") && !source.name.contains("邵") && !source.name.contains("郢")
        }
        var urls = Set(mergedSources.map(\.feedURL))

        for source in defaultSources where !urls.contains(source.feedURL) {
            mergedSources.append(source)
            urls.insert(source.feedURL)
        }
        return mergedSources.isEmpty ? defaultSources : mergedSources
    }

    private func clusterKey(for article: Article) -> String {
        let ignored = Set(["これ", "それ", "ため", "さん", "ちゃん", "ニュース", "まとめ", "画像", "動画"])
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let words = article.title
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && !ignored.contains($0) }

        return words.max { $0.count < $1.count } ?? article.category.rawValue
    }
}

private extension Array where Element == Article {
    func uniquedByLink() -> [Article] {
        var seen = Set<URL>()
        return filter { article in
            seen.insert(article.link).inserted
        }
    }
}
