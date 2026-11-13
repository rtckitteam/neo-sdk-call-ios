//
//  CallManager.swift
//  CicareSdkCall
//
//  Created by Mohammad Annas Al Hariri on 27/10/25.
//


import Foundation
import AVFoundation
import CallKit
import UIKit
import SwiftUI
import CommonCrypto

final class CallManager: NSObject, CallServiceDelegate, CXCallObserverDelegate, CXProviderDelegate {
    
    static let sharedInstance: CallManager = CallManager()
    
    private var isOutgoing: Bool = false
    private var screenIsShown: Bool = false
    private var metaData: [String: String] = [:]
    var callVC: UIViewController?
    var delegate: CallEventListener?
    
    private var callWindow: UIWindow?

    private var provider: CXProvider?
    private var callController: CXCallController?
    
    private let callObserver = CXCallObserver()
    
    private var calls: [UUID: CallInfo] = [:]
    private var currentCall: UUID?
    private var isInCall: Bool = false
    private var defaultVolume: Float = 1.0
    
    private var isSipCall: Bool = false
    
    private override init() {
        super.init()
        setupCallKit()
    }
    
    private func setupCallKit() {
        let configuration = CXProviderConfiguration.init(localizedName: "CallKit")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1;
        configuration.supportedHandleTypes = [CXHandle.HandleType.generic]
        callObserver.setDelegate(self, queue: nil)
        provider = CXProvider.init(configuration: configuration)
        provider?.setDelegate(self, queue: nil)
        
        callController = CXCallController.init()
    }
    
    private func requestTransaction(
        transaction: CXTransaction,
        completion: @escaping (Bool) -> Void
    ) {

        // DEBUG: Cek status aktual CallKit
        print("========== CALLKIT OBSERVER ==========")

        let activeCalls = callObserver.calls

        for call in activeCalls {
            print("""
            [CallKit Observer]
            UUID: \(call.uuid)
            Ended: \(call.hasEnded)
            Connected: \(call.hasConnected)
            """)
        }
        
        for action in transaction.actions {
            if let end = action as? CXEndCallAction {
                print(" APP REQUESTED END CALL: \(end.callUUID)")
            }

            if let start = action as? CXStartCallAction {
                print(" APP REQUESTED START CALL: \(start.callUUID)")
            }
            
            print("END CALL REQUEST STACK TRACE")

            Thread.callStackSymbols.prefix(25).forEach {
                print($0)
            }

            print("END CALL REQUEST STACK TRACE END\n")
        }
        print("========== CALLKIT ACTIVE CALLS ==========")

        for call in callObserver.calls {
            print("""
            UUID: \(call.uuid)
            Outgoing: \(call.isOutgoing)
            Connected: \(call.hasConnected)
            Ended: \(call.hasEnded)
            """)
        }

        print("Requested UUIDs: \(Array(calls.keys))")
        print("Current UUID: \(String(describing: currentCall))")
        print("==========================================")
        
        

        print("======================================")

        callController?.request(transaction) { error in

            if let error = error {
                print("========== CALLKIT ERROR ==========")
                print("Error: \(error.localizedDescription)")

                for action in transaction.actions {
                    print("Action: \(type(of: action))")

                    if let endAction = action as? CXEndCallAction {
                        print("END CALL UUID: \(endAction.callUUID)")
                    }
                }

                print("Current Call: \(String(describing: self.currentCall))")
                print("Registered Calls: \(Array(self.calls.keys))")
                print("===================================")

                completion(false)
            } else {
                print("[CallKit] Transaction successful")
                completion(true)
            }
        }
    }
    
