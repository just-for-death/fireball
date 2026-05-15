import Foundation
#if canImport(os)
import os.log
#endif

enum FireballAnalytics {
    static func log(_ event: String, settings: FireballSettings, properties: [String: String] = [:]) {
        guard settings.analytics || settings.loggingEnabled else { return }
        let props = properties.isEmpty ? "" : " \(properties)"
        #if canImport(os)
        Logger(subsystem: "com.fireball.nativeapp", category: "analytics")
            .info("\(event, privacy: .public)\(props, privacy: .public)")
        #else
        print("[FireballAnalytics] \(event)\(props)")
        #endif
    }
}
