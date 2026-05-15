import GoogleMobileAds
import SwiftUI
import UIKit

enum AdPlacement {
    case top
    case bottom
    case detail
    case inline
}

struct AdConfiguration {
    static let sampleBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    static func bannerUnitID(for placement: AdPlacement) -> String {
        let key = switch placement {
        case .top:
            "GADBannerTopAdUnitID"
        case .bottom:
            "GADBannerBottomAdUnitID"
        case .detail:
            "GADBannerDetailAdUnitID"
        case .inline:
            "GADBannerInlineAdUnitID"
        }

        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return sampleBannerUnitID
        }

        return value
    }
}

@MainActor
final class AdService {
    static let shared = AdService()

    let isAdFree = false

    private init() {}

    func start() {
        MobileAds.shared.start()
    }
}

struct AdMobBannerSlotView: View {
    let placement: AdPlacement

    var body: some View {
        if AdService.shared.isAdFree {
            EmptyView()
        } else {
            BannerViewContainer(
                adSize: AdSizeBanner,
                adUnitID: AdConfiguration.bannerUnitID(for: placement)
            )
            .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("広告")
        }
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.adRootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.adUnitID != adUnitID {
            banner.adUnitID = adUnitID
            banner.load(Request())
        }
    }
}

private extension UIApplication {
    var adRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        presentedViewController?.topPresentedViewController ?? self
    }
}
