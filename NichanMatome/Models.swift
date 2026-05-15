import Foundation

struct FeedSource: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var feedURL: URL
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, feedURL: URL, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.isEnabled = isEnabled
    }
}

struct Article: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let link: URL
    let sourceName: String
    let publishedAt: Date?
    let summary: String

    var relativeDateText: String {
        guard let publishedAt else { return "日時不明" }
        return publishedAt.formatted(.relative(presentation: .named))
    }

    var hostText: String {
        URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .host?
            .replacingOccurrences(of: "www.", with: "") ?? "link"
    }

    var category: ArticleCategory {
        ArticleCategory.detect(from: "\(title) \(summary)")
    }

    var estimatedReadMinutes: Int {
        max(1, (title.count + summary.count) / 420)
    }

    var analysisText: String {
        "\(title) \(summary)".lowercased()
    }
}

struct ArticleTopicCluster: Identifiable {
    let id: String
    let title: String
    let articles: [Article]

    var sourceCount: Int {
        Set(articles.map(\.sourceName)).count
    }

    var heat: Int {
        min(99, articles.count * 12 + sourceCount * 8)
    }
}

struct BiasMetric: Identifiable {
    let id = UUID()
    let category: ArticleCategory
    let count: Int
    let ratio: Double
}

enum ArticleCategory: String, CaseIterable, Identifiable {
    case all = "すべて"
    case news = "ニュース"
    case internet = "ネット"
    case entertainment = "芸能"
    case gameAnime = "ゲーム・アニメ"
    case money = "お金"
    case life = "暮らし"
    case other = "その他"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .news:
            return "newspaper"
        case .internet:
            return "network"
        case .entertainment:
            return "sparkles"
        case .gameAnime:
            return "gamecontroller"
        case .money:
            return "yensign.circle"
        case .life:
            return "house"
        case .other:
            return "text.bubble"
        }
    }

    static func detect(from text: String) -> ArticleCategory {
        let value = text.lowercased()
        let rules: [(ArticleCategory, [String])] = [
            (.gameAnime, ["ゲーム", "アニメ", "漫画", "マンガ", "任天堂", "ps5", "switch", "steam"]),
            (.entertainment, ["芸能", "アイドル", "俳優", "女優", "テレビ", "映画", "youtube", "vtuber"]),
            (.money, ["円", "株", "投資", "給料", "年収", "税", "物価", "経済"]),
            (.life, ["生活", "家族", "結婚", "育児", "学校", "仕事", "会社", "料理"]),
            (.internet, ["sns", "x民", "twitter", "ネット", "炎上", "ai", "スマホ"]),
            (.news, ["速報", "逮捕", "政府", "警察", "事件", "事故", "政治", "海外"])
        ]

        for (category, keywords) in rules where keywords.contains(where: { value.contains($0) }) {
            return category
        }
        return .other
    }
}

enum ArticleTimeScope: String, CaseIterable, Identifiable {
    case all = "全期間"
    case today = "今日"
    case twoDays = "48時間"
    case week = "7日"

    var id: String { rawValue }

    func includes(_ date: Date?, now: Date = .now) -> Bool {
        guard self != .all else { return true }
        guard let date else { return false }

        switch self {
        case .all:
            return true
        case .today:
            return Calendar.current.isDateInToday(date)
        case .twoDays:
            return date >= now.addingTimeInterval(-60 * 60 * 48)
        case .week:
            return date >= now.addingTimeInterval(-60 * 60 * 24 * 7)
        }
    }
}

enum ArticleSortMode: String, CaseIterable, Identifiable {
    case newest = "新着順"
    case source = "サイト順"
    case titleLength = "情報量順"

    var id: String { rawValue }
}
