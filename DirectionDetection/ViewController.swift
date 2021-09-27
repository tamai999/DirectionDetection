import UIKit
import Accelerate

class ViewController: UIViewController {
    
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var spectrumImageView: UIImageView!
    @IBOutlet weak var reflectSpectrumImageView: UIImageView!
    
    let ciContext = CIContext(options: [
            .cacheIntermediates : false
        ])
    
    // image capture
    lazy var imageCapture = ImageCapture()
    lazy var spatialConverter = SpatialConverter()
    
    private var imageSize = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // キャプチャ開始
        imageCapture.delegate = self
        imageCapture.session.startRunning()
        // 処理対象の画像サイズ取得
        imageSize = spatialConverter.imageSize
    }
}

extension ViewController: ImageCaptureDelegate {
    // 動画像を受け取る
    func captureOutput(ciimage: CIImage) {
        //
        // FFTにかける画像に前処理
        //
        
        // 右回転して向きを縦に直す
        let rotatedImage = ciimage.oriented(.right)
        // 画像中央を正方形に切り抜く
        guard let croppedImage = rotatedImage.crop(frame: CGRect(x: Int(rotatedImage.extent.size.height) / 2 - imageSize / 2,
                                                                 y: Int(rotatedImage.extent.size.width) / 2 - imageSize / 2,
                                                                 width: imageSize,
                                                                 height: imageSize)) else {
            return
        }
        // 振幅スペクトルに画像枠の縦横成分がのらないように画像の周囲を円状に暗くしておく
        guard let gradientImage = croppedImage.gaussianGradient(radius: 128) else { return }
        // カラー画像をグレースケール(8bit)に変換する
        guard let baseImage = ciContext.createCGImage(gradientImage,
                                                    from: gradientImage.extent,
                                                    format: .L8,
                                                    colorSpace: CGColorSpaceCreateDeviceGray()) else { return }
        //
        // 振幅スペクトル画像を取得
        //
        guard let spectrum = spatialConverter.convert(cgimage: baseImage),
              let spectrumImage = spectrum.cgImage() else { return }
        
        // （見た目だけのため）振幅スペクトルのxy鏡映画像を作成
        let reflectSpectrum = spectrum.reflect()
        guard let reflectSpectrumImage = reflectSpectrum.cgImage() else { return }
        
        // 画像を表示
        DispatchQueue.main.async {
            self.videoImageView.image = UIImage(cgImage: baseImage)
            self.spectrumImageView.image = UIImage(cgImage: spectrumImage)
            self.reflectSpectrumImageView.image = UIImage(cgImage: reflectSpectrumImage)
        }
    }
}
