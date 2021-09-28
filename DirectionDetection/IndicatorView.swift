import UIKit

fileprivate struct Const {
    static let width: CGFloat = 150
    static let height: CGFloat = 20
}

class IndicatorView: UIView {
    var position: CGPoint = .zero {
        didSet {
            transform = CGAffineTransform(rotationAngle: orientation / 180 * CGFloat(Float.pi))
                .concatenating(CGAffineTransform(translationX: position.x, y: position.y))
        }
    }
    
    var orientation: CGFloat = 0 {
        didSet {
            transform = CGAffineTransform(rotationAngle: orientation / 180 * CGFloat(Float.pi))
                .concatenating(CGAffineTransform(translationX: position.x, y: position.y))
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: -(Const.width / 2),
                                 y: -(Const.height / 2),
                                 width: Const.width,
                                 height: Const.height))
        backgroundColor = .red
        layer.cornerRadius = Const.height / 2
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
