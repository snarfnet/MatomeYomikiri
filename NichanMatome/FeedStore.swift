import Foundation
import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var articles: [Article] = Article.reviewFallbackArticles
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
    private nonisolated static let refreshBatchSize = 4
    private let refreshSourceLimit = 150
    @Published private(set) var previousArticleIDs: Set<String> = []
    private nonisolated static let sourceTimeoutNanoseconds: UInt64 = 5_000_000_000
    private let refreshTimeoutNanoseconds: UInt64 = 14_000_000_000

    init() {
        if let savedSources = Self.load([FeedSource].self, key: sourcesKey) {
            sources = Self.merged(savedSources, with: FeedSource.defaults)
        } else {
            sources = FeedSource.defaults
        }
        savedArticles = Self.load([Article].self, key: savedKey) ?? []
        fatigueWords = Self.load([String].self, key: fatigueWordsKey) ?? ["炎上", "逮捕", "悲報", "批判", "事件"]
        articleNotes = Self.load([String: String].self, key: articleNotesKey) ?? [:]
        lastUpdatedAt = Date()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let enabledSources = Array(sources.filter(\.isEnabled).prefix(refreshSourceLimit))
        guard !enabledSources.isEmpty else {
            articles = Article.reviewFallbackArticles
            errorMessage = "有効な配信元がありません。配信元タブでRSSをオンにしてください。"
            return
        }

        do {
            let fetchedArticles = try await withTimeout(seconds: refreshTimeoutNanoseconds) {
                await self.fetchArticles(from: enabledSources)
            }

            let normalized = fetchedArticles
                .uniquedByLink()
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                .prefix(500)
                .map { $0 }

            previousArticleIDs = Set(articles.map(\.id))

            if normalized.isEmpty {
                articles = Article.reviewFallbackArticles
                errorMessage = "RSSをすぐに取得できなかったため、サンプル記事を表示しています。更新ボタンで再取得できます。"
            } else {
                articles = normalized
                errorMessage = nil
            }
            lastUpdatedAt = Date()
        } catch {
            articles = articles.isEmpty ? Article.reviewFallbackArticles : articles
            lastUpdatedAt = Date()
            errorMessage = "RSS取得がタイムアウトしました。サンプル記事を表示しています。更新ボタンで再取得できます。"
        }
    }

    private nonisolated func fetchArticles(from enabledSources: [FeedSource]) async -> [Article] {
        var fetchedArticles: [Article] = []

        for startIndex in stride(from: 0, to: enabledSources.count, by: Self.refreshBatchSize) {
            let endIndex = min(startIndex + Self.refreshBatchSize, enabledSources.count)
            let batch = Array(enabledSources[startIndex..<endIndex])

            await withTaskGroup(of: [Article].self) { group in
                for source in batch {
                    group.addTask {
                        do {
                            return try await self.fetchSource(source)
                        } catch {
                            return []
                        }
                    }
                }

                for await items in group {
                    fetchedArticles.append(contentsOf: items)
                }
            }
        }

        return fetchedArticles
    }

    private nonisolated func fetchSource(_ source: FeedSource) async throws -> [Article] {
        try await withTimeout(seconds: Self.sourceTimeoutNanoseconds) {
            var request = URLRequest(url: source.feedURL, timeoutInterval: 4)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("MatomeYomikiri/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<400).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            return try FeedParser(sourceName: source.name).parse(data)
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

    func isNew(_ article: Article) -> Bool {
        !previousArticleIDs.isEmpty && !previousArticleIDs.contains(article.id)
    }

    func fatigueScore(for article: Article) -> Int {
        let text = article.analysisText
        let fatigueHits = fatigueWords.filter { !$0.isEmpty && text.contains($0.lowercased()) }.count
        let hotWords = ["炎上", "批判", "速報", "悲報", "事件", "逮捕", "拡散", "終了"]
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
        let hotWords = ["速報", "炎上", "話題", "悲報", "発表", "衝撃", "逮捕", "終了"]
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
            !source.name.contains("?") && !source.name.contains("驍ｵ") && !source.name.contains("驛｢")
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

private func withTimeout<T: Sendable>(
    seconds nanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw URLError(.timedOut)
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
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

private extension Article {
    static var reviewFallbackArticles: [Article] {
        let base = URL(string: "https://snarfnet.github.io/")!
        let items: [(String, String, String, TimeInterval)] = [
            ("【速報】大谷翔平が今季50号ホームラン達成、MLB記録を更新", "なんJ HERO", "news", -120),
            ("彼女に「好きな寿司ネタは？」って聞いたら予想外の回答きた", "キニ速", "life", -300),
            ("任天堂の新型ゲーム機、予約開始からわずか3分で完売", "はちま起稿", "gameAnime", -600),
            ("新宿駅の工事がついに完成、「迷宮」がどう変わったか見てきた", "痛いニュース", "news", -900),
            ("プログラマーワイ、ChatGPTに仕事を奪われそうで震える", "IT速報", "internet", -1200),
            ("ホロライブの新人VTuber、デビュー配信で同接10万人超え", "Vtuberまとめ", "entertainment", -1500),
            ("【朗報】ビットコインが史上最高値を更新、投資民歓喜", "稼げるまとめ", "money", -1800),
            ("東京の家賃が高すぎるので地方移住を検討した結果", "暮らしまとめ", "life", -2100),
            ("ガンダムの新作映画、興行収入100億円突破確実の大ヒット", "アニゲー速報", "gameAnime", -2400),
            ("Appleの新型iPhoneのリーク画像が流出、デザインが大幅変更か", "ガジェット速報", "internet", -2700),
            ("【悲報】ワイの上司、会議中にとんでもない発言をしてしまう", "ハムスター速報", "life", -3000),
            ("日経平均株価が4万円台回復、海外投資家の買いが加速", "市況まとめ", "money", -3300),
            ("人気声優が結婚を発表、ファンから祝福の声が殺到", "芸能まとめ速報", "entertainment", -3600),
            ("深夜にコンビニで見かけた光景が面白すぎた件", "2chまとめ", "life", -3900),
            ("スプラトゥーン4の新情報が公開、新武器と新ステージが判明", "ゲーム速報", "gameAnime", -4200),
            ("AIで生成した画像が美術コンクールで最優秀賞を受賞して物議", "ニュー速クオリティ", "news", -4500),
            ("NISAの積立投資で1000万円達成した人の運用方法がこちら", "マネーニュース", "money", -4800),
            ("海外の反応「日本の電車の時刻表の正確さは異常」", "海外反応まとめ", "news", -5100),
            ("ラーメン二郎に初めて行ったんだが注文の仕方が分からなかった話", "食べ物まとめ", "life", -5400),
            ("Netflixの新作アニメが海外で大バズり、世界1位を獲得", "アニメまとめ", "gameAnime", -5700),
        ]
        return items.enumerated().map { index, item in
            Article(
                id: "fallback-\(index + 1)",
                title: item.0,
                link: base.appendingPathComponent("article/\(index + 1)"),
                sourceName: item.1,
                publishedAt: Date().addingTimeInterval(item.3),
                summary: ""
            )
        }
    }
}
