import SwiftUI
import WidgetKit

@main
struct NichanMatomeApp: App {
    @StateObject private var store = FeedStore()
    @AppStorage("didStartMobileAds") private var didStartMobileAds = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    startAdsIfNeeded()
                }
                .onChange(of: store.articles) { _, articles in
                    syncSharedData(articles)
                }
        }
    }

    @MainActor
    private func startAdsIfNeeded() {
        guard !didStartMobileAds else { return }
        didStartMobileAds = true
        AdService.shared.start()
    }

    private func syncSharedData(_ articles: [Article]) {
        let shared = articles.prefix(20).map { article in
            SharedArticle(
                title: article.title,
                sourceName: article.sourceName,
                link: article.link.absoluteString,
                heat: store.heatScore(for: article),
                timeAgo: article.shortTimeText
            )
        }
        SharedDataManager.saveArticles(shared)
        NotificationManager.shared.scheduleWithArticles(shared)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
