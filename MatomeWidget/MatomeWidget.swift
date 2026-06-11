import WidgetKit
import SwiftUI

struct MatomeEntry: TimelineEntry {
    let date: Date
    let articles: [SharedArticle]
}

struct MatomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatomeEntry {
        MatomeEntry(date: .now, articles: sampleArticles)
    }

    func getSnapshot(in context: Context, completion: @escaping (MatomeEntry) -> Void) {
        let articles = SharedDataManager.loadArticles()
        completion(MatomeEntry(date: .now, articles: articles.isEmpty ? sampleArticles : articles))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatomeEntry>) -> Void) {
        let articles = SharedDataManager.loadArticles()
        let count = SharedDataManager.widgetArticleCount
        let display = Array(articles.prefix(count))
        let entry = MatomeEntry(date: .now, articles: display.isEmpty ? sampleArticles : display)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var sampleArticles: [SharedArticle] {
        [
            SharedArticle(title: "まとめ・よみきりで最新記事をチェック", sourceName: "サンプル", link: "", heat: 80, timeAgo: "1時間前"),
            SharedArticle(title: "ウィジェットに最新まとめが表示されます", sourceName: "使い方", link: "", heat: 60, timeAgo: "2時間前"),
            SharedArticle(title: "アプリを開いて記事を読み込むと更新されます", sourceName: "ヒント", link: "", heat: 40, timeAgo: "3時間前"),
        ]
    }
}

struct MatomeWidgetEntryView: View {
    var entry: MatomeEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                    .font(.system(size: 10, weight: .bold))
                Text("まとめ・よみきり")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            // Articles
            let maxCount = family == .systemSmall ? 3 : (family == .systemMedium ? 4 : 8)
            ForEach(Array(entry.articles.prefix(maxCount).enumerated()), id: \.offset) { index, article in
                if index > 0 {
                    Divider()
                }
                HStack(spacing: 4) {
                    Text(article.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(family == .systemSmall ? 1 : 2)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 2)

                    Text(article.sourceName)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct MatomeWidget: Widget {
    let kind = "MatomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatomeProvider()) { entry in
            MatomeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("まとめ・よみきり")
        .description("最新のまとめ記事タイトルを表示します")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
