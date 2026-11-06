import Foundation
import UIKit
import UserNotifications
import CallKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let callNotificationIds = ["incoming", "outgoing", "ongoing", "missed"]

    private struct CallNotification {
        let title: String
        let body: String
    }

    // Naik setiap kali notifikasi dibersihkan. Dipakai untuk mendeteksi notifikasi
    // yang selesai di-add (async) setelah call sudah berakhir.
    private var clearGeneration = 0
    private let lock = NSLock()

    // Saat app di foreground, notifikasi call tidak dipost (UI call sudah terlihat).
    // Status call terakhir disimpan di sini lalu dipost saat app masuk background.
    private var isInForeground = true
    private var activeNotifications: [String: CallNotification] = [:]

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Request permission for notifications
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            } else if !granted {
                print("Notification permission denied")
            } else {
                //print("Notification permission granted")
            }
        }
        configureNotificationCategories()
        observeAppState()
    }

    private func observeAppState() {
        let readState = { UIApplication.shared.applicationState != .background }
        isInForeground = Thread.isMainThread ? readState() : DispatchQueue.main.sync(execute: readState)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appDidEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // App ke background: tampilkan notifikasi status call yang sedang aktif (tanpa suara)
    @objc private func appDidEnterBackground() {
        lock.lock()
        isInForeground = false
        let pending = activeNotifications
        lock.unlock()
        for (id, item) in pending {
            add(id: id, title: item.title, body: item.body, playSound: false)
        }
    }

    // App kembali ke foreground: sembunyikan notifikasi call yang sedang tampil
    @objc private func appWillEnterForeground() {
        lock.lock()
        isInForeground = true
        lock.unlock()
        // "missed" tetap dibiarkan agar user masih bisa melihatnya
        removeNotifications(ids: ["incoming", "outgoing", "ongoing"])
    }

    // Setup categories and actions if needed (e.g. Accept/Reject call)
    private func configureNotificationCategories() {
        let acceptAction = UNNotificationAction(identifier: "ACCEPT_CALL", title: "Accept", options: [.foreground])
        let rejectAction = UNNotificationAction(identifier: "REJECT_CALL", title: "Reject", options: [.destructive])
        let incomingCategory = UNNotificationCategory(identifier: "incoming", actions: [acceptAction, rejectAction], intentIdentifiers: [], options: [])
        let missedCategory = UNNotificationCategory(identifier: "missed", actions: [], intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current().setNotificationCategories([incomingCategory, missedCategory])
    }

    private func post(title: String, body: String, id: String) {
        lock.lock()
        // "missed" bukan status call yang berjalan, jadi tidak perlu ditampilkan ulang nanti
        if id != "missed" {
            activeNotifications[id] = CallNotification(title: title, body: body)
        }
        let foreground = isInForeground
        lock.unlock()

        if foreground {
            print("Notification skipped (app in foreground) id \(id)")
            return
        }
        add(id: id, title: title, body: body, playSound: true)
    }

    private func add(id: String, title: String, body: String, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if playSound {
            // Critical alert requires special entitlement, fallback to normal alert
            content.sound = id == "incoming" ? .defaultCritical : .default
        }

        content.categoryIdentifier = id

        // Immediate notification (no trigger)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        lock.lock()
        let generation = clearGeneration
        lock.unlock()

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                print("Failed to add notification: \(error)")
                return
            }
            guard let self = self else { return }
            self.lock.lock()
            let wasCleared = self.clearGeneration != generation
            let backInForeground = self.isInForeground
            self.lock.unlock()
            // Call sudah berakhir, atau app sudah kembali ke foreground,
            // sebelum notifikasi ini selesai ditambahkan
            if wasCleared || backInForeground {
                self.removeNotifications(ids: [id])
            }
        }
        print("Notification posted \(title) id \(id) body \(body)")
    }

    func showIncomingCallNotification(caller: String, uuid: UUID) {
        post(title: "Incoming call", body: "Call from \(caller)", id: "incoming")
    }

    func showOutgoingCallNotification(callee: String) {
        post(title: "Calling", body: "Calling \(callee)...", id: "outgoing")
    }

    func showOngoingCallNotification(callee: String) {
        post(title: "Ongoing call", body: "In call with \(callee)", id: "ongoing")
    }

    func showMissedOrEndedNotification(caller: String) {
        post(title: "Missed call", body: "Missed call from \(caller)", id: "missed")
    }

    func clearCallNotifications() {
        lock.lock()
        clearGeneration += 1
        activeNotifications.removeAll()
        lock.unlock()
        removeNotifications(ids: NotificationManager.callNotificationIds)
    }

    // Hapus notifikasi "Calling ..." saat call sudah tersambung
    func clearOutgoingNotification() {
        lock.lock()
        activeNotifications["outgoing"] = nil
        lock.unlock()
        removeNotifications(ids: ["outgoing"])
    }

    private func removeNotifications(ids: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // Optional: Handle user actions on notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "ACCEPT_CALL":
            print("User accepted call")
            //if let uuid = CallState.shared.currentCallUUID {
            //}
            // Trigger your accept call logic here
        case "REJECT_CALL":
            print("User rejected call")
            //if CallState.shared.currentCallUUID != nil {
            //}
            // Trigger your reject call logic here
        default:
            break
        }
        completionHandler()
    }
}
