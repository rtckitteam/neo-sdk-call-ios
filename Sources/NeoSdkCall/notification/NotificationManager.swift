
import Foundation
import UserNotifications
import UIKit
import CallKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private let stateQueue = DispatchQueue(label: "com.neosdkcall.notification.state")
    private var activeSessionId: UUID?
    private var isCallActive: Bool = false
    
    private let activeCallNotificationIds = ["incoming", "outgoing", "ongoing"]
    private let allCallNotificationIds = ["incoming", "outgoing", "ongoing", "missed"]
    
    private override init() {
        super.init()
        setupCenter()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppWillTerminate() {
        clearCallNotifications()
    }
    
    func setupCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestAuthorization()
        configureNotificationCategories()
    }
    
    // Request permission for notifications across iOS versions
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NeoSdkCall] Notification permission error: \(error.localizedDescription)")
            } else if !granted {
                print("[NeoSdkCall] Notification permission denied")
            } else {
                print("[NeoSdkCall] Notification permission granted")
            }
            completion?(granted)
        }
    }
    
    // Setup categories and actions (Accept/Reject call)
    private func configureNotificationCategories() {
        let acceptAction = UNNotificationAction(identifier: "ACCEPT_CALL", title: "Accept", options: [.foreground])
        let rejectAction = UNNotificationAction(identifier: "REJECT_CALL", title: "Reject", options: [.destructive])
        let incomingCategory = UNNotificationCategory(identifier: "incoming", actions: [acceptAction, rejectAction], intentIdentifiers: [], options: [])
        let missedCategory = UNNotificationCategory(identifier: "missed", actions: [], intentIdentifiers: [], options: [])
        
        UNUserNotificationCenter.current().setNotificationCategories([incomingCategory, missedCategory])
    }
    
    func beginCallSession() {
        stateQueue.sync {
            isCallActive = true
            activeSessionId = UUID()
        }
    }
    
    private func beginOrGetSessionId() -> UUID {
        return stateQueue.sync {
            if !isCallActive || activeSessionId == nil {
                isCallActive = true
                activeSessionId = UUID()
            }
            return activeSessionId!
        }
    }
    
    private func isSessionValid(_ sessionId: UUID) -> Bool {
        return stateQueue.sync {
            return isCallActive && activeSessionId == sessionId
        }
    }
    
    private func deliverNotification(
        title: String,
        body: String,
        id: String,
        userInfo: [String: Any],
        sessionId: UUID?
    ) {
        if let sessionId = sessionId, !isSessionValid(sessionId) {
            print("[NeoSdkCall] Skipped posting notification (\(id)): call session already ended")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = id
        content.userInfo = userInfo
        
        // Immediate notification (no trigger)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        
        center.add(request) { [weak self] error in
            if let error = error {
                print("[NeoSdkCall] Failed to add notification (\(id)): \(error.localizedDescription)")
                return
            }
            
            // Guard against race condition: if call ended while add(request) was in flight, remove immediately
            if let self = self, let sessionId = sessionId, !self.isSessionValid(sessionId) {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
                print("[NeoSdkCall] Removed notification (\(id)) immediately because call ended during delivery")
            } else {
                print("[NeoSdkCall] Notification posted: \(title) id: \(id) body: \(body)")
            }
        }
    }
    
    private func post(
        title: String,
        body: String,
        id: String,
        userInfo: [String: Any] = [:],
        requiresActiveSession: Bool = true
    ) {
        let sessionId: UUID? = requiresActiveSession ? beginOrGetSessionId() : nil
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            if let sessionId = sessionId, !self.isSessionValid(sessionId) {
                return
            }
            
            switch settings.authorizationStatus {
            case .notDetermined:
                self.requestAuthorization { granted in
                    if granted {
                        self.deliverNotification(title: title, body: body, id: id, userInfo: userInfo, sessionId: sessionId)
                    }
                }
            case .denied:
                print("[NeoSdkCall] Cannot post notification: permission denied by user")
            default:
                self.deliverNotification(title: title, body: body, id: id, userInfo: userInfo, sessionId: sessionId)
            }
        }
    }
    
    func showIncomingCallNotification(caller: String, uuid: UUID) {
        beginCallSession()
        post(
            title: "Incoming call",
            body: "Call from \(caller)",
            id: "incoming",
            userInfo: ["uuid": uuid.uuidString, "caller": caller],
            requiresActiveSession: true
        )
    }
    
    func showOutgoingCallNotification(callee: String) {
        beginCallSession()
        post(
            title: "Menghubungkan",
            body: "Menghubungkan ke \(callee)",
            id: "outgoing",
            userInfo: ["callee": callee],
            requiresActiveSession: true
        )
    }
    
    func showOngoingCallNotification(callee: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["incoming", "outgoing"])
        center.removeDeliveredNotifications(withIdentifiers: ["incoming", "outgoing"])
        
        post(
            title: "Terhubung",
            body: "Terhubung dengan \(callee)",
            id: "ongoing",
            userInfo: ["callee": callee],
            requiresActiveSession: true
        )
    }
    
    func showMissedOrEndedNotification(caller: String) {
        post(
            title: "Missed call",
            body: "Missed call from \(caller)",
            id: "missed",
            userInfo: ["caller": caller],
            requiresActiveSession: false
        )
    }
    
    func clearCallNotifications() {
        stateQueue.sync {
            isCallActive = false
            activeSessionId = nil
        }
        
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allCallNotificationIds)
        center.removeDeliveredNotifications(withIdentifiers: allCallNotificationIds)
        
        // Safety sweep for iOS SpringBoard animation / async delivery races across iOS versions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            let stillInactive = self.stateQueue.sync { !self.isCallActive }
            if stillInactive {
                let c = UNUserNotificationCenter.current()
                c.removePendingNotificationRequests(withIdentifiers: self.activeCallNotificationIds)
                c.removeDeliveredNotifications(withIdentifiers: self.activeCallNotificationIds)
            }
        }
    }
    
    // Handle foreground presentation across all iOS versions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        if activeCallNotificationIds.contains(identifier) {
            let active = stateQueue.sync { isCallActive }
            if !active {
                // Suppress presenting stale call notifications if the call already ended
                completionHandler([])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
                return
            }
        }
        
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // Handle user actions on notifications (Accept/Reject/Tap)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        let uuidString = userInfo["uuid"] as? String
        let callUUID = uuidString.flatMap {
            UUID(uuidString: $0)
        }

        switch response.actionIdentifier {

        case "ACCEPT_CALL":
            print("[NeoSdkCall] User accepted call from notification")

            DispatchQueue.main.async {
                CallManager.sharedInstance
                    .answerIncomingCallFromNotification(uuid: callUUID)
            }

        case "REJECT_CALL":
            print("[NeoSdkCall] User rejected call from notification")

            DispatchQueue.main.async {
                if let uuid = callUUID {
                    CallManager.sharedInstance.rejectCall(uuid: uuid)
                } else {
                    CallManager.sharedInstance.rejectCall()
                }
            }

        case UNNotificationDefaultActionIdentifier:
            print("[NeoSdkCall] User tapped notification")

//            CallManager.sharedInstance.bringCurrentCallScreenToFront()
            DispatchQueue.main.async {
                    CallManager.sharedInstance.bringCurrentCallScreenToFront()
                }

        default:
            print("[NeoSdkCall] User interacted: \(response.actionIdentifier)")
        }

        completionHandler()
    }
    
    func clearOutgoingNotification() {
        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(
            withIdentifiers: ["outgoing"]
        )

        center.removeDeliveredNotifications(
            withIdentifiers: ["outgoing"]
        )
    }
}
