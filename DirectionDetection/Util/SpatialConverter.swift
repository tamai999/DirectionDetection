import Accelerate
import UIKit
import CoreImage.CIFilterBuiltins

fileprivate struct Const {
    static let imageSize = 256 // 2のべき乗にすること
    static let imageDataSize = imageSize * imageSize
}

class SpatialConverter {
    private let ciContext = CIContext(options: [
        .cacheIntermediates : false
    ])
    private let countLog2n: vDSP_Length
    private let fftSetup: FFTSetup
    
    init() {
        // FFTのセットアップ
        countLog2n = vDSP_Length(log2(Float(Const.imageSize)))
        if let fftSetup = vDSP_create_fftsetup(countLog2n, FFTRadix(kFFTRadix2)) {
            self.fftSetup = fftSetup
        } else {
            fatalError()
        }
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    var imageSize: Int {
        return Const.imageSize
    }
    
    // 空間領域->周波数領域の振幅スペクトル
    func convert(cgimage: CGImage) -> Spectrum? {
        guard cgimage.width == Const.imageSize && cgimage.height == Const.imageSize,
              let pixelData = cgimage.dataProvider?.data else { return nil }
        
        // UInt8配列をFloat配列に変換
        let pixelUInt8 = (pixelData as Data).withUnsafeBytes({ (pointer: UnsafeRawBufferPointer) -> [UInt8] in
            let unsafeBufferPointer = pointer.bindMemory(to: UInt8.self)
            let unsafePointer = unsafeBufferPointer.baseAddress!
            return [UInt8](UnsafeBufferPointer(start: unsafePointer, count: Const.imageDataSize))
        })
        var pixelFloat = [Float](repeating: 0, count: Const.imageDataSize)
        vDSP.convertElements(of: pixelUInt8, to: &pixelFloat)
        
        // データサイズ定義
        let realDimension = Const.imageSize
        let complexValuesWidth = realDimension / 2
        let complexValuesHeight = realDimension
        let complexElementCount = complexValuesWidth * complexValuesHeight
        // 振幅スペクトルの格納場所
        var amplitudeSpectrum = [Float](repeating: 0, count: complexElementCount)
        var powerSpectrum: [Float] = []
        
        pixelFloat.withUnsafeBytes { imageDataPointer in
            _ = [Float](unsafeUninitializedCapacity: complexElementCount) { realBuffer, _ in
                _ = [Float](unsafeUninitializedCapacity: complexElementCount) { imagBuffer, _ in
                    // 画素値配列を複素数配列に変換
                    var splitComplex = DSPSplitComplex(
                        realp: realBuffer.baseAddress!,
                        imagp: imagBuffer.baseAddress!)
                    vDSP_ctoz([DSPComplex](imageDataPointer.bindMemory(to: DSPComplex.self)),
                              2,
                              &splitComplex,
                              1,
                              vDSP_Length(complexValuesWidth * complexValuesHeight))
                    // ２次元フーリエ変換
                    vDSP_fft2d_zrip(fftSetup,
                                    &splitComplex,
                                    1,
                                    0,
                                    countLog2n,
                                    countLog2n,
                                    FFTDirection(kFFTDirection_Forward))
                    // 複素数を振幅スペクトル（絶対値をとって振幅の大きさ）に変換
                    vDSP.absolute(splitComplex, result: &amplitudeSpectrum)
                    // 振幅スペクトルをパワースペクトル[dB]に変換
                    powerSpectrum = vDSP.amplitudeToDecibels(amplitudeSpectrum, zeroReference: 1)
                    // 上半分と下半分のデータを入れ替え
                    powerSpectrum.withUnsafeMutableBufferPointer { pointer in
                        let p1 = UnsafeMutablePointer(pointer.baseAddress!)
                        let p2 = p1.advanced(by: complexElementCount / 2)
                        vDSP_vswap(p1, 1,
                                   p2, 1,
                                   vDSP_Length(complexElementCount / 2))
                    }
                }
            }
        }
        
        return Spectrum(values: powerSpectrum, width: complexValuesWidth, height: complexValuesHeight)
    }
}

struct Spectrum {
    let values: [Float]
    let width: Int
    let height: Int
    
