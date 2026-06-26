import UIKit
import CallKit
import AVFoundation
import Network

public class CallScreenViewController: UIViewController {
    
    var calleeName: String = ""
    var callStatus: String = ""
    var avatarUrl: String? = ""
    var isSipCall: Bool = false
    
    var metaData: [String: String] = [:]
    var dismissed = true
    var pendingDismissed = false
    
    let monitor = NWPathMonitor()
    let queue = DispatchQueue.global(qos: .background)
    var isNetworkReallyDown = false
    var checkTimer: DispatchWorkItem?
    
    // MARK: - UI Elements
    private let nameLabel = UILabel()
    var statusLabel = UILabel()
    private let durationLabel = UILabel()
    private var showKeypad = false
    private let avatarImageView = UIImageView()
    private let connectionLabel = UILabel()
    private var incomingButtonStack: UIStackView!
    private var connectedButtonStack: UIStackView!
    private var callerInfoStack: UIStackView!
    private var statusStack: UIStackView!
    
    private let keypadView = DTMFKeypadView()
    private var keypadButton: CircleIconButton!
    
    private var muteButton: CircleIconButton!
    private var speakerButton: CircleIconButton!
    private var endButton: CircleIconButton!
    private var isMuted: Bool = false
    private var isSpeakerOn: Bool = false
    private var isConnected: Bool = false
    
    private var onMessageClicked: (() -> Void)?
    
    private var status: CallStatus?
    
    init(onMessageClicked: (() -> Void)? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.onMessageClicked = onMessageClicked
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let gradientBackground = MultiLayerGradientView(frame: view.bounds)
        gradientBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(gradientBackground, at: 0)
        
        monitor.pathUpdateHandler = { path in
            // Reset timer setiap ada perubahan path
            self.checkTimer?.cancel()

            if path.status == .unsatisfied {
                // Delay 3 detik untuk memastikan benar-benar tidak ada koneksi
                let task = DispatchWorkItem {
                    if self.monitor.currentPath.status == .unsatisfied {
                        DispatchQueue.main.async {
                            if !self.isNetworkReallyDown {
                                self.isNetworkReallyDown = true
                                self.showErrorConnectionAlert(
                                    text: self.metaData["call_failed_no_connection"] ?? "No internet connection",
                                    icon: nil
                                )
                            }
                        }
                    }
                }
                self.checkTimer = task
                DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: task)
            } else {
                // Kalau koneksi balik lagi
                self.isNetworkReallyDown = false
            }
        }
        monitor.start(queue: queue)

