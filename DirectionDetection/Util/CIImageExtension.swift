import UIKit
import CoreImage.CIFilterBuiltins

extension CIImage {
    func crop(frame: CGRect) -> CIImage? {
        guard let cropFilter = CIFilter(name: "CICrop") else { return nil }
        cropFilter.setValue(self, forKey: kCIInputImageKey)
        let vector = CIVector(cgRect: frame)
        cropFilter.setValue(vector, forKey: "inputRectangle")
        return cropFilter.outputImage
    }
    
    // 画像の中央だけ円状に残して黒く塗りつぶす
    func gaussianGradient(radius: Float) -> CIImage? {
        // 中央だけ白いフィルターを生成
        let radialMask = CIFilter.gaussianGradient()
        radialMask.center = .init(x: extent.origin.x + (extent.width / 2),
                                  y: extent.origin.y + (extent.height / 2))
        radialMask.radius = radius
        radialMask.color0 = CIColor(cgColor: UIColor.white.cgColor)
        radialMask.color1 = CIColor(cgColor: UIColor.black.cgColor)
        
        // 自身と上記のフィルタ生成画像を乗算
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = self
        multiply.backgroundImage = radialMask.outputImage
        
        return multiply.outputImage
    }
}