    // 振幅スペクトル(UInt8)をCGImageに変換する際のピクセルフォーマット
    static let grayPixelFormat = vImage_CGImageFormat(bitsPerComponent: 8,
                                                      bitsPerPixel: 8,
                                                      colorSpace: CGColorSpaceCreateDeviceGray(),
                                                      bitmapInfo: CGBitmapInfo(rawValue: 0))
    
    func cgImage() -> CGImage? {
        let pixelCount = width * height
        var uIntPixels = [UInt8](repeating: 0, count: pixelCount)
        
        // Float配列をUInt8配列に変換
        vDSP.convertElements(of: values,
                             to: &uIntPixels,
                             rounding: .towardZero)
        // 画素値からCGImageを作成
        let cgimage: CGImage? = uIntPixels.withUnsafeMutableBufferPointer { uIntPixelsPtr in
            let buffer = vImage_Buffer(data: uIntPixelsPtr.baseAddress!,
                                       height: vImagePixelCount(height),
                                       width: vImagePixelCount(width),
                                       rowBytes: width)
            
            if let format = Self.grayPixelFormat {
                return try? buffer.createCGImage(format: format)
            } else {
                return nil
            }
        }
        return cgimage
    }
    
    func reflect() -> Spectrum {
        // 反転するだけなのでとりあえずライブラリを使わないで実装しておく
        return Spectrum(values: values.reversed(),
                        width: width,
                        height: height)
    }
}

extension Spectrum {
    // 利用しない領域の値
    private static let angleNone = 999
    
    // 128x256で扇状の領域別に代表角度を格納したテーブル
    private static let fanShapedAngleTable: [Int] = {
        
        let width = Const.imageSize / 2
        let height = Const.imageSize
        let yCenter = Const.imageSize / 2
        
        var fanShapedPattern = [Int](repeating: angleNone, count: width * height)
        
        for y in 0 ..< height {
            for x in 0 ..< width {
                let xf = Float(x) + 0.01
                let yf = Float(yCenter-y)
                let distance = sqrtf(xf*xf + yf*yf)
                if distance > Float(width) {
                    continue
                }
                let angle = atanf(yf / xf) * 180.0 / Float.pi
                let roundedAngle = Int(angle.rounded())
                
                let centerAngle: Int
                // 10度間隔で0〜の番号（インデックス）を算出
                switch roundedAngle {
                case -90 ... -85:
                    centerAngle = 90
                case -84 ... 0:
                    centerAngle = Int(round(Float(roundedAngle) / 10.0 + 0.1)) * 10
                case 1 ... 85:
                    centerAngle = Int(round(Float(roundedAngle) / 10.0 - 0.1)) * 10
                case 86 ... 90:
                    centerAngle = 90
                default:
                    continue
                }
                fanShapedPattern[y * width + x] = centerAngle
            }
        }
        
        return fanShapedPattern
    }()
    
    // 強い周波数成分がある方向をdegreeで返す
    func direction() -> Int? {
        var angleQuantity: [Int: Int] = [:]
        
        // TODO: 周波数領域全体を計算せずに、低周波領域の計算だけで判定できそう
        values.enumerated().forEach { index, value in
            let angle = Self.fanShapedAngleTable[index]
            guard value.isFinite, angle != Self.angleNone else { return }
            
            // 100dB以下の信号はノイズとみなして捨てる
            guard value > 100 else { return }
            
            if let currentAngle = angleQuantity[angle] {
                angleQuantity[angle] = currentAngle + Int(value)
            } else {
                angleQuantity[angle] = Int(value)
            }
        }
        
        // TODO: 扇状の領域のテーブル上の偏りを補正
        
        let max = angleQuantity.max { $0.value < $1.value }
        
        // 最大値であっても小さければ方向成分がみつからなかったという判定
        if let maxValue = max?.value, maxValue < 800 {
            return nil
        }
        
        // TODO: 直交する角度に変換するのは利用側とする
        
        return max?.key
    }
}
