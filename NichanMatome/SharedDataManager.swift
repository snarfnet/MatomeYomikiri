import Foundation

struct SharedArticle: Codable {
    let title: String
    let sourceName: String
    let link: String
    let heat: Int
    let timeAgo: String
}

enum SharedDataManager {
    private static let articlesKey = "shared.articles"
    private static let widgetCountKey = "widget.articleCount"

    static var widgetArticleCount: Int {
        get { UserDefaults.standard.integer(forKey: widgetCountKey).clamped(to: 3...10) }
        set { UserDefaults.standard.set(newValue, forKey: widgetCountKey) }
    }

    static func saveArticles(_ articles: [SharedArticle]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        UserDefaults.standard.set(data, forKey: articlesKey)
    }

    static func loadArticles() -> [SharedArticle] {
        guard let data = UserDefaults.standard.data(forKey: articlesKey),
              let articles = try? JSONDecoder().decode([SharedArticle].self, from: data) else {
            return []
        }
        return articles
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
