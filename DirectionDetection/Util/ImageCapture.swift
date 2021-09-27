import AVFoundation
import UIKit

protocol ImageCaptureDelegate {
    func captureOutput(ciimage: CIImage)
}

class ImageCapture: NSObject {
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput",
                                                     qos: .userInitiated,
                                                     attributes: [],
                                                     autoreleaseFrequency: .workItem)
    private(set) var session = AVCaptureSession()
    // キャプチャー画像サイズ
    private(set) var videoWidth = 0
    private(set) var videoHeight = 0
    // キャプチャー画像の通知用デリゲート
    var delegate: ImageCaptureDelegate?
    
    override init() {
        super.init()
        
        setupAVCapture()
    }
    
    private func setupAVCapture() {
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                           mediaType: .video,
                                                           position: .back).devices.first
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice!) else { return }
        // capture セッション セットアップ
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        
        // 入力デバイス指定
        session.addInput(deviceInput)
        
        // 出力先の設定
        session.addOutput(videoDataOutput)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true
        
        // ビデオの画像サイズ取得
        try? videoDevice!.lockForConfiguration()
        let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
        videoWidth = Int(dimensions.width)
        videoHeight = Int(dimensions.height)
        videoDevice!.unlockForConfiguration()
        
        session.commitConfiguration()
    }
}

extension ImageCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciimage = CIImage(cvPixelBuffer: pb)
        delegate?.captureOutput(ciimage: ciimage)
    }
}
