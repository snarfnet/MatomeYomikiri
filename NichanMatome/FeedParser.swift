import Foundation

final class FeedParser: NSObject, XMLParserDelegate {
    private let sourceName: String
    private var articles: [Article] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentSummary = ""
    private var currentDate = ""
    private var isInsideItem = false

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func parse(_ data: Data) throws -> [Article] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()

        if currentElement == "item" || currentElement == "entry" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentSummary = ""
            currentDate = ""
        }

        if isInsideItem, currentElement == "link", let href = attributeDict["href"] {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description", "summary", "content:encoded":
            currentSummary += string
        case "pubdate", "published", "updated", "dc:date":
            currentDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lowercasedName = elementName.lowercased()
        if lowercasedName == "item" || lowercasedName == "entry" {
            appendArticle()
            isInsideItem = false
        }
        currentElement = ""
    }

    private func appendArticle() {
        let title = currentTitle.cleanedText
        let linkText = currentLink.cleanedText
        guard !title.isEmpty, let url = URL(string: linkText) else { return }

        let article = Article(
            id: "\(sourceName)-\(linkText)",
            title: title,
            link: url,
            sourceName: sourceName,
            publishedAt: DateParser.parse(currentDate.cleanedText),
            summary: currentSummary.cleanedText.strippingHTML
        )
        articles.append(article)
    }
}

private enum DateParser {
    static func parse(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        let formatters: [DateFormatter] = [
            make("EEE, dd MMM yyyy HH:mm:ss Z", locale: Locale(identifier: "en_US_POSIX")),
            make("yyyy-MM-dd'T'HH:mm:ssXXXXX", locale: Locale(identifier: "en_US_POSIX")),
            make("yyyy-MM-dd'T'HH:mm:ssZ", locale: Locale(identifier: "en_US_POSIX")),
            make("yyyy-MM-dd HH:mm:ss", locale: Locale(identifier: "ja_JP"))
        ]

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func make(_ format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter
    }
}

private extension String {
    var cleanedText: String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingHTML: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }
        return attributed.string.cleanedText
    }
}
