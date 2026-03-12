//
//  DTMFKeypadDelegate.swift
//  CicareSdkCall
//
//  Created by Mohammad Annas Al Hariri on 12/03/26.
//


import UIKit

protocol DTMFKeypadDelegate: AnyObject {
    func didPressDTMF(_ digit: String)
}

class DTMFKeypadView: UIView {

    weak var delegate: DTMFKeypadDelegate?

    private let keys: [[String]] = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        ["*","0","#"]
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeypad()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeypad()
    }

    private func setupKeypad() {

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.distribution = .fillEqually
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor)
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
                button.backgroundColor = UIColor.systemGray5
                button.layer.cornerRadius = 35
                button.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)

                rowStack.addArrangedSubview(button)
            }

            mainStack.addArrangedSubview(rowStack)
        }
    }

    @objc private func keyPressed(_ sender: UIButton) {
        guard let digit = sender.titleLabel?.text else { return }
        delegate?.didPressDTMF(digit)
    }
}