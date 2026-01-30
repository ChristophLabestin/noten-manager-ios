import SwiftUI
@preconcurrency import AVFoundation
import Combine

extension AVCaptureSession: @unchecked @retroactive Sendable {}
extension AVCaptureMetadataOutput: @unchecked @retroactive Sendable {}

@MainActor
class QRScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var errorMessage: String?
    @Published var permissionDenied = false
    @Published var isTorchOn = false
    
    // MainActor isolated (default)
    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    
    // Callback needs to be called on MainActor
    var onScan: ((String) -> Void)?
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.permissionDenied = true
                        self?.errorMessage = "Zugriff auf die Kamera verweigert."
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
            errorMessage = "Zugriff auf die Kamera verweigert."
        @unknown default:
            errorMessage = "Unbekannter Fehler."
        }
    }
    
    func setupCamera() {
        let session = session
        let output = output

        // Run configuration on a background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self, session, output] in
            guard let self = self else { return }
            
            guard let device = AVCaptureDevice.default(for: .video) else {
                Task { @MainActor in self.errorMessage = "Keine Kamera gefunden." }
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                session.beginConfiguration()
                
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    // Delegate callback on Main Queue - this is safe as self is expected to be on MainActor?
                    // Actually setMetadataObjectsDelegate expects delegate.
                    // self is MainActor isolated.
                    // But standard AVCapture delegate doesn't strictly enforce Sendable on delegate reference?
                    // We'll see.
                    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    if output.availableMetadataObjectTypes.contains(.qr) {
                        output.metadataObjectTypes = [.qr]
                    }
                }
                
                session.commitConfiguration()
                session.startRunning()
                
            } catch {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func stopSession() {
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                if isTorchOn {
                    device.torchMode = .off
                } else {
                    try device.setTorchModeOn(level: 1.0)
                }
                device.unlockForConfiguration()
                isTorchOn.toggle()
            } catch {
                print("Lichtfehler: \(error)")
            }
        }
    }
    
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            // Dispatch to MainActor to update UI state and stop session
            Task { @MainActor in
                self.stopSession()
                self.onScan?(stringValue)
            }
        }
    }
}

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (String) -> Void
    var onManualEntry: (() -> Void)? = nil
    
    @StateObject private var controller = QRScannerController()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let error = controller.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill.badge.ellipsis")
                            .font(.system(size: 50))
                            .foregroundStyle(.gray)
                        Text(error)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if controller.permissionDenied {
                            Button("Einstellungen öffnen") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    QRCameraPreview(session: controller.session)
                        .ignoresSafeArea()
                    
                    VStack {
                        Spacer()
                        
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.5), lineWidth: 4)
                            .frame(width: 250, height: 250)
                            .overlay(
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 100, weight: .thin))
                                    .foregroundStyle(.white.opacity(0.8))
                            )
                        
                        Spacer()
                        
                        HStack(spacing: 40) {
                            Button {
                                controller.toggleTorch()
                            } label: {
                                VStack {
                                    Image(systemName: controller.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                        .font(.title2)
                                    Text("Licht")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.white)
                            }
                            
                            if let onManualEntry = onManualEntry {
                                Button {
                                    onManualEntry()
                                } label: {
                                    VStack {
                                        Image(systemName: "keyboard")
                                            .font(.title2)
                                        Text("Manuell")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Code scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                controller.onScan = { code in
                    onScan(code)
                    dismiss()
                }
                controller.checkPermission()
            }
            .onDisappear {
                controller.stopSession()
            }
        }
    }
}

private struct QRCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
}

private class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
