import SwiftUI
import WidgetKit

/// Extensão só com a Live Activity do megafone — o app não tem widget de tela inicial.
@main
struct MBAdminLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MegaphoneLiveActivityWidget()
    }
}
