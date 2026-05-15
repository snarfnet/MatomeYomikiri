import AppTrackingTransparency
import SwiftUI

@main
struct NichanMatomeApp: App {
    @StateObject private var store = FeedStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didRequestTrackingPermission") private var didRequestTrackingPermission = false
    @AppStorage("didStartMobileAds") private var didStartMobileAds = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    requestTrackingPermissionIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        requestTrackingPermissionIfNeeded()
                    }
                }
        }
    }

    private func requestTrackingPermissionIfNeeded() {
        guard !didStartMobileAds else { return }

        if didRequestTrackingPermission || ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            startAds()
            return
        }

        didRequestTrackingPermission = true
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in
                startAds()
            }
        }
    }

    @MainActor
    private func startAds() {
        guard !didStartMobileAds else { return }
        didStartMobileAds = true
        AdService.shared.start()
    }
}