    private func extractServerData(
        callerId: String,
        alertData: String,
        completion: @escaping (Result<(server: String, token: String, isFromPhone: Bool), Error>) -> Void
    ) {
        guard let decryptedString = decrypt(cipher: alertData, encryptionKey: "0123456789abcdef0123456789abcdef"),
              let data = decryptedString.data(using: .utf8) else {
            completion(.failure(NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decrypt data"])))
            return
        }

        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                guard
                    let server = jsonObject["server"] as? String,
                    let token = jsonObject["token"] as? String
                else {
                    throw NSError(domain: "JSONError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
                }

                let isFromPhone = (jsonObject["isFromPhone"] as? Bool) ?? false
                completion(.success((server: server, token: token, isFromPhone: isFromPhone)))
            } else {
                throw NSError(domain: "JSONError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
            
        case .denied:
            completion(false)
            
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
            
        @unknown default:
            completion(false)
        }
    }
    
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        print("""
           ========== CALL OBSERVER CHANGED ==========
           UUID: \(call.uuid)
           Outgoing: \(call.isOutgoing)
           Connected: \(call.hasConnected)
           Ended: \(call.hasEnded)
           ===========================================
           """)

        isOutgoing = call.isOutgoing
        if call.hasEnded {
            isInCall = false
            //delegate?.callDidEnd()
        } else if !call.hasEnded {
            isInCall = true
            //delegate?.callInprogress()
        } else if call.hasConnected {
            //delegate?.callDidConnected()
        //} else if !call.isOutgoing && !call.hasConnected && !call.hasEnded {
        //} else if !call.isOutgoing && call.hasConnected {
        //    delegate?.callDidConnected()
        }
    }
    
    func providerDidReset(_ provider: CXProvider) {
        for (uuid, _) in calls {
            endCall(uuid: uuid)
        }
    }
    
    func sendDTMF(_ digit: String) {
        SocketSignaling.shared.sendDTMF(digit)
    }
    
    func outgoingCall(handle: String, calleeId: String, calleeName: String, calleeAvatar: String? = "", metaData: [String:String], callData: CallSessionRequest, completion: @escaping (Result<Void, CallError>) -> Void) {
        if (self.currentCall != nil) {
            return completion(.failure(CallError.alreadyIncall))
        }
        self.isSipCall = false
        self.currentCall = UUID.init()
        requestMicrophonePermission { granted in
            if (granted) {
                if let unwrappedCurrentCall = self.currentCall {
                    self.calls[unwrappedCurrentCall] = CallInfo (
                        callId: calleeId,
                        hasVideo: false,
                        callName: calleeName,
                        callAvatar: calleeAvatar ?? "",
                        callType: .OUTGOING,
                        callStatus: .connecting
                    )
                    let cxHandle = CXHandle(type: CXHandle.HandleType.generic, value: handle)
                    let action = CXStartCallAction.init(call: unwrappedCurrentCall, handle: cxHandle)
                    action.isVideo = false
                    let transaction = CXTransaction.init()
                    transaction.addAction(action)
                    self.requestTransaction(transaction: transaction) { success in
                        if success {
                            DispatchQueue.main.async {
                                self.showCallScreen(uuid: unwrappedCurrentCall, callStatus: "connecting")
                            }
                            NotificationManager.shared.showOutgoingCallNotification(callee: handle)
                            
                            guard let bodyData = try? JSONEncoder().encode(callData) else {
                                return
                            }
                            self.calls[unwrappedCurrentCall]?.callStatus = .connecting
                            SocketSignaling.shared.setCallState(.connecting)
                            self.postCallStatus(.connecting)
                            
                            APIService.shared.request(
                                path: "api/sdk-call/one2one",
                                method: "POST",
                                body: bodyData,
                                headers: ["Content-Type": "application/json"],
                                completion: { (result: Result<CallSession, APIError>) in
                                    switch result {
                                    case .success(let callSession):
                                        if let wssUrl = URL(string: callSession.server) {
                                            self.postCallStatus(.calling)
                                            SocketSignaling.shared.connect(wssUrl: wssUrl, token: callSession.token, uuid: unwrappedCurrentCall) { status in
                                                if status == .connected {
                                                    SocketSignaling.shared.initCall()
                                                }
                                            }
                                            completion(.success(()))
                                        } else {
                                            completion(.failure(CallError.internalServerError(code: 505, message: "Server not found")))
                                            self.postNetworkStatus("server_not_found")
                                        }
                                        break
                                    case .failure(let error):
                                        switch error {
                                        case .unauthorized:
                                            completion(.failure(CallError.apiUnauthorized))
                                            self.postNetworkStatus("call_failed_api")
                                        case .badRequest(let data):
                                            completion(.failure(CallError.internalServerError(code: data.code ?? 400, message: data.message)))
                                            self.postNetworkStatus(data.message)
                                        default:
                                            completion(.failure(CallError.internalServerError(code: 500, message: error.localizedDescription)))
                                            self.postNetworkStatus("call_failed_api")
                                        }
                                    }
                                })
                        }
                    }
                }
            } else {
                completion(.failure(CallError.microphonePermissionDenied))
            }
        }
    }
    
    func outgoingCallSip(handle: String, destination: String, destinationName: String, destinationAvatar: String? = "", metaData: [String:String], callData: CallSipSessionRequest, completion: @escaping (Result<Void, CallError>) -> Void) {
        if (self.currentCall != nil) {
            return completion(.failure(CallError.alreadyIncall))
        }
        self.isSipCall = true
        self.currentCall = UUID.init()
        requestMicrophonePermission { granted in
            if (granted) {
                if let unwrappedCurrentCall = self.currentCall {
                    self.calls[unwrappedCurrentCall] = CallInfo (
                        callId: destination,
                        hasVideo: false,
                        callName: destinationName,
                        callAvatar: destinationAvatar ?? "",
                        callType: .OUTGOING,
                        callStatus: .connecting
                    )
                    let cxHandle = CXHandle(type: CXHandle.HandleType.generic, value: handle)
                    let action = CXStartCallAction.init(call: unwrappedCurrentCall, handle: cxHandle)
                    action.isVideo = false
                    let transaction = CXTransaction.init()
                    transaction.addAction(action)
                    self.requestTransaction(transaction: transaction) { success in
                        if success {
                            DispatchQueue.main.async {
                                self.showCallScreen(uuid: unwrappedCurrentCall, callStatus: "connecting")
                            }
                            NotificationManager.shared.showOutgoingCallNotification(callee: handle)
                            
                            guard let bodyData = try? JSONEncoder().encode(callData) else {
                                return
                            }
                            self.calls[unwrappedCurrentCall]?.callStatus = .connecting
                            SocketSignaling.shared.setCallState(.connecting)
                            self.postCallStatus(.connecting)
                            
                            APIService.shared.request(
                                path: "api/sdk-call/app2phone",
                                method: "POST",
                                body: bodyData,
                                headers: ["Content-Type": "application/json"],
                                completion: { (result: Result<CallSession, APIError>) in
                                    switch result {
                                    case .success(let callSession):
                                        if let wssUrl = URL(string: callSession.server) {
                                            self.postCallStatus(.calling)
                                            SocketSignaling.shared.connect(wssUrl: wssUrl, token: callSession.token, uuid: unwrappedCurrentCall) { status in
                                                if status == .connected {
                                                    SocketSignaling.shared.initCall()
                                                }
                                            }
                                            completion(.success(()))
                                        } else {
                                            completion(.failure(CallError.internalServerError(code: 505, message: "Server not found")))
                                            self.postNetworkStatus("server_not_found")
                                        }
                                        break
                                    case .failure(let error):
                                        switch error {
                                        case .unauthorized:
                                            completion(.failure(CallError.apiUnauthorized))
                                            self.postNetworkStatus("call_failed_api")
                                        case .badRequest(let data):
                                            completion(.failure(CallError.internalServerError(code: data.code ?? 400, message: data.message)))
                                            self.postNetworkStatus(data.message)
                                        default:
                                            completion(.failure(CallError.internalServerError(code: 500, message: error.localizedDescription)))
                                            self.postNetworkStatus("call_failed_api")
                                        }
                                    }
                                })
                        }
                    }
                }
            } else {
                completion(.failure(CallError.microphonePermissionDenied))
            }
        }
    }
    
    func reportIncomingCall(
        callerId: String,
        callerName: String,
        avatarUrl: String,
        metaData: [String:String],
        onMessageClicked: (() -> Void)? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let inUUID = UUID()
        self.metaData = metaData
        if let alertData = metaData["alert_data"] {
            self.extractServerData(callerId: callerId, alertData: alertData) { result in
                switch result {
                case .success(let data):
                    let update = CXCallUpdate()
                    update.remoteHandle = CXHandle(type: .generic, value: callerName)
                    update.localizedCallerName = callerName
                    update.hasVideo = false
                    if (self.currentCall != nil && self.isInCall) {
                        SocketSignaling.shared.sendBusyCall(token: data.token)
                        self.provider?.reportCall(with: inUUID, endedAt: Date(), reason: .unanswered)
                    } else {
                        self.provider?.reportNewIncomingCall(with: inUUID, update: update) { error in
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                if let wssUrl = URL(string: data.server) {
                                    SocketSignaling.shared.connect(wssUrl: wssUrl, token: data.token, uuid: inUUID) {_ in
                                        
                                    }
                                    self.currentCall = inUUID
                                    self.postCallStatus(.incoming)
                                    self.calls[inUUID] = CallInfo(
                                        callId: callerId,
                                        hasVideo: false,
                                        callName: callerName,
                                        callAvatar: avatarUrl,
                                        callType: .INCOMING,
                                        callStatus: .incoming
                                    )
                                    SocketSignaling.shared.emit("RINGING_CALL", [:])
                                    completion(.success(()))
                                } else {
                                    self.provider?.reportCall(with: inUUID, endedAt: Date(), reason: .failed)
                                    completion(.failure("" as! Error))
                                }
                            }
                        }
                    }
                    
                case .failure(let error):
                    print(error)
                }
            }
        }
    }
    
    func muteCall(isMuted: Bool) -> Bool {
        let success = SocketSignaling.shared.muteCall(isMuted)
        return success
    }
    
    func missedCall() {
        for (uuid, _) in calls {
            let endCallAction = CXEndCallAction.init(call:uuid)
            let transaction = CXTransaction.init()
            transaction.addAction(endCallAction)
            requestTransaction(transaction: transaction) { success in
                SocketSignaling.shared.setCallState(.missed)
                self.postCallStatus(.ended)
                SocketSignaling.shared.releaseWebrtc()
                self.dismissCallScreen()
                self.currentCall = nil
                self.calls.removeValue(forKey: uuid)
            }
        }
    }
    
    func cleanUpAndEnd(uuid: UUID, state: CallStatus) {
        
    }
    
    func endActiveCall() {
        for (uuid, call) in calls {
            if (call.callType == .OUTGOING && (call.callStatus == .connecting || call.callStatus == .calling)) {
                cancelCall(uuid: uuid)
            } else {
                endCall(uuid: uuid)
            }
        }
    }
    
    func callAccepted() {
        self.postCallStatus(.accepted)
    }
    
    func callConnected() {
        self.postCallStatus(.connected)
    }
    
    func callRejected() {
        if let uuid = currentCall {
            let endCallAction = CXEndCallAction.init(call:uuid)
            let transaction = CXTransaction.init()
            transaction.addAction(endCallAction)
            requestTransaction(transaction: transaction) { success in
                self.postCallStatus(.refused)
                self.calls.removeValue(forKey: uuid)
                if (self.currentCall == uuid) {
                    self.dismissCallScreen()
                    self.currentCall = nil
                }
            }
        }
    }
    
    func callBusy() {
        if let uuid = currentCall {
            let endCallAction = CXEndCallAction.init(call:uuid)
            let transaction = CXTransaction.init()
            transaction.addAction(endCallAction)
            requestTransaction(transaction: transaction) { success in
                self.postCallStatus(.busy)
                self.calls.removeValue(forKey: uuid)
                if (self.currentCall == uuid) {
                    self.dismissCallScreen()
                    self.currentCall = nil
                }
            }
        }
    }
    
    func callRinging() {
        postCallStatus(.ringing)
    }
    
    func answerIncomingCallFromNotification(uuid: UUID?) {
        guard let uuid = uuid else {
            print("[NeoSdkCall] Invalid incoming call UUID")
            return
        }

        guard calls[uuid] != nil else {
            print("[NeoSdkCall] Call not found: \(uuid)")
            return
        }

        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction()
        transaction.addAction(answerAction)

        requestTransaction(transaction: transaction) { success in
            if success {
                print("[NeoSdkCall] Answer call transaction submitted")
            } else {
                print("[NeoSdkCall] Failed to answer call")
            }
        }
    }
    
    func rejectCall() {
        let incomingCalls = calls.filter { $0.value.callType == .INCOMING && $0.value.callStatus == .incoming }
        for (uuid, _) in incomingCalls {
            rejectCall(uuid: uuid)
        }
        
        
    }
    
    func rejectCall(uuid: UUID) {
        let endCallAction = CXEndCallAction.init(call:uuid)
        let transaction = CXTransaction.init()
        transaction.addAction(endCallAction)
        requestTransaction(transaction: transaction) { success in
            SocketSignaling.shared.rejectCall()
            self.postCallStatus(.ended)
            self.calls.removeValue(forKey: uuid)
        }
    }
    
    func cancelCall(uuid: UUID) {
        guard calls[uuid] != nil else {
            print("[CallManager] Call already removed: \(uuid)")
            return
        }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        requestTransaction(transaction: transaction) { [weak self] success in
            guard let self = self else { return }

            if success {
                print("[CallManager] Cancel transaction accepted: \(uuid)")
                // Cleanup akan dilakukan oleh CXEndCallAction callback.
                return
            }

            print("[CallManager] CallKit EndCall failed, using local cleanup: \(uuid)")

            guard self.calls[uuid] != nil else { return }

            SocketSignaling.shared.setCallState(.cancel)
            self.delegate?.onCallStateChanged(.cancel)

            if self.currentCall == uuid {
                SocketSignaling.shared.releaseWebrtc()
                self.dismissCallScreen()
                self.currentCall = nil
            }

            self.calls.removeValue(forKey: uuid)
            self.postCallStatus(.ended)
        }
    }
    
    func endCallOnDeniedMic() {
        if let uuid = self.currentCall {
            let endCallAction = CXEndCallAction.init(call:uuid)
            let transaction = CXTransaction.init()
            transaction.addAction(endCallAction)
            requestTransaction(transaction: transaction) { success in
                SocketSignaling.shared.setCallState(.ended)
                self.postCallStatus(.ended)
                SocketSignaling.shared.releaseWebrtc()
                self.calls.removeValue(forKey: uuid)
                self.currentCall = nil
            }
        }
    }
    
    func endCall(uuid: UUID) {

        //  UUID masih terdaftar
        guard calls[uuid] != nil else {
            print("[CallManager] Ignore duplicate EndCall: \(uuid)")
            return
        }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        requestTransaction(transaction: transaction) { success in

            guard success else {
                print("[CallManager] EndCall transaction failed: \(uuid)")
                return
            }

            SocketSignaling.shared.setCallState(.ended)
            self.postCallStatus(.ended)

            if self.currentCall == uuid {
                SocketSignaling.shared.releaseWebrtc()
                self.dismissCallScreen()
                self.currentCall = nil
            }

            self.calls.removeValue(forKey: uuid)
        }
    }
    
    func endedCall(uuid: UUID, callState: CallStatus) {
        print("[CallManager] Remote call ended: \(uuid)")

        // Beri tahu CallKit bahwa panggilan berakhir dari sisi remote/server.
        provider?.reportCall(
            with: uuid,
            endedAt: Date(),
            reason: .remoteEnded
        )

        // Hindari cleanup berulang.
        guard calls[uuid] != nil || currentCall == uuid else {
            print("[CallManager] Call already cleaned up: \(uuid)")
            return
        }

        SocketSignaling.shared.setCallState(callState)
        delegate?.onCallStateChanged(callState)

        if currentCall == uuid {
            SocketSignaling.shared.releaseWebrtc()
            dismissCallScreen()
            currentCall = nil
        }

        calls.removeValue(forKey: uuid)
        postCallStatus(.ended)

        print("[CallManager] Remote call cleanup completed: \(uuid)")
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("[CallKit] StartCallAction: \(action.callUUID)")

        provider.reportOutgoingCall(
            with: action.callUUID,
            startedConnectingAt: Date()
        )

        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if (!self.screenIsShown) {
                self.showCallScreen(uuid: action.callUUID ,callStatus: "connecting")
            }
        }
        
        self.postCallStatus(.connecting)
        self.calls[action.callUUID]?.callStatus = .connecting
        
        for (uuid, _) in self.calls {
            if (uuid != action.callUUID) {
                self.endCall(uuid: uuid)
            } else {
                //self.currentCall = action.callUUID
                SocketSignaling.shared.answerCall() {
                    self.calls[action.callUUID]?.callStatus = .connected
                    SocketSignaling.shared.initOffer()
                }
            }
        }
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        //print("Something else held")
        if action.isOnHold {
            //todo: stop audio
        } else {
            //todo: start audio
        }
        
        //delegate?.callDidHold(isOnHold: action.isOnHold)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let success = SocketSignaling.shared.muteCall(action.isMuted)
        print("mute \(success)")
        let session = AVAudioSession.sharedInstance()
        defaultVolume = session.inputGain
        /*if session.isInputGainSettable {
            try? session.setInputGain(action.isMuted ? 0.0 : defaultVolume)
        }*/
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
    }
    
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fulfill()
    }
    
    /// Called when the provider's audio session activation state changes.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("🔊 Audio session activated")
        self.configureAudioSession()
        if let _ = currentCall {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                SocketSignaling.shared.initOffer()
            }
        }
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("🔇 Audio session deactivated")
        if let _ = currentCall {
            SocketSignaling.shared.releaseWebrtc()
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("========== END ACTION RECEIVED ==========")
        print("UUID: \(action.callUUID)")
        print("Current Call: \(String(describing: currentCall))")
        print("Call Exists: \(calls[action.callUUID] != nil)")
        print("Call Status: \(String(describing: calls[action.callUUID]?.callStatus))")
        print("Call Type: \(String(describing: calls[action.callUUID]?.callType))")
        print("==========================================")

        action.fulfill()
    }
    
    func postCallStatus(_ status: CallStatus) {
            switch status {
            case .ended, .refused, .cancel, .missed, .busy, .timeout, .call_error:
                NotificationManager.shared.clearCallNotifications()
            case .accepted, .connected, .ongoing:
                NotificationManager.shared.clearOutgoingNotification()
            default:
                break
            }
            
            delegate?.onCallStateChanged(status)
            NotificationCenter.default.post(name: .callStatusChanged, object: nil, userInfo: ["status" : status.rawValue])
    }
    
    private func postNetworkStatus(_ status: String) {
        NotificationCenter.default.post(name: .callNetworkChanged, object: nil, userInfo: ["error" : status])
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if audioSession.category != .playAndRecord {
                try audioSession.setCategory(AVAudioSession.Category.playAndRecord,
                                             options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            }
            if audioSession.mode != .voiceChat {
                try audioSession.setMode(.voiceChat)
            }
        } catch {
            print("Error configuring AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    private func showCallScreen(uuid: UUID, callStatus: String) {
        guard self.calls[uuid] != nil else { return }
        self.screenIsShown = true
        // Tutup window lama jika ada
        self.callWindow?.isHidden = true
        self.callWindow = nil

        let vc: UIViewController
        if #available(iOS 13.0, *) {
            vc = UIHostingController(rootView: CallScreenWrapper(
                calleeName: self.calls[uuid]!.callName,
                callStatus: callStatus,
                avatarUrl: self.calls[uuid]!.callAvatar,
                isSipCall: self.isSipCall,
                metaData: self.metaData
            ))
        } else {
            let screen = CallScreenViewController()
            screen.callStatus = callStatus
            screen.calleeName = self.calls[uuid]!.callName
            screen.avatarUrl = self.calls[uuid]!.callAvatar
            screen.isSipCall = self.isSipCall
            screen.metaData = self.metaData
            vc = screen
        }

        let newWindow: UIWindow
        if #available(iOS 13.0, *) {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first

            if let windowScene = scene {
                newWindow = UIWindow(windowScene: windowScene)
            } else {
                newWindow = UIWindow(frame: UIScreen.main.bounds)
            }
        } else {
            newWindow = UIWindow(frame: UIScreen.main.bounds)
        }

        newWindow.frame = UIScreen.main.bounds
        newWindow.rootViewController = vc
        newWindow.windowLevel = .alert + 1
        newWindow.makeKeyAndVisible()

        self.callWindow = newWindow
        self.callVC = vc
    }

    func dismissCallScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.callWindow?.isHidden = true
            if #available(iOS 13.0, *) {
                self.callWindow?.windowScene = nil
            }
            self.callWindow = nil
            self.callVC = nil
            self.screenIsShown = false
        }
    }
    
    func bringCurrentCallScreenToFront() {
        DispatchQueue.main.async {
            guard let uuid = self.currentCall,
                  let call = self.calls[uuid] else {
                print("[NeoSdkCall] No active call")
                return
            }

            if self.screenIsShown {
                self.callWindow?.makeKeyAndVisible()
            } else {
                self.showCallScreen(
                    uuid: uuid,
                    callStatus: call.callStatus?.rawValue ?? "connecting"
                )
            }
        }
    }
    
}

