import UIKit
import AudioToolbox

class DTMFToneGenerator {

    private let systemSounds: [String: SystemSoundID] = [
        "0": 1200,
        "1": 1201,
        "2": 1202,
        "3": 1203,
        "4": 1204,
        "5": 1205,
        "6": 1206,
        "7": 1207,
        "8": 1208,
        "9": 1209,
        "*": 1210,
        "#": 1211
    ]

    func play(digit: String) {
        if let soundID = systemSounds[digit] {
            AudioServicesPlaySystemSound(soundID)
        }
    }
}

protocol DTMFKeypadDelegate: AnyObject {
    func didPressDTMF(_ digit: String)
    func keypadDidClose()
}

class DTMFKeypadView: UIView {

    weak var delegate: DTMFKeypadDelegate?

    private let toneGenerator = DTMFToneGenerator()

    private var inputText = "" {
        didSet {
            inputLabel.text = inputText
        }
    }

    private let containerView = UIView()
    private let inputLabel = UILabel()

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

        backgroundColor = .clear

        containerView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 26),
            containerView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -26),
            containerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 120),
            containerView.heightAnchor.constraint(equalToConstant: 280)
        ])

        setupKeypad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }
    
    @objc private func handleOverlayTap(_ gesture: UITapGestureRecognizer) {

        let location = gesture.location(in: self)

        if !containerView.frame.contains(location) {
            hide()
            delegate?.keypadDidClose()
        }
    }

    private func setupKeypad() {
        
        inputLabel.text = ""
        inputLabel.textColor = .white
        inputLabel.font = UIFont.systemFont(ofSize: 32, weight: .semibold)
        inputLabel.textAlignment = .center
        inputLabel.adjustsFontSizeToFitWidth = true
        inputLabel.minimumScaleFactor = 0.5
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(inputLabel)

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.distribution = .fillEqually
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            inputLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 5),
            inputLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            inputLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            inputLabel.heightAnchor.constraint(equalToConstant: 30),

            mainStack.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 8),
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10)
        ])

        for row in keys {

            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually

            for key in row {

                let button = UIButton(type: .system)
                button.setTitle(key, for: .normal)
                button.setTitleColor(.white, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .regular)

                button.backgroundColor = UIColor(white: 0.0, alpha: 0.2)

                button.layer.cornerRadius = 16
                button.clipsToBounds = true

                button.translatesAutoresizingMaskIntoConstraints = false

                button.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)

                rowStack.addArrangedSubview(button)
            }

            mainStack.addArrangedSubview(rowStack)
        }
    }

    @objc private func keyPressed(_ sender: UIButton) {
        guard let digit = sender.titleLabel?.text else { return }
        inputText.append(digit)
        toneGenerator.play(digit: digit)
        delegate?.didPressDTMF(digit)
    }

    func show(in parent: UIView) {
        
        inputText = ""

        frame = parent.bounds
        parent.addSubview(self)

        layoutIfNeeded()

        self.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
            self.containerView.transform = .identity
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            self.removeFromSuperview()
        }
    }
}

