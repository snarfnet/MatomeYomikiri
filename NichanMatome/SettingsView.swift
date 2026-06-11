import SwiftUI

struct SettingsView: View {
    @ObservedObject private var notifManager = NotificationManager.shared
    @State private var notifTime = Date()

    var body: some View {
        Form {
            // Notification settings
            Section {
                Toggle("毎日のバズ通知", isOn: Binding(
                    get: { notifManager.isEnabled },
                    set: { newValue in
                        if newValue {
                            notifManager.requestPermissionAndEnable()
                        } else {
                            notifManager.disable()
                        }
                    }
                ))

                if notifManager.isEnabled {
                    DatePicker("通知時刻", selection: $notifTime, displayedComponents: .hourAndMinute)
                        .onChange(of: notifTime) { _, newValue in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            notifManager.hour = components.hour ?? 20
                            notifManager.minute = components.minute ?? 0
                        }

                    Text("毎日この時刻にバズ記事TOP3を通知します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("通知", systemImage: "bell")
            }

            // App info
            Section {
                LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                LabeledContent("ビルド", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
            } header: {
                Label("アプリ情報", systemImage: "info.circle")
            }
        }
        .onAppear {
            var components = DateComponents()
            components.hour = notifManager.hour
            components.minute = notifManager.minute
            notifTime = Calendar.current.date(from: components) ?? Date()
        }
    }
}