        setupUI()
            //setupKeypadView()
        requestMicrophonePermission { granted in
            /*if !granted {
                CallManager.sharedInstance.endCallOnDeniedMic()
                self.showErrorConnectionAlert(text: self.metaData["call_failed_mic_permission_denied"] ?? "Call failed, mic permission denied",icon: nil)
            }*/
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleCallStatus(_:)), name: .callStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(callProfileSet(_:)), name: .callProfileSet, object: "")
        NotificationCenter.default.addObserver(self, selector: #selector(handleNetworkSignal(_:)), name: .callNetworkChanged, object: nil)
        /*NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissScreen),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )*/
    }
    
    @objc private func handleNetworkSignal(_ notification: Notification) {
        guard let value = (notification.userInfo?["signalStrength"] as? String)
            ?? (notification.userInfo?["error"] as? String)
        else {
            return
        }
        DispatchQueue.main.async {
            if (self.isConnected) {
                switch value {
                case "weak":
                    self.connectionLabel.text = "\(self.metaData["call_weak_signal"] ?? "Weak signal")..."
                    self.connectionLabel.textColor = .systemRed
                case "lost":
                    self.connectionLabel.text = "\(self.metaData["call_lost_connection"] ?? "Lost connection")..."
                    self.connectionLabel.textColor = .systemRed
                case "reconnecting":
                    self.connectionLabel.text = "\(self.metaData["call_reconnecting"] ?? "Reconnecting")..."
                    self.connectionLabel.textColor = .systemRed
                default:
                    self.connectionLabel.text = ""
                }
            } else if (notification.userInfo?["error"] != nil) {
                self.showErrorConnectionAlert(text: self.metaData[value] ?? value, icon: AsssetKitImageProvider.Resources.errorIcon.image)
            }
        }
    }
    
    @objc private func callProfileSet(_ notification: Notification) {
        let nameString = (notification.userInfo?["name"] as? String) ?? ""
        let avatarString = (notification.userInfo?["avatar"] as? String) ?? ""
        
        DispatchQueue.main.async {
            self.calleeName = nameString.isEmpty ? "Call INA" : nameString
            
            if let callNameTitle = self.metaData["call_name_title"] {
                if (!callNameTitle.isEmpty) {
                    self.calleeName = callNameTitle
                }
            }
            
            self.nameLabel.text = self.calleeName
        }
        
        if !avatarString.isEmpty {
            if avatarString.hasPrefix("http"), let url = URL(string: avatarString) {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data {
                        DispatchQueue.main.async {
                            self.avatarImageView.image = UIImage(data: data)
                        }
                    }
                }.resume()
            } else {
                DispatchQueue.main.async {
                    self.avatarImageView.image = UIImage(named: avatarString) ?? UIImage(named: "neocall") ?? ImageAsset(name: "neocall").image
                    self.avatarImageView.backgroundColor = .white
                }
            }
        } else {
            DispatchQueue.main.async {
                self.avatarImageView.image = UIImage(named: "neocall") ?? ImageAsset(name: "neocall").image
                self.avatarImageView.backgroundColor = .white
            }
        }
    }
    
    @objc private func handleCallStatus(_ notification: Notification) {
        guard let statusString = notification.userInfo?["status"] as? String,
              let status = CallStatus(rawValue: statusString) else { return }
        
        self.callStatus = status.rawValue
        DispatchQueue.main.async {
            self.endButton.button.isEnabled = true
        }
        
        DispatchQueue.main.async {
            switch status {
            case .incoming:
                self.isConnected = false
                self.statusLabel.text = self.getLocalizedStatus("call_incoming")
                //self.updateUIForIncomingCall()
            case .calling:
                self.isConnected = false
                self.statusLabel.text = self.getLocalizedStatus("call_calling")
                //self.updateUIForOutgoingCall()
            case .ongoing:
                self.isConnected = true
                self.statusLabel.text = self.getLocalizedStatus("call_connected")
                self.muteButton?.isEnabled = true
                self.keypadButton?.isEnabled = true
                self.startCallDurationTimer()
                DispatchQueue.main.async {
                    self.incomingButtonStack.isHidden = true
                    self.connectedButtonStack.isHidden = false
                }
            case .ended:
                self.statusLabel.text = self.getLocalizedStatus("call_end")
                self.endedCall(delay: 0.5)
            case .accepted:
                self.statusLabel.text = self.getLocalizedStatus("call_accepted")
            case .connected:
                self.isConnected = true
                self.statusLabel.text = self.getLocalizedStatus("call_connected")
                //NotificationManager.shared.showOngoingCallNotification(callee: self.calleeName)
                self.muteButton?.isEnabled = true
                self.keypadButton?.isEnabled = true
                self.startCallDurationTimer()
                DispatchQueue.main.async {
                    self.incomingButtonStack.isHidden = true
                    self.connectedButtonStack.isHidden = false
                }
            case .connecting:
                self.isConnected = false
                self.statusLabel.text = self.getLocalizedStatus("call_connecting")
                self.muteButton?.isEnabled = false
                self.keypadButton?.isEnabled = false
                DispatchQueue.main.async {
                    self.incomingButtonStack.isHidden = true
                    self.connectedButtonStack.isHidden = false
                }
            case .reconnecting:
                self.isConnected = false
                self.statusLabel.text = self.getLocalizedStatus("call_reconnecting")
                self.muteButton?.isEnabled = false
                self.keypadButton?.isEnabled = false
            case .ringing:
                self.statusLabel.text = self.getLocalizedStatus("call_ringing")
            case .answering:
                self.statusLabel.text = self.getLocalizedStatus("call_answering")
            case .busy:
                self.statusLabel.text = self.getLocalizedStatus("call_busy")
                self.endedCall(delay: 1.5)
            case .refused:
                self.statusLabel.text = self.getLocalizedStatus("call_refused")
                self.endedCall(delay: 1.5)
            case .timeout:
                self.statusLabel.text = self.getLocalizedStatus("call_timeout")
                self.endedCall(delay: 1.5)
            case .cancel:
                self.statusLabel.text = self.getLocalizedStatus("call_cancel")
                self.endedCall()
            default:
                break;
            }
        }
        self.status = status
    }
    
    @objc func toggleKeypad() {
        // guard isSipCall else { return } // Dihapus agar keypad bisa tampil di call apa saja (App2App & App2Phone)

        keypadView.delegate = self
        keypadView.show(in: self.view)
        UIView.animate(withDuration: 0.3) {
            self.callerInfoStack.alpha = 0
            self.statusStack.alpha = 0
        }
    }
    
    private func showErrorConnectionAlert(text: String, icon: UIImage?) {
        let toast = Alert(
            message: text,
            icon: icon
        ) {
            self.endedCall(delay: 0.0)
            CallManager.sharedInstance.endActiveCall()
            CallManager.sharedInstance.dismissCallScreen()
        }
        DispatchQueue.main.async {
            toast.show(in: self.view)
        }
    }

    func endedCall(delay: Double = 1.5) {
        //if (!dismissed) {
        self.isConnected = false
     //   self.pendingDismissed = true
        self.callDurationTimer?.invalidate()
        self.durationLabel.text = ""
        self.muteButton?.isEnabled = false
        self.keypadButton?.isEnabled = false
        self.speakerButton?.isEnabled = false
        self.endButton?.isEnabled = false
        //print("end call")
        //}
        //SocketManagerSignaling.shared.disconnect()
    }
    
    /*@objc private func dismissScreen() {
        if (self.pendingDismissed) {
            self.dismissed = true
            self.pendingDismissed = false
            //print("dismissed")
            //CallService.sharedInstance.callVC = nil
            CallService.sharedInstance.closedCall()
        }
    }*/
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        monitor.cancel()
    }
    
    func compatibleImage(named: String, systemName: String) -> UIImage? {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: systemName) ?? UIImage(named: named)
        } else {
            return UIImage(named: named)
        }
    }
    
    /*private func setupKeypadView() {
        
        keypadView.delegate = self
        keypadView.translatesAutoresizingMaskIntoConstraints = false
        keypadView.isHidden = true

        view.addSubview(keypadView)

        NSLayoutConstraint.activate([
            keypadView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            keypadView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            keypadView.bottomAnchor.constraint(equalTo: keypadButton.topAnchor, constant: -20),
            keypadView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }*/
    
    private func getLocalizedStatus(_ key: String) -> String {
        if let val = self.metaData[key], !val.isEmpty {
            return val
        }
        switch key {
        case "call_incoming": return "Incoming"
        case "call_calling": return "Menghubungi..."
        case "call_connected": return "Terhubung"
        case "call_end": return "Panggilan Berakhir"
        case "call_accepted": return "Call Accepted"
        case "call_connecting": return "Menghubungi..."
        case "call_reconnecting": return "Reconnecting..."
        case "call_ringing": return "Ringing..."
        case "call_answering": return "Answering"
        case "call_busy": return "Busy"
        case "call_refused": return "Declined"
        case "call_timeout": return "No Answer"
        case "call_cancel": return "Canceled"
        default:
            let cleanKey = key.replacingOccurrences(of: "call_", with: "")
            return cleanKey.isEmpty ? "Calling" : cleanKey.capitalized
        }
    }
    
    private func setupUI() {
        self.dismissed = false
        self.pendingDismissed = false
        self.isConnected = false
        
        statusLabel.text = getLocalizedStatus("call_\(callStatus)")
        statusLabel.font = UIFont.systemFont(ofSize: 18)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        
        statusStack = UIStackView(arrangedSubviews: [statusLabel])
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)
        
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 80
        avatarImageView.layer.borderWidth = 2
        avatarImageView.layer.borderColor = UIColor.white.cgColor
        avatarImageView.clipsToBounds = true
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        
        if let callNameTitle = metaData["call_name_title"], !callNameTitle.isEmpty {
            calleeName = callNameTitle
        }
        
        if calleeName.isEmpty {
            calleeName = "Call INA"
        }
        
        nameLabel.text = calleeName
        nameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        
        durationLabel.text = ""
        durationLabel.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        
        connectionLabel.text = ""
        connectionLabel.font = UIFont.systemFont(ofSize: 14)
        connectionLabel.textColor = UIColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1.0)
        connectionLabel.textAlignment = .center
        
        callerInfoStack = UIStackView(arrangedSubviews: [avatarImageView, nameLabel, durationLabel, connectionLabel])
        callerInfoStack.axis = .vertical
        callerInfoStack.spacing = 16
        callerInfoStack.alignment = .center
        callerInfoStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(callerInfoStack)
 
        if let avatarString = avatarUrl, !avatarString.isEmpty {
            if avatarString.hasPrefix("http"), let url = URL(string: avatarString) {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data { DispatchQueue.main.async { self.avatarImageView.image = UIImage(data: data) } }
                }.resume()
            } else {
                // Jika bukan URL http, anggap itu adalah nama gambar dari Assets lokal klien
                self.avatarImageView.image = UIImage(named: avatarString) ?? UIImage(named: "neocall") ?? ImageAsset(name: "neocall").image
                self.avatarImageView.backgroundColor = .white
            }
        } else {
            self.avatarImageView.image = UIImage(named: "neocall") ?? ImageAsset(name: "neocall").image
            self.avatarImageView.backgroundColor = .white
        }

        let infoCard = UIView()
        infoCard.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        infoCard.layer.cornerRadius = 16
        infoCard.translatesAutoresizingMaskIntoConstraints = false
        
        let infoIcon = UIImageView(image: compatibleImage(named: "info.circle", systemName: "info.circle"))
        infoIcon.tintColor = .white
        infoIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let infoText = UILabel()
        infoText.text = "Pastikan perangkat kamu terhubung dengan jaringan internet yang stabil untuk melakukan panggilan ini"
        infoText.textColor = .white
        infoText.font = UIFont.systemFont(ofSize: 12)
        infoText.numberOfLines = 0
        infoText.translatesAutoresizingMaskIntoConstraints = false
        
        infoCard.addSubview(infoIcon)
        infoCard.addSubview(infoText)
        view.addSubview(infoCard)
        
        incomingButtonStack = UIStackView(arrangedSubviews: incomingbuttons())
        incomingButtonStack.axis = .vertical
        incomingButtonStack.spacing = 30
        incomingButtonStack.alignment = .center
        incomingButtonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingButtonStack)
        
        connectedButtonStack = UIStackView(arrangedSubviews: connectedButtons())
        connectedButtonStack.axis = .vertical
        connectedButtonStack.spacing = 30
        connectedButtonStack.alignment = .center
        connectedButtonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectedButtonStack)

        NSLayoutConstraint.activate([
            statusStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            avatarImageView.widthAnchor.constraint(equalToConstant: 160),
            avatarImageView.heightAnchor.constraint(equalToConstant: 160),
            
            callerInfoStack.topAnchor.constraint(equalTo: statusStack.bottomAnchor, constant: 40),
            callerInfoStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            callerInfoStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            callerInfoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            
            infoCard.bottomAnchor.constraint(equalTo: incomingButtonStack.topAnchor, constant: -30),
            infoCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            infoCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            
            infoIcon.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            infoIcon.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 16),
            infoIcon.widthAnchor.constraint(equalToConstant: 20),
            infoIcon.heightAnchor.constraint(equalToConstant: 20),
            
            infoText.leadingAnchor.constraint(equalTo: infoIcon.trailingAnchor, constant: 12),
            infoText.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            infoText.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 16),
            infoText.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -16),
            
            incomingButtonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            incomingButtonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            incomingButtonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            incomingButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            connectedButtonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectedButtonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            connectedButtonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectedButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        if (callStatus == "incoming")  {
            incomingButtonStack.isHidden = false
            connectedButtonStack.isHidden = true
            self.isConnected = false
        } else {
            incomingButtonStack.isHidden = true
            connectedButtonStack.isHidden = false
            if callStatus == "connected" || callStatus == "ongoing" {
                self.isConnected = true
                self.muteButton?.isEnabled = true
                self.keypadButton?.isEnabled = true
                self.startCallDurationTimer()
            } else {
                self.isConnected = false
            }
        }
    }
    
    var callDurationTimer: Timer?
    var secondsElapsed: Int = 0

    func startCallDurationTimer() {
        callDurationTimer?.invalidate()
        secondsElapsed = 0
        DispatchQueue.main.async {
          self.callDurationTimer = Timer.scheduledTimer(timeInterval: 1.0,
                                                        target: self,
                                                        selector: #selector(self.updateCallDuration),
                                                        userInfo: nil,
                                                        repeats: true)
        }
    }

    @objc func updateCallDuration() {
        secondsElapsed += 1
        let minutes = secondsElapsed / 60
        let seconds = secondsElapsed % 60
        self.durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func incomingbuttons()-> [UIView]{
        muteButton = CircleIconButton(
            icon: compatibleImage(named: "mic.slash", systemName: "mic.slash"),
            labelText: self.metaData["call_btn_mute"] ?? "Mute",
            iconColor: .white,
            backgroundColor: UIColor(white: 1.0, alpha: 0.2)
        ) {
            if (SocketSignaling.shared.muteCall(!self.isMuted)) {
                self.isMuted.toggle()
            }
            self.muteButton.icon = self.isMuted ? self.compatibleImage(named: "mic.slash", systemName: "mic.slash.fill") : self.compatibleImage(named: "mic.slash", systemName: "mic.slash")
            self.muteButton.button.tintColor = .white
            self.muteButton.button.backgroundColor = self.isMuted ? .systemRed : UIColor(white: 1.0, alpha: 0.2)
        }
        muteButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        muteButton.isEnabled = false
        
        speakerButton = CircleIconButton(
            icon: compatibleImage(named: "speaker", systemName: "speaker.wave.2"),
            labelText: self.metaData["call_btn_speaker"] ?? "Speaker",
            iconColor: .white,
            backgroundColor: UIColor(white: 1.0, alpha: 0.2)
        ) {
            self.isSpeakerOn.toggle()
            self.speakerButton.icon = self.isSpeakerOn ? self.compatibleImage(named: "speaker", systemName: "speaker.wave.2.fill") : self.compatibleImage(named: "speaker", systemName: "speaker.wave.2")
            self.speakerButton.button.tintColor = .white
            self.speakerButton.button.backgroundColor =  self.isSpeakerOn ? .systemRed : UIColor(white: 1.0, alpha: 0.2)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try session.setActive(true)
                if self.isSpeakerOn {
                    try session.overrideOutputAudioPort(.speaker)
                } else {
                    try session.overrideOutputAudioPort(.none)
                }
            } catch {
                print("Failed to set audio session: \(error)")
            }
        }
        speakerButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        
        let audioButtonStack = UIStackView(arrangedSubviews: [speakerButton, muteButton])
        audioButtonStack.axis = .horizontal
        audioButtonStack.spacing = 80
        audioButtonStack.distribution = .equalCentering
        audioButtonStack.alignment = .center
        audioButtonStack.translatesAutoresizingMaskIntoConstraints = false
        audioButtonStack.isUserInteractionEnabled = true
        
        let endCallButton = CircleIconButton(
            icon: compatibleImage(named: "phone.down.fill", systemName: "phone.down.fill"),
            labelText: self.metaData["call_end"] ?? "Akhiri Panggilan",
            iconColor: .white,
            backgroundColor: .systemRed
        ) {
        }
        endCallButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        let answerCallButton = CircleIconButton(
            icon: compatibleImage(named: "phone.fill", systemName: "phone.fill"),
            labelText: self.metaData["answer"] ?? "Terima",
            iconColor: .white,
            backgroundColor: .systemGreen
        ) {
        }
        answerCallButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        let actionButtonStack = UIStackView(arrangedSubviews: [endCallButton, answerCallButton])
        actionButtonStack.axis = .horizontal
        actionButtonStack.spacing = 80
        actionButtonStack.distribution = .equalCentering
        actionButtonStack.alignment = .fill
        actionButtonStack.translatesAutoresizingMaskIntoConstraints = false
        actionButtonStack.isUserInteractionEnabled = true
        return [audioButtonStack, actionButtonStack]
    }
    
    private func connectedButtons()-> [UIView]{
        muteButton = CircleIconButton(
            icon: compatibleImage(named: "mic.slash", systemName: "mic.slash"),
            labelText: self.metaData["call_btn_mute"] ?? "Mute",
            iconColor: .white,
            backgroundColor: UIColor(white: 1.0, alpha: 0.2)
        ) {
            if (SocketSignaling.shared.muteCall(!self.isMuted)) {
                self.isMuted.toggle()
            }
            self.muteButton.icon = self.isMuted ? self.compatibleImage(named: "mic.slash", systemName: "mic.slash.fill") : self.compatibleImage(named: "mic.slash", systemName: "mic.slash")
            self.muteButton.button.tintColor = .white
            self.muteButton.button.backgroundColor = self.isMuted ? .systemRed : UIColor(white: 1.0, alpha: 0.2)
        }
        muteButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        muteButton.isEnabled = false
        
        keypadButton = CircleIconButton(
            icon: compatibleImage(named: "keypad", systemName: "circle.grid.3x3.fill"),
            labelText: self.metaData["call_numpad"] ?? "Keypad",
            iconColor: .white,
            backgroundColor: UIColor(white: 1.0, alpha: 0.2)
        ) { [weak self] in
            self?.toggleKeypad()
        }
        keypadButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        keypadButton.isEnabled = false
        
        speakerButton = CircleIconButton(
            icon: compatibleImage(named: "speaker", systemName: "speaker.wave.2"),
            labelText: self.metaData["call_btn_speaker"] ?? "Speaker",
            iconColor: .white,
            backgroundColor: UIColor(white: 1.0, alpha: 0.2)
        ) {
            self.isSpeakerOn.toggle()
            self.speakerButton.icon = self.isSpeakerOn ? self.compatibleImage(named: "speaker", systemName: "speaker.wave.2.fill") : self.compatibleImage(named: "speaker", systemName: "speaker.wave.2")
            self.speakerButton.button.tintColor = .white
            self.speakerButton.button.backgroundColor =  self.isSpeakerOn ? .systemRed : UIColor(white: 1.0, alpha: 0.2)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try session.setActive(true)
                if self.isSpeakerOn {
                    try session.overrideOutputAudioPort(.speaker)
                } else {
                    try session.overrideOutputAudioPort(.none)
                }
            } catch {
                print("Failed to set audio session: \(error)")
            }
        }
        speakerButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        
        let audioButtonStack = UIStackView(arrangedSubviews: [keypadButton, speakerButton, muteButton])
        audioButtonStack.axis = .horizontal
        audioButtonStack.distribution = .equalCentering
        audioButtonStack.alignment = .center
        audioButtonStack.translatesAutoresizingMaskIntoConstraints = false
        audioButtonStack.isUserInteractionEnabled = true
        audioButtonStack.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width - 80).isActive = true
        
        endButton = CircleIconButton(
            icon: compatibleImage(named: "phone.down.fill", systemName: "phone.down.fill"),
            labelText: self.metaData["call_end"] ?? "Akhiri Panggilan",
            iconColor: .white,
            backgroundColor: .systemRed
        ) {
            CallManager.sharedInstance.endActiveCall()
        }
        endButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        
        let endButtonStack = UIStackView(arrangedSubviews: [endButton])
        endButtonStack.axis = .horizontal
        endButtonStack.alignment = .center
        endButtonStack.translatesAutoresizingMaskIntoConstraints = false
        
        return [audioButtonStack, endButtonStack]
    }
    
}

extension CallScreenViewController: DTMFKeypadDelegate {

    func didPressDTMF(_ digit: String) {
        CallManager.sharedInstance.sendDTMF(digit)
    }
    
    func keypadDidClose() {
        UIView.animate(withDuration: 0.3) {
            self.callerInfoStack.alpha = 1
            self.statusStack.alpha = 1
        }
    }

}

extension UIColor {
  /// Initialize from hex string (supports 6 or 8 hex digits, with optional "#").
  public convenience init?(hex: String) {
    var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if hexStr.hasPrefix("#") {
      hexStr.removeFirst()
    }
    guard hexStr.count == 6 || hexStr.count == 8,
          let hexVal = UInt64(hexStr, radix: 16) else {
      return nil
    }
    let r, g, b, a: UInt64
    if hexStr.count == 6 {
      a = 255
      r = (hexVal >> 16) & 0xFF
      g = (hexVal >> 8) & 0xFF
      b = hexVal & 0xFF
    } else { // 8 characters = AARRGGBB
      a = (hexVal >> 24) & 0xFF
      r = (hexVal >> 16) & 0xFF
      g = (hexVal >> 8) & 0xFF
      b = hexVal & 0xFF
    }
    self.init(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
}
	
