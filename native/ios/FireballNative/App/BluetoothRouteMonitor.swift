import AVFoundation
import Foundation

/// Resumes playback when a Bluetooth audio route connects (mirrors Android A2DP autoplay).
@MainActor
final class BluetoothRouteMonitor {
    private var observer: NSObjectProtocol?

    func start(isEnabled: @escaping () -> Bool, shouldResume: @escaping () -> Bool, onResume: @escaping () -> Void) {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .newDeviceAvailable
            else { return }
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            let hasBluetooth = outputs.contains {
                $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE || $0.portType == .bluetoothHFP
            }
            guard hasBluetooth, isEnabled(), shouldResume() else { return }
            onResume()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