enum CallType: String {
    case OUTGOING
    case INCOMING
}

struct CallInfo {
    var callId: String
    var hasVideo: Bool
    var callName: String
    var callAvatar: String
    var callType: CallType
    var callStatus: CallStatus?
    var alertData: String?
}

struct CallSessionRequest: Codable {
    let callerId: String
    let callerName: String
    let callerAvatar: String
    let calleeId: String
    let calleeName: String
    let calleeAvatar: String
    let checkSum: String
}

struct CallSipSessionRequest: Codable {
    let callerId: String
    let callerName: String
    let callerAvatar: String
    let destination: String
}

struct CallSession: Decodable {
    let server: String
    let token: String
    let isFromPhone: Bool?
}


protocol CallServiceDelegate: AnyObject {
    func endCall(uuid: UUID)
    func endedCall(uuid: UUID, callState: CallStatus)
    func callAccepted()
    func callConnected()
    func callRinging()
    func callRejected()
    func callBusy()
}

func decrypt(cipher: String, encryptionKey: String) -> String? {
    // Pisahkan iv dan ciphertext berdasarkan tanda ":"
    let components = cipher.split(separator: ":")
    guard components.count == 2 else { return nil }
    
    let ivHex = String(components[0])
    let encryptedHex = String(components[1])
    
    // Konversi hex ke Data
    guard let iv = Data(hex: ivHex),
          let encryptedData = Data(hex: encryptedHex),
          let keyData = encryptionKey.data(using: .utf8) else {
        return nil
    }
    
    let keyLength = kCCKeySizeAES256
    guard keyData.count == keyLength else {
        return nil
    }
    
    // Siapkan buffer sementara untuk hasil dekripsi
    let bufferSize = encryptedData.count + kCCBlockSizeAES128
    var buffer = Data(count: bufferSize)
    var numBytesDecrypted: size_t = 0
    
    let cryptStatus = buffer.withUnsafeMutableBytes { bufferBytes in
        encryptedData.withUnsafeBytes { encryptedBytes in
            iv.withUnsafeBytes { ivBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        keyLength,
                        ivBytes.baseAddress,
                        encryptedBytes.baseAddress,
                        encryptedData.count,
                        bufferBytes.baseAddress,
                        bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }
    }
    
    if cryptStatus == kCCSuccess {
        let decryptedData = buffer.prefix(numBytesDecrypted)
        return String(data: decryptedData, encoding: .utf8)
    } else {
        print(" Dekripsi gagal dengan status \(cryptStatus)")
        return nil
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            if nextIndex > hex.endIndex { return nil }
            let bytes = hex[index..<nextIndex]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
    
    
}
