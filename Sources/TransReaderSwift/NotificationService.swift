import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Service

final class NotificationService: NSObject, @unchecked Sendable {
    enum Category: String, Sendable {
        case translationDone
        case error
        case longOperation
        case background
    }

    private let configStore: ConfigStore
    private var permissionGranted = false

    init(configStore: ConfigStore) {
        self.configStore = configStore
        super.init()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.permissionGranted = settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.permissionGranted = granted
            if let error {
                appLog("[Notify] Permission error: \(error.localizedDescription)")
            } else {
                appLog("[Notify] Permission \(granted ? "granted" : "denied")")
            }
        }
    }

    // MARK: - Send Notification

    func send(title: String, body: String, category: Category) {
        guard configStore.config.notificationsEnabled else { return }
        guard permissionGranted else {
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                self?.permissionGranted = settings.authorizationStatus == .authorized
            }
            return
        }

        // Check per-category toggle
        switch category {
        case .translationDone:
            guard configStore.config.notifyOnTranslationDone else { return }
            // Skip if app is in foreground — user can already see the result
            guard !NSApp.isActive else { return }
        case .error:
            guard configStore.config.notifyOnError else { return }
        case .longOperation:
            guard configStore.config.notifyOnLongOperation else { return }
        case .background:
            break // always send if master toggle is on
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let id = "transreader-\(category.rawValue)-\(UUID().uuidString.prefix(8))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appLog("[Notify] Failed to send: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Notification Click Handling

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Activate app window when user clicks notification
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        completionHandler()
    }

    // Show notifications even when app is in foreground (for error category)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
