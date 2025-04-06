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

    private let wideAngleButton = UIButton()
    private let telephotoButton = UIButton()

    private var isBackCameraActive = true  // Default to back camera

    private let focusIndicator = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        checkAvailableCameras()
        setupPreview()
        setupCaptureSession()
        setupCaptureButton()
        setupThumbnailButton()
        setupCameraToggleButtons()
        setupTapGestureForFocus()
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
        // Create a specific container for the black bars
        let topBlackView = UIView()
        topBlackView.translatesAutoresizingMaskIntoConstraints = false
        topBlackView.backgroundColor = .black
        view.addSubview(topBlackView)
        
        let bottomBlackView = UIView()
        bottomBlackView.translatesAutoresizingMaskIntoConstraints = false
        bottomBlackView.backgroundColor = .black
        view.addSubview(bottomBlackView)
        
        // Add the preview view
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // Create specific constraints to position everything
        let topBarHeight: CGFloat = UIScreen.main.bounds.height * 0.07  // 7% for top bar
        let bottomBarHeight: CGFloat = UIScreen.main.bounds.height * 0.2 // 20% for bottom bar
        
        NSLayoutConstraint.activate([
            // Top black bar
            topBlackView.topAnchor.constraint(equalTo: view.topAnchor),
            topBlackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBlackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBlackView.heightAnchor.constraint(equalToConstant: topBarHeight),
            
            // Bottom black bar
            bottomBlackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBlackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBlackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBlackView.heightAnchor.constraint(equalToConstant: bottomBarHeight),
            
            // Preview view - constrained between the black bars
            previewView.topAnchor.constraint(equalTo: topBlackView.bottomAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomBlackView.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Add the aspect ratio label to the top black bar
        addAspectRatioLabel(inView: topBlackView)
    }

    private func addAspectRatioLabel(inView containerView: UIView) {
        let label = UILabel()
        label.tag = 101
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "3:4"
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        containerView.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            label.widthAnchor.constraint(equalToConstant: 40),
            label.heightAnchor.constraint(equalToConstant: 22)
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

        // Create the preview layer with proper aspect ratio settings
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspect // Use aspect to maintain true 3:4 ratio
        previewView.layer.addSublayer(previewLayer!)
        previewView.backgroundColor = .black
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

    private func setupCameraToggleButtons() {
        // 1x Button (Wide Angle)
        wideAngleButton.translatesAutoresizingMaskIntoConstraints = false
        wideAngleButton.setTitle("1x", for: .normal)
        wideAngleButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        wideAngleButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        wideAngleButton.layer.cornerRadius = 25
        wideAngleButton.addTarget(self, action: #selector(switchToWideAngle), for: .touchUpInside)
        wideAngleButton.alpha = 1.0
        view.addSubview(wideAngleButton)
        
        // Telephoto Button (2x, 3x, or 5x depending on the device)
        telephotoButton.translatesAutoresizingMaskIntoConstraints = false
        telephotoButton.setTitle("\(Int(telephotoZoomFactor))x", for: .normal)
        telephotoButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        telephotoButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        telephotoButton.layer.cornerRadius = 25
        telephotoButton.addTarget(self, action: #selector(switchToTelephoto), for: .touchUpInside)
        telephotoButton.alpha = 0.4
        telephotoButton.isHidden = !hasTelephotoCamera // Hide if no telephoto available
        view.addSubview(telephotoButton)
        
        // Layout - Position above the shutter button
        NSLayoutConstraint.activate([
            wideAngleButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            wideAngleButton.trailingAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: -15),
            wideAngleButton.widthAnchor.constraint(equalToConstant: 50),
            wideAngleButton.heightAnchor.constraint(equalToConstant: 50),
            
            telephotoButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            telephotoButton.leadingAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: 15),
            telephotoButton.widthAnchor.constraint(equalToConstant: 50),
            telephotoButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func switchToWideAngle() {
        if !isUsingTelephoto { return } // Already using wide angle
        
        let switchSuccessful = switchToCamera(type: .builtInWideAngleCamera)
        if switchSuccessful {
            isUsingTelephoto = false
            isUsingUltraWide = false
            
            // Fix: Button appearance - 1x should be highlighted, telephoto dimmed
            wideAngleButton.alpha = 1.0
            telephotoButton.alpha = 0.4
            
            // Reset zoom
            if let device = videoDeviceInput?.device {
                try? device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
            }
            
            permanentZoomLabel.text = "1.0x"
        }
    }

    @objc private func switchToTelephoto() {
        if isUsingTelephoto || !hasTelephotoCamera { return } // Already using telephoto or not available
        
        let switchSuccessful = switchToCamera(type: .builtInTelephotoCamera)
        if switchSuccessful {
            isUsingTelephoto = true
            isUsingUltraWide = false
            
            // Fix: Button appearance - telephoto should be highlighted, 1x dimmed
            wideAngleButton.alpha = 0.4
            telephotoButton.alpha = 1.0
            
            // Reset zoom on telephoto
            if let device = videoDeviceInput?.device {
                try? device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
            }
            
            permanentZoomLabel.text = String(format: "%.1fx", telephotoZoomFactor)
        }
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
        permanentZoomLabel.textColor = .black
        permanentZoomLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        permanentZoomLabel.textAlignment = .center
        permanentZoomLabel.backgroundColor = UIColor.clear
        view.addSubview(permanentZoomLabel)

        NSLayoutConstraint.activate([
            // Move label to inside the capture button
            permanentZoomLabel.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            permanentZoomLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            permanentZoomLabel.widthAnchor.constraint(equalToConstant: 40),
            permanentZoomLabel.heightAnchor.constraint(equalToConstant: 20)
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
                }
            }
        } catch {
            print("Could not switch camera: \(error)")
        }
        
        session.commitConfiguration()
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

    private func setupTapGestureForFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        previewView.addGestureRecognizer(tapGesture)
        
        // Setup focus indicator view
        focusIndicator.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        focusIndicator.layer.borderColor = UIColor.yellow.cgColor
        focusIndicator.layer.borderWidth = 2
        focusIndicator.backgroundColor = UIColor.clear
        focusIndicator.isHidden = true
        view.addSubview(focusIndicator)
    }

    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        // Get tap location in the previewView
        let locationInPreviewView = gesture.location(in: previewView)
        
        guard let device = videoDeviceInput?.device,
              let previewLayer = previewLayer else { return }
        
        // Only proceed if the tap is within the actual visible camera feed
        if !previewLayer.frame.contains(locationInPreviewView) {
            print("Tap outside of camera feed area - ignoring")
            return
        }
        
        // Convert tap point to camera coordinates
        let pointInCamera = previewLayer.captureDevicePointConverted(fromLayerPoint: locationInPreviewView)
        
        // Ensure the converted point is valid
        if pointInCamera.x < 0 || pointInCamera.x > 1 || pointInCamera.y < 0 || pointInCamera.y > 1 {
            print("Converted point outside valid range: \(pointInCamera)")
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            // Set focus point
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = pointInCamera
                device.focusMode = .autoFocus
            }
            
            // Set exposure point
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = pointInCamera
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            
            // IMPORTANT: Convert preview view coordinates to main view coordinates
            // This is the key fix - the focus indicator is in the main view, not the preview view
            let locationInMainView = previewView.convert(locationInPreviewView, to: view)
            
            // Position indicator at the converted coordinates in the main view
            focusIndicator.center = locationInMainView
            focusIndicator.isHidden = false
            focusIndicator.alpha = 1
            focusIndicator.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            
            UIView.animate(withDuration: 0.3, animations: {
                self.focusIndicator.transform = CGAffineTransform.identity
            }) { _ in
                UIView.animate(withDuration: 0.5, delay: 0.5, options: [], animations: {
                    self.focusIndicator.alpha = 0
                }) { _ in
                    self.focusIndicator.isHidden = true
                }
            }
            
        } catch {
            print("Could not set focus point: \(error)")
        }
    }
}
