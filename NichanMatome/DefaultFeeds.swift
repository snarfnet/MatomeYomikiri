import Foundation

extension FeedSource {
    static let defaults: [FeedSource] = [
        FeedSource(name: "痛いニュース", feedURL: URL(string: "https://itainews.com/index.rdf")!),
        FeedSource(name: "ハムスター速報", feedURL: URL(string: "https://hamusoku.com/index.rdf")!),
        FeedSource(name: "アルファルファモザイク", feedURL: URL(string: "https://alfalfalfa.com/index.rdf")!),
        FeedSource(name: "VIPPERな俺", feedURL: URL(string: "http://blog.livedoor.jp/news23vip/index.rdf")!),
        FeedSource(name: "ゴールデンタイムズ", feedURL: URL(string: "http://blog.livedoor.jp/goldennews/index.rdf")!),
        FeedSource(name: "キニ速", feedURL: URL(string: "http://blog.livedoor.jp/kinisoku/index.rdf")!),
        FeedSource(name: "哲学ニュースnwk", feedURL: URL(string: "http://blog.livedoor.jp/nwknews/index.rdf")!),
        FeedSource(name: "VIPPER速報", feedURL: URL(string: "http://vippers.jp/index.rdf")!),
        FeedSource(name: "IT速報", feedURL: URL(string: "http://blog.livedoor.jp/itsoku/index.rdf")!),
        FeedSource(name: "ニュース30over", feedURL: URL(string: "http://www.news30over.com/index.rdf")!),
        FeedSource(name: "ライフハックちゃんねる弐式", feedURL: URL(string: "http://lifehack2ch.livedoor.biz/index.rdf")!),
        FeedSource(name: "はちま起稿", feedURL: URL(string: "http://blog.esuteru.com/index.rdf")!),
        FeedSource(name: "オレ的ゲーム速報", feedURL: URL(string: "http://jin115.com/index.rdf")!),
        FeedSource(name: "暇人速報", feedURL: URL(string: "http://himasoku.com/index.rdf")!),
        FeedSource(name: "カナ速", feedURL: URL(string: "http://kanasoku.info/index.rdf")!),
        FeedSource(name: "ニュー速クオリティ", feedURL: URL(string: "http://news4vip.livedoor.biz/index.rdf")!),
        FeedSource(name: "まとめたニュース", feedURL: URL(string: "http://matometanews.com/index.rdf")!),
        FeedSource(name: "NEWSOKU BLOG", feedURL: URL(string: "https://newsoku.blog/feed")!),
        FeedSource(name: "お料理速報", feedURL: URL(string: "http://oryouri.2chblog.jp/index.rdf")!),
        FeedSource(name: "エアライン本舗", feedURL: URL(string: "http://airlinehonpo.blog.fc2.com/?xml")!, isEnabled: false)
    ]
}
