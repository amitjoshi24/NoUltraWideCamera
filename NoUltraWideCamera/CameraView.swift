import SwiftUI
import AVFoundation
import Photos

// SwiftUI wrapper
struct CameraView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        
    }

    // Lock orientation to portrait
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }

    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let previewView = UIView()
    private let captureButton = UIButton()
    private let thumbnailButton = UIButton()
    private let permanentZoomLabel = UILabel()
    private var isCapturing = false

    private var availableCameraTypes: [AVCaptureDevice.DeviceType] = []
    private var isUsingTelephoto = false
    private var isUsingUltraWide = false
    private var hasTelephotoCamera = false
    private var hasUltraWideCamera = false
    private var telephotoZoomFactor: CGFloat = 2.0 // Default, will be updated based on device

    private let zoomFactorLabel = UILabel()
    private var isBackCameraActive = true  // Default to back camera

    private var shouldSwitchToWide = false

    override func viewDidLoad() {
        super.viewDidLoad()
        checkAvailableCameras()
        setupPreview()
        setupCaptureSession()
        setupCaptureButton()
        setupThumbnailButton()
        setupGesture()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    private func setupPreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // Always start with wide-angle (1x) camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }

        videoDeviceInput = input
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        photoOutput = output
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        captureSession.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewView.layer.addSublayer(previewLayer!)
    }

    private func setupCaptureButton() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderColor = UIColor.gray.cgColor
        captureButton.layer.borderWidth = 5
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        view.addSubview(captureButton)
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }

    private func setupThumbnailButton() {
        thumbnailButton.translatesAutoresizingMaskIntoConstraints = false
        thumbnailButton.layer.cornerRadius = 6
        thumbnailButton.clipsToBounds = true
        thumbnailButton.layer.borderWidth = 1
        thumbnailButton.layer.borderColor = UIColor.white.cgColor
        thumbnailButton.addTarget(self, action: #selector(openCameraRoll), for: .touchUpInside)
        thumbnailButton.imageView?.contentMode = .scaleAspectFill
        view.addSubview(thumbnailButton)

        NSLayoutConstraint.activate([
            thumbnailButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            thumbnailButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            thumbnailButton.widthAnchor.constraint(equalToConstant: 50),
            thumbnailButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        updateThumbnailImage()
    }

    @objc private func openCameraRoll() {
        guard let url = URL(string: "photos-redirect://") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func setupGesture() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewView.addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoDeviceInput?.device else { return }
        
        if gesture.state == .began {
            // Show zoom label when pinch begins
            zoomFactorLabel.isHidden = false
            // Reset switch flag on new gesture
            shouldSwitchToWide = false
        }
        
        if gesture.state == .changed {
            do {
                // Calculate raw zoom level (before enforcing minimum)
                let rawTargetZoom = device.videoZoomFactor * gesture.scale
                
                // Check if we should switch back to wide BEFORE enforcing minimum
                if isUsingTelephoto && rawTargetZoom < 1.0 {
                    shouldSwitchToWide = true
                }
                
                // Now enforce minimum zoom
                var targetZoom = max(1.0, rawTargetZoom)
                
                // Debug info
                print("Current zoom: \(device.videoZoomFactor), Target zoom: \(targetZoom), Raw: \(rawTargetZoom)")
                
                // Switch to telephoto if needed
                if hasTelephotoCamera && !isUsingTelephoto && targetZoom >= telephotoZoomFactor {
                    // Log before switch attempt
                    print("Attempting to switch to telephoto")
                    
                    // Try to switch to telephoto camera
                    let switchSuccessful = switchToCamera(type: .builtInTelephotoCamera)
                    
                    // Only update state if switch was successful
                    if switchSuccessful {
                        isUsingTelephoto = true
                        isUsingUltraWide = false
                        print("Switch to telephoto successful")
                        
                        // Reset to 1.0x when switching to telephoto
                        if let device = videoDeviceInput?.device {
                            try? device.lockForConfiguration()
                            device.videoZoomFactor = 1.0
                            device.unlockForConfiguration()
                            
                            // Update the zoom display to show telephoto zoom factor
                            let zoomText = String(format: "%.1fx", telephotoZoomFactor)
                            permanentZoomLabel.text = zoomText
                            zoomFactorLabel.text = zoomText
                        }
                    } else {
                        // If switch failed, continue with digital zoom on current camera
                        print("Switch to telephoto failed, using digital zoom")
                        try device.lockForConfiguration()
                        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0) // Limit max digital zoom
                        let limitedZoom = min(targetZoom, maxZoom)
                        device.videoZoomFactor = limitedZoom
                        
                        let zoomText = String(format: "%.1fx", limitedZoom)
                        permanentZoomLabel.text = zoomText
                        zoomFactorLabel.text = zoomText
                        
                        device.unlockForConfiguration()
                    }
                }
                // Switch back to wide if flag is set
                else if isUsingTelephoto && shouldSwitchToWide {
                    print("Attempting to switch back to wide (flag triggered)")
                    
                    let switchSuccessful = switchToCamera(type: .builtInWideAngleCamera)
                    if switchSuccessful {
                        isUsingTelephoto = false
                        isUsingUltraWide = false
                        shouldSwitchToWide = false  // Reset flag
                        print("Switch to wide successful")
                        
                        // Set zoom to telephoto factor when switching back
                        if let device = videoDeviceInput?.device {
                            try? device.lockForConfiguration()
                            device.videoZoomFactor = telephotoZoomFactor
                            device.unlockForConfiguration()
                            
                            // Update zoom display
                            let zoomText = String(format: "%.1fx", telephotoZoomFactor)
                            permanentZoomLabel.text = zoomText
                            zoomFactorLabel.text = zoomText
                        }
                    }
                }
                else {
                    // Apply zoom to the current camera
                    try device.lockForConfiguration()
                    let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                    let limitedZoom = min(targetZoom, maxZoom)
                    device.videoZoomFactor = limitedZoom
                    
                    // Update zoom display
                    let displayZoom: CGFloat
                    if isUsingTelephoto {
                        displayZoom = limitedZoom * telephotoZoomFactor
                    } else if isUsingUltraWide {
                        displayZoom = limitedZoom * 0.5
                    } else {
                        displayZoom = limitedZoom
                    }
                    
                    let zoomText = String(format: "%.1fx", displayZoom)
                    zoomFactorLabel.text = zoomText
                    permanentZoomLabel.text = zoomText
                    
                    device.unlockForConfiguration()
                }
                
                // Reset scale for continuous pinching
                gesture.scale = 1.0
                
            } catch {
                print("Error during zoom: \(error)")
            }
        } else if gesture.state == .ended {
            // Reset flag when gesture ends
            shouldSwitchToWide = false
            
            // Hide temporary zoom label after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.zoomFactorLabel.isHidden = true
            }
        }
    }

    private func switchToCamera(type: AVCaptureDevice.DeviceType) -> Bool {
        guard let session = captureSession,
              let newDevice = AVCaptureDevice.default(type, for: .video, position: .back) else {
            print("Could not find camera device of type: \(type)")
            return false
        }
        
        var success = false
        
        session.beginConfiguration()
        
        // Remove existing camera input
        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
        }
        
        // Add new camera input
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoDeviceInput = newInput
                success = true
                
                // Update zoom level display
                let displayZoom: CGFloat
                switch type {
                case .builtInTelephotoCamera:
                    displayZoom = telephotoZoomFactor
                    isUsingTelephoto = true
                    isUsingUltraWide = false
                case .builtInUltraWideCamera:
                    displayZoom = 0.5
                    isUsingTelephoto = false
                    isUsingUltraWide = true
                default: // Wide angle
                    displayZoom = 1.0
                    isUsingTelephoto = false
                    isUsingUltraWide = false
                }
                
                // Update label with actual camera zoom factor
                DispatchQueue.main.async {
                    self.permanentZoomLabel.text = String(format: "%.1fx", displayZoom)
                    self.zoomFactorLabel.text = String(format: "%.1fx", displayZoom)
                }
            } else {
                print("Camera session could not add input for device type: \(type)")
                // If we failed to add the new input, try to restore the old one
                if let oldInput = videoDeviceInput {
                    if session.canAddInput(oldInput) {
                        session.addInput(oldInput)
                    }
                }
            }
        } catch {
            print("Error creating camera input: \(error)")
            // Try to restore the old input
            if let oldInput = videoDeviceInput {
                if session.canAddInput(oldInput) {
                    session.addInput(oldInput)
                }
            }
        }
        
        session.commitConfiguration()
        return success
    }

    @objc private func capturePhoto() {
        guard let output = photoOutput, !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
        triggerHaptic()
        performShutterEffect()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        
        guard error == nil else {
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }
        
        // Use the photo directly rather than converting to UIImage first
        // This preserves all the metadata
        if let data = photo.fileDataRepresentation() {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        // Create a request to add the photo to the library
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        // Add full photo data with metadata preserved
                        creationRequest.addResource(with: .photo, data: data, options: nil)
                    }, completionHandler: { success, error in
                        if let error = error {
                            print("Error saving photo with metadata: \(error.localizedDescription)")
                        } else {
                            DispatchQueue.main.async {
                                self.updateThumbnailImage()
                                
                                // Show success message
                                let successView = UIView(frame: CGRect(x: 0, y: 0, width: 150, height: 50))
                                successView.center = self.view.center
                                successView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                                successView.layer.cornerRadius = 10
                                
                                let label = UILabel(frame: successView.bounds)
                                label.text = "Photo Saved"
                                label.textColor = .white
                                label.textAlignment = .center
                                
                                successView.addSubview(label)
                                self.view.addSubview(successView)
                                
                                UIView.animate(withDuration: 0.5, delay: 1.0, options: [], animations: {
                                    successView.alpha = 0
                                }, completion: { _ in
                                    successView.removeFromSuperview()
                                })
                            }
                        }
                    })
                }
            }
        }
    }

    private func updateThumbnailImage() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = assets.firstObject else { return }

        let manager = PHImageManager.default()
        let size = CGSize(width: 50, height: 50)
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: nil) { image, _ in
            if let image = image {
                self.thumbnailButton.setImage(image, for: .normal)
            }
        }
    }

    private func performShutterEffect() {
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0.0
        view.addSubview(flashView)
        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                flashView.alpha = 0.0
            }) { _ in
                flashView.removeFromSuperview()
            }
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    private func stopSession() {
        captureSession?.stopRunning()
    }

    private func setupUI() {
        updateThumbnailImage()

        permanentZoomLabel.translatesAutoresizingMaskIntoConstraints = false
        permanentZoomLabel.text = "1.0x"
        permanentZoomLabel.textColor = .white
        permanentZoomLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        permanentZoomLabel.textAlignment = .center
        permanentZoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        permanentZoomLabel.layer.cornerRadius = 8
        permanentZoomLabel.clipsToBounds = true
        view.addSubview(permanentZoomLabel)

        NSLayoutConstraint.activate([
            permanentZoomLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            permanentZoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            permanentZoomLabel.widthAnchor.constraint(equalToConstant: 60),
            permanentZoomLabel.heightAnchor.constraint(equalToConstant: 25)
        ])

        // Setup temporary zoom factor label (appears only during zoom gesture)
        zoomFactorLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomFactorLabel.text = "1.0x"
        zoomFactorLabel.textColor = .white
        zoomFactorLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        zoomFactorLabel.textAlignment = .center
        zoomFactorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        zoomFactorLabel.layer.cornerRadius = 10
        zoomFactorLabel.clipsToBounds = true
        zoomFactorLabel.isHidden = true  // Hidden by default, only shows during zoom
        view.addSubview(zoomFactorLabel)

        NSLayoutConstraint.activate([
            zoomFactorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomFactorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            zoomFactorLabel.widthAnchor.constraint(equalToConstant: 80),
            zoomFactorLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func checkAvailableCameras() {
        // Check for ultra-wide camera
        if let _ = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            hasUltraWideCamera = true
            availableCameraTypes.append(.builtInUltraWideCamera)
        }
        
        // Check for wide-angle camera (all iPhones have this)
        if let _ = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            availableCameraTypes.append(.builtInWideAngleCamera)
        }
        
        // Check for telephoto camera
        if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            hasTelephotoCamera = true
            availableCameraTypes.append(.builtInTelephotoCamera)
            
            // Find telephoto zoom factor by querying the device directly
            do {
                try device.lockForConfiguration()
                
                // Determine if this is 2x, 3x or 5x telephoto by checking focal length
                let wideAngleDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                
                if let wideAngle = wideAngleDevice {
                    // Get focal lengths - no need for optional binding since these are non-optional Float values
                    let wideFocalLength = wideAngle.activeFormat.videoFieldOfView
                    let telePhotoFocalLength = device.activeFormat.videoFieldOfView
                    
                    // Calculate approximate zoom factor by comparing field of view
                    // (lower FOV = higher zoom)
                    let ratio = wideFocalLength / telePhotoFocalLength
                    
                    if ratio > 4.0 {
                        // Likely 5x zoom (iPhone 15 Pro Max or similar)
                        telephotoZoomFactor = 5.0
                    } else if ratio > 2.0 {
                        // Likely 3x zoom (iPhone 13/14/15 Pro)
                        telephotoZoomFactor = 3.0
                    } else {
                        // Default to 2x (older iPhones)
                        telephotoZoomFactor = 2.0
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Could not determine telephoto properties: \(error)")
                // Fall back to 2x
                telephotoZoomFactor = 2.0
            }
        }
        
        print("Available cameras: \(availableCameraTypes)")
        print("Telephoto zoom factor: \(telephotoZoomFactor)")
    }

    @objc private func flipCamera() {
        guard let currentInput = videoDeviceInput,
              let session = captureSession else { return }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        // Toggle between front and back
        isBackCameraActive.toggle()
        
        // When flipping, reset to default camera (wide-angle)
        isUsingTelephoto = false
        isUsingUltraWide = false
        
        let newPosition: AVCaptureDevice.Position = isBackCameraActive ? .back : .front
        let deviceType: AVCaptureDevice.DeviceType = isBackCameraActive ? .builtInWideAngleCamera : .builtInWideAngleCamera
        
        guard let newDevice = AVCaptureDevice.default(deviceType, for: .video, position: newPosition) else {
            session.commitConfiguration()
            return
        }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoDeviceInput = newInput
                
                // Reset zoom
                try newDevice.lockForConfiguration()
                newDevice.videoZoomFactor = 1.0
                newDevice.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.permanentZoomLabel.text = "1.0x"
                    self.zoomFactorLabel.text = "1.0x"
                }
            }
        } catch {
            print("Could not switch camera: \(error)")
        }
        
        session.commitConfiguration()
    }
}
