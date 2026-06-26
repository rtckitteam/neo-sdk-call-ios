//
//  MultiLayerGradientView.swift
//  CiCareCall
//
//  Created by Mohammad Annas Al Hariri on 08/12/25.
//


import UIKit

class MultiLayerGradientView: UIView {
    
    private let layer1 = CAGradientLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        // Vertical Gradient (Top: Bright Red, Bottom: Dark Red)
        layer1.colors = [
            UIColor(hex: "#D30E0E")?.cgColor ?? UIColor.red.cgColor,
            UIColor(hex: "#260000")?.cgColor ?? UIColor.black.cgColor
        ]
        layer1.startPoint = CGPoint(x: 0.5, y: 0.0)
        layer1.endPoint   = CGPoint(x: 0.5, y: 1.0)
        self.layer.addSublayer(layer1)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer1.frame = self.bounds
    }
}
