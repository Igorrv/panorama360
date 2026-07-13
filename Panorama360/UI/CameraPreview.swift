import SwiftUI
import AVFoundation

/// Full-bleed `AVCaptureVideoPreviewLayer` host used as the capture background.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let orientation: UIInterfaceOrientation

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let conn = uiView.videoPreviewLayer.connection {
            if #available(iOS 17.0, *) {
                conn.videoRotationAngle = 90 // portrait
            } else {
                conn.videoOrientation = .portrait
            }
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
