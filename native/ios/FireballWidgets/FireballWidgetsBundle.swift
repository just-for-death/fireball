import WidgetKit
import SwiftUI

@main
struct FireballWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            NowPlayingLiveActivityWidget()
        }
    }
}
