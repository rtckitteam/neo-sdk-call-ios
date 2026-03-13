import UIKit
import AVFoundation

class DTMFToneGenerator {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private let sampleRate: Double = 44100

    init() {
        engine.attach(player)

        let mixer = engine.mainMixerNode
        engine.connect(player, to: mixer, format: mixer.outputFormat(forBus: 0))

        try? engine.start()
    }

    func play(digit: String, duration: Double = 0.15) {

        guard let (f1, f2) = dtmfFrequencies[digit] else { return }

        let frameCount = AVAudioFrameCount(sampleRate * duration)

        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        )!

        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]

        for i in 0..<Int(frameCount) {

            let t = Double(i) / sampleRate

            let sample =
                sin(2 * .pi * f1 * t) +
                sin(2 * .pi * f2 * t)

            samples[i] = Float(sample * 0.5)
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)

        if !player.isPlaying {
            player.play()
        }
    }

    private let dtmfFrequencies: [String:(Double,Double)] = [
        "1":(697,1209),
        "2":(697,1336),
        "3":(697,1477),
        "4":(770,1209),
        "5":(770,1336),
        "6":(770,1477),
        "7":(852,1209),
        "8":(852,1336),
        "9":(852,1477),
        "*":(941,1209),
        "0":(941,1336),
        "#":(941,1477)
    ]
}

protocol DTMFKeypadDelegate: AnyObject {
    func didPressDTMF(_ digit: String)
    func keypadDidClose()
}

class DTMFKeypadView: UIView {

    weak var delegate: DTMFKeypadDelegate?

    private var inputText = ""

    private let displayLabel = UILabel()
    private let backspaceButton = UIButton(type: .system)
    private let containerView = UIView()
    
    //let dtmfTone = DTMFToneGenerator()

    private let keys: [[String]] = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        ["*","0","#"]
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlay()
    }

    private func setupOverlay() {

        backgroundColor = UIColor.black.withAlphaComponent(0.3)

        containerView.backgroundColor = .white
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 420)
        ])

        setupDisplay()
        setupKeypad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }
    
    @objc private func handleOverlayTap(_ gesture: UITapGestureRecognizer) {

        let location = gesture.location(in: self)

        // cek apakah tap terjadi di luar containerView
        if !containerView.frame.contains(location) {
            hide()
            delegate?.keypadDidClose()
        }
    }

    private func setupDisplay() {

        displayLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        displayLabel.textAlignment = .center
        displayLabel.text = ""
        if #available(iOS 13.0, *) {
            displayLabel.textColor = .black
        } else {
            displayLabel.textColor = .black
        }
        displayLabel.translatesAutoresizingMaskIntoConstraints = false

        backspaceButton.setTitle("⌫", for: .normal)
        backspaceButton.titleLabel?.font = UIFont.systemFont(ofSize: 22)
        backspaceButton.addTarget(self, action: #selector(backspacePressed), for: .touchUpInside)
        backspaceButton.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(displayLabel)
        containerView.addSubview(backspaceButton)

        NSLayoutConstraint.activate([
            displayLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            displayLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            backspaceButton.centerYAnchor.constraint(equalTo: displayLabel.centerYAnchor),
            backspaceButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24)
        ])
    }

    private func setupKeypad() {

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.distribution = .fillEqually
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        for row in keys {

            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 12
            rowStack.distribution = .fillEqually

            for key in row {

                let button = UIButton(type: .system)
                button.setTitle(key, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .bold)

                if #available(iOS 13.0, *) {
                    button.backgroundColor = UIColor.systemGray5
                } else {
                    button.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
                }

                button.layer.cornerRadius = 32
                button.clipsToBounds = true

                button.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 64),
                    button.heightAnchor.constraint(equalToConstant: 64)
                ])

                button.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)

                rowStack.addArrangedSubview(button)
            }

            mainStack.addArrangedSubview(rowStack)
        }
    }

    @objc private func keyPressed(_ sender: UIButton) {

        guard let digit = sender.titleLabel?.text else { return }

        inputText.append(digit)
        displayLabel.text = inputText
        //dtmfTone.play(digit: digit)
        delegate?.didPressDTMF(digit)
    }

    @objc private func backspacePressed() {

        if inputText.isEmpty {
            hide()
            delegate?.keypadDidClose()
            return
        }

        inputText.removeLast()
        displayLabel.text = inputText
    }

    func show(in parent: UIView) {

        frame = parent.bounds
        parent.addSubview(self)

        layoutIfNeeded()

        containerView.transform = CGAffineTransform(translationX: 0, y: 420)

        UIView.animate(withDuration: 0.3) {
            self.containerView.transform = .identity
        }
    }

    func hide() {

        UIView.animate(withDuration: 0.3, animations: {
            self.containerView.transform = CGAffineTransform(translationX: 0, y: 420)
        }) { _ in
            self.removeFromSuperview()
        }
    }
}
