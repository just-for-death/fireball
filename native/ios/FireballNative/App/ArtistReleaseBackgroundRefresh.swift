import BackgroundTasks
import Foundation

/// Optional periodic followed-artist release probe when the app is not in the foreground.
enum ArtistReleaseBackgroundRefresh {
    static let taskIdentifier = "com.fireball.native.artist-releases"

    static func register(store: LibraryStore) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(refreshTask: refresh, store: store)
        }
    }

    static func scheduleIfNeeded(settings: FireballSettings) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard settings.notifyArtistReleasesOnDevice else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run(refreshTask: BGAppRefreshTask, store: LibraryStore) {
        let work = Task<Bool, Never> {
            let snapshot = store.load()
            scheduleIfNeeded(settings: snapshot.settings)
            guard snapshot.settings.notifyArtistReleasesOnDevice else { return true }

            let repository = FireballRepository(api: FireballAPIClient(), store: store)
            let gotify = GotifyClient()

            let wantGotify =
                snapshot.settings.gotifyEnabled &&
                !snapshot.settings.gotifyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !snapshot.settings.gotifyToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let onGotify: (@Sendable (String, String) async -> Bool)? =
                wantGotify
                    ? { @Sendable (title: String, message: String) async -> Bool in
                        await gotify.send(
                            url: snapshot.settings.gotifyUrl,
                            token: snapshot.settings.gotifyToken,
                            title: title,
                            message: message
                        )
                    }
                    : nil

            let onDevice: (@Sendable (String, String) async -> Void)? =
                snapshot.settings.notifyArtistReleasesOnDevice
                    ? { @Sendable (title: String, message: String) async in
                        await ArtistReleaseNotifier.notify(title: title, message: message)
                    }
                    : nil

            guard let updated = await repository.checkFollowedArtistNewReleases(
                snapshot: snapshot,
                onGotifyNotify: onGotify,
                onDeviceNotify: onDevice
            )
            else { return true }

            try? store.save(updated)
            return true
        }

        refreshTask.expirationHandler = { work.cancel() }
        Task {
            let ok = (try? await work.value) ?? false
            refreshTask.setTaskCompleted(success: ok)
        }
    }
}
