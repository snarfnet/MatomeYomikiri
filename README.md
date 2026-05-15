# まとめ・よみきり

複数のまとめ系RSSを読みやすく整理するiOSアプリです。

- Bundle ID: `com.tokyonasu.matomeyomikiri`
- App Store Connect App ID: `6769196238`
- AdMob App ID: `ca-app-pub-9404799280370656~4316108976`

## 主な機能

- RSS記事の新着一覧
- カテゴリ、期間、検索、並び替え
- 話題クラスター、よく出る言葉、サイト別バランス
- NGワード
- あとで読む保存
- 読後メモ
- 元サイト表示
- AdMobバナー広告

## 開発

このフォルダはXcodeGen向けの `project.yml` を含みます。

```sh
xcodegen generate
open NichanMatome.xcodeproj
```

初期RSSは `NichanMatome/DefaultFeeds.swift` で管理します。記事データ、保存、メモ、NGワードは端末内に保存します。
