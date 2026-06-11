import Foundation

struct SharedArticle: Codable {
    let title: String
    let sourceName: String
    let link: String
    let heat: Int
    let timeAgo: String
}

enum SharedDataManager {
    static let appGroupID = "group.com.tokyonasu.matomeyomikiri"
    private static let articlesKey = "shared.articles"
    private static let widgetCountKey = "widget.articleCount"

    static var suitDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var widgetArticleCount: Int {
        get { suitDefaults?.integer(forKey: widgetCountKey).clamped(to: 3...10) ?? 5 }
        set { suitDefaults?.set(newValue, forKey: widgetCountKey) }
    }

    static func saveArticles(_ articles: [SharedArticle]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        suitDefaults?.set(data, forKey: articlesKey)
    }

    static func loadArticles() -> [SharedArticle] {
        guard let data = suitDefaults?.data(forKey: articlesKey),
              let articles = try? JSONDecoder().decode([SharedArticle].self, from: data) else {
            return []
        }
        return articles
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
