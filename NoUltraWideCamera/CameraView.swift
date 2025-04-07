import SwiftUI
import AVFoundation
import Photos
import CoreLocation

// SwiftUI wrapper
struct CameraView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    private var settingsScrollView: UIScrollView?

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

    // Add a new button property
    private let twoXButton = UIButton()
    private var has2xOpticalQualityZoom = false

    // Add these properties to the class
    private let flashButton = UIButton()
    private var isFlashOn = false

    // Add these new properties to the class
    private let formatButton = UIButton()
    private var currentFormat: PhotoFormat = .heic
    private var exposureSlider = UISlider()
    private var exposureView = UIView()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    // Add these properties to the class
    private let advancedSettingsButton = UIButton()
    private let settingsPanel = UIView()
    private let formatLabel = UILabel()
    private var isSettingsPanelVisible = false

    // Add this enum for photo formats
    private enum PhotoFormat: String, CaseIterable {
        case heic = "HEIC"
        case jpeg = "JPEG"
        case png = "PNG"
        
        var fileExtension: String {
            switch self {
            case .heic: return "heic"
            case .jpeg: return "jpeg"
            case .png: return "png"
            }
        }
        
        var mimeType: String {
            switch self {
            case .heic: return "image/heic"
            case .jpeg: return "image/jpeg"
            case .png: return "image/png"
            }
        }
    }

    // Add this new property to the class
    private var currentEVLabel: UILabel?

    // Add this property
    private let formatIndicatorLabel = UILabel()

    // Add this property to track device orientation
    private var currentOrientation: UIDeviceOrientation = .portrait

    // Add these properties to track orientation state
    private var lastKnownOrientation: UIDeviceOrientation = .portrait
    private let rotationAnimationDuration: TimeInterval = 0.3

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add this line to suppress Metal framework warnings in simulator
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            print("Running in Simulator - some camera features disabled")
            return
        }
        
        checkAvailableCameras()
        setupPreview()
        setupCaptureSession()
        setupCaptureButton()
        setupThumbnailButton()
        setupCameraToggleButtons()
        setupTapGestureForFocus()
        setupTopControlButtons()
        setupAdvancedSettings()
        setupExposureControl()
        setupLocationServices()
        setupUI()
        
        // Lock orientation to portrait
        AppDelegate.orientationLock = .portrait
        
        // Initialize transforms based on current orientation
        lastKnownOrientation = UIDevice.current.orientation
        if lastKnownOrientation.isPortrait || lastKnownOrientation.isLandscape {
            rotateUIForCurrentOrientation()
        }
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
        // Remove any existing aspect ratio label to prevent duplicates
        if let existingLabel = containerView.viewWithTag(101) {
            existingLabel.removeFromSuperview()
        }
        
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
        
        // Apply current rotation if needed
        if currentOrientation.isLandscape {
            var rotationAngle: CGFloat = 0
            switch currentOrientation {
            case .landscapeLeft: rotationAngle = CGFloat.pi / 2
            case .landscapeRight: rotationAngle = -CGFloat.pi / 2
            default: break
            }
            label.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
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

        // Add device orientation monitoring
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        
        // Initialize current orientation
        currentOrientation = UIDevice.current.orientation
    }

    // Handle orientation changes
    @objc private func deviceOrientationChanged() {
        // Only respond to actual rotation changes
        let orientation = UIDevice.current.orientation
        if (orientation.isPortrait || orientation.isLandscape) && orientation != lastKnownOrientation {
            currentOrientation = orientation
            lastKnownOrientation = orientation
            
            // Rotate UI elements with animation
            rotateUIForCurrentOrientation()
        }
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
        wideAngleButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
        wideAngleButton.titleLabel?.adjustsFontForContentSizeCategory = true
        wideAngleButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        wideAngleButton.layer.cornerRadius = 25
        wideAngleButton.addTarget(self, action: #selector(switchToWideAngle), for: .touchUpInside)
        wideAngleButton.alpha = 1.0
        view.addSubview(wideAngleButton)
        
        // 2x Button (Optical-quality from main sensor)
        if has2xOpticalQualityZoom && telephotoZoomFactor > 2.0 {
            twoXButton.translatesAutoresizingMaskIntoConstraints = false
            twoXButton.setTitle("2x", for: .normal)
            twoXButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
            twoXButton.titleLabel?.adjustsFontForContentSizeCategory = true
            twoXButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            twoXButton.layer.cornerRadius = 25
            twoXButton.addTarget(self, action: #selector(switchToTwoX), for: .touchUpInside)
            twoXButton.alpha = 0.4
            view.addSubview(twoXButton)
        }
        
        // Telephoto Button (2x, 3x, or 5x depending on the device)
        telephotoButton.translatesAutoresizingMaskIntoConstraints = false
        telephotoButton.setTitle("\(Int(telephotoZoomFactor))x", for: .normal)
        telephotoButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
        telephotoButton.titleLabel?.adjustsFontForContentSizeCategory = true
        telephotoButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        telephotoButton.layer.cornerRadius = 25
        telephotoButton.addTarget(self, action: #selector(switchToTelephoto), for: .touchUpInside)
        telephotoButton.alpha = 0.4
        telephotoButton.isHidden = !hasTelephotoCamera // Hide if no telephoto available
        view.addSubview(telephotoButton)
        
        // Layout - Position the buttons in a row
        if has2xOpticalQualityZoom && telephotoZoomFactor > 2.0 {
            NSLayoutConstraint.activate([
                wideAngleButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
                wideAngleButton.trailingAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: -40),
                wideAngleButton.widthAnchor.constraint(equalToConstant: 50),
                wideAngleButton.heightAnchor.constraint(equalToConstant: 50),
                
                twoXButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
                twoXButton.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
                twoXButton.widthAnchor.constraint(equalToConstant: 50),
                twoXButton.heightAnchor.constraint(equalToConstant: 50),
                
                telephotoButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
                telephotoButton.leadingAnchor.constraint(equalTo: captureButton.centerXAnchor, constant: 40),
                telephotoButton.widthAnchor.constraint(equalToConstant: 50),
                telephotoButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        } else {
            // Keep existing layout for devices without 2x button
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
    }

    @objc private func switchToWideAngle() {
        if !isUsingTelephoto && videoDeviceInput?.device.videoZoomFactor == 1.0 {
            return // Already at 1x on wide angle
        }
        
        if isUsingTelephoto {
            // Switch to wide angle camera
            let switchSuccessful = switchToCamera(type: .builtInWideAngleCamera)
            if !switchSuccessful { return }
        }
        
        // Ensure zoom is set to 1.0x
        if let device = videoDeviceInput?.device {
            try? device.lockForConfiguration()
            device.videoZoomFactor = 1.0
            device.unlockForConfiguration()
        }
        
        // Update UI
        isUsingTelephoto = false
        isUsingUltraWide = false
        wideAngleButton.alpha = 1.0
        if has2xOpticalQualityZoom {
            twoXButton.alpha = 0.4
        }
        telephotoButton.alpha = 0.4
        permanentZoomLabel.text = "1.0x"
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

    @objc private func switchToTwoX() {
        // First ensure we're using the wide angle camera
        if isUsingTelephoto {
            switchToCamera(type: .builtInWideAngleCamera)
        }
        
        // Apply 2x zoom on the wide angle camera
        if let device = videoDeviceInput?.device {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 2.0
                device.unlockForConfiguration()
                
                // Update UI
                permanentZoomLabel.text = "2.0x"
                wideAngleButton.alpha = 0.4
                twoXButton.alpha = 1.0
                telephotoButton.alpha = 0.4
                
                isUsingTelephoto = false
                isUsingUltraWide = false
            } catch {
                print("Could not set 2x zoom: \(error)")
            }
        }
    }

    @objc private func capturePhoto() {
        guard let output = photoOutput, !isCapturing else { return }
        isCapturing = true
        
        do {
            // Configure photo settings based on selected format
            let settings: AVCapturePhotoSettings
            
            switch currentFormat {
            case .heic:
                if let availableFormats = output.availablePhotoCodecTypes as? [AVVideoCodecType],
                   availableFormats.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    // Fall back to JPEG if HEIC not available
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                }
                
            case .jpeg:
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                
            case .png:
                // For PNG, we'll capture in JPEG format and convert after
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            // Add location metadata if available
            var metadata = settings.metadata ?? [:]
            
            // CRITICAL FIX: Set orientation directly in the top-level metadata
            // This is more reliable than putting it in the EXIF dictionary
            let exifOrientation = getImageOrientationFromDeviceOrientation()
            metadata[kCGImagePropertyOrientation as String] = exifOrientation.rawValue
            
            // Also add it to the EXIF dictionary for compatibility
            var exifDictionary = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            exifDictionary[kCGImagePropertyOrientation as String] = exifOrientation.rawValue
            metadata[kCGImagePropertyExifDictionary as String] = exifDictionary
            
            // Add location metadata if available
            if let location = currentLocation {
                // Create GPS metadata dictionary
                let gpsDictionary = [
                    kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
                    kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
                    kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
                    kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
                    kCGImagePropertyGPSAltitude as String: location.altitude,
                    kCGImagePropertyGPSTimeStamp as String: Date(),
                    kCGImagePropertyGPSSpeed as String: location.speed,
                    kCGImagePropertyGPSSpeedRef as String: "K", // Kilometers per hour
                    kCGImagePropertyGPSDateStamp as String: Date()
                ] as [String : Any]
                
                // Add GPS dictionary to the metadata
                metadata[kCGImagePropertyGPSDictionary as String] = gpsDictionary
            }
            
            // Set the updated metadata
            settings.metadata = metadata
            
            // Set flash mode based on user selection
            if isFlashOn {
                settings.flashMode = .on
            } else {
                settings.flashMode = .off
            }
            
            // Take the photo with our settings
            output.capturePhoto(with: settings, delegate: self)
            triggerHaptic()
            performShutterEffect()
        } catch {
            print("Error during photo capture: \(error.localizedDescription)")
            isCapturing = false
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        
        guard error == nil else {
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }
        
        var imageData = photo.fileDataRepresentation()
        
        // IMPORTANT: For PNG conversion, we need to preserve the orientation
        if currentFormat == .png, let jpegData = imageData {
            let ciImage = CIImage(data: jpegData)
            let context = CIContext()
            
            if let ciImage = ciImage, let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                // Create a UIImage with correct orientation
                
                // Get the metadata - photo.metadata is not optional
                let metadata = photo.metadata
                
                // Get orientation from metadata if available
                if let orientationNumber = metadata[kCGImagePropertyOrientation as String] as? NSNumber,
                   let orientation = CGImagePropertyOrientation(rawValue: orientationNumber.uint32Value) {
                    
                    // Convert CGImagePropertyOrientation to UIImage.Orientation
                    let uiOrientation = convertToUIImageOrientation(from: orientation)
                    
                    // Create a new UIImage with the correct orientation
                    let orientedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
                    
                    // Convert to PNG
                    imageData = orientedImage.pngData()
                } else {
                    // Fallback if orientation metadata is missing
                    let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                    imageData = uiImage.pngData()
                }
            }
        }
        
        // Save the image to the photo library
        if let data = imageData {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo, data: data, options: nil)
                    }, completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success {
                                self.updateThumbnailImage()
                            } else if let error = error {
                                print("Error saving photo: \(error.localizedDescription)")
                            }
                        }
                    })
                }
            }
        }
    }

    // Helper method to convert CGImagePropertyOrientation to UIImage.Orientation
    private func convertToUIImageOrientation(from cgOrientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch cgOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }

    private func updateThumbnailImage() {
        // Fetch the most recent photo from the photo library with proper error handling
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self, status == .authorized else { return }
            
            DispatchQueue.main.async {
                let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                
                guard let asset = fetchResult.firstObject else {
                    // No photos available - use a placeholder
                    let placeholderImage = UIImage(systemName: "photo")
                    self.thumbnailButton.setImage(placeholderImage, for: .normal)
                    self.thumbnailButton.tintColor = .white
                    return
                }
                
                // Use a smaller image size to avoid performance issues
                let manager = PHImageManager.default()
                let targetSize = CGSize(width: 100, height: 100) // 2x larger than display size for retina
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = false // Don't try to download from iCloud
                options.isSynchronous = false
                
                manager.requestImage(for: asset,
                                     targetSize: targetSize,
                                     contentMode: .aspectFill,
                                     options: options) { [weak self] image, info in
                    guard let image = image, let self = self else { return }
                    
                    DispatchQueue.main.async {
                        self.thumbnailButton.setImage(image, for: .normal)
                    }
                }
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
        // Add a black background behind the zoom controls
        let zoomControlsBackground = UIView()
        zoomControlsBackground.translatesAutoresizingMaskIntoConstraints = false
        zoomControlsBackground.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        zoomControlsBackground.layer.cornerRadius = 20
        view.insertSubview(zoomControlsBackground, belowSubview: wideAngleButton)
        
        // Update the permanent zoom label - ensure it appears in the shutter button
        permanentZoomLabel.translatesAutoresizingMaskIntoConstraints = false
        permanentZoomLabel.text = "1.0×"
        permanentZoomLabel.textColor = .black // This ensures visibility against white shutter button
        permanentZoomLabel.font = scaledDynamicFont(forTextStyle: .callout) // More visible size
        permanentZoomLabel.adjustsFontForContentSizeCategory = true
        permanentZoomLabel.textAlignment = .center
        permanentZoomLabel.backgroundColor = .clear
        view.addSubview(permanentZoomLabel)
        
        // Make sure we only add the aspect ratio label once
        if view.viewWithTag(101) == nil {
            addAspectRatioLabel(inView: view)
        }
        
        // Layout constraints - update zoom label to be properly centered on shutter button
        NSLayoutConstraint.activate([
            // Position zoom label directly on top of the shutter button
            permanentZoomLabel.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            permanentZoomLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
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
        
        // Add detection for 2x optical-quality zoom capability
        // iPhone 14 Pro/Pro Max and 15 Pro/Pro Max have this capability with their 48MP sensors
        let device = UIDevice.current
        let modelName = device.model
        let systemVersion = Float(UIDevice.current.systemVersion) ?? 0
        
        // Simple detection based on model identifier and system version
        if modelName.contains("iPhone") && systemVersion >= 16.0 {
            // Check if this is likely a Pro model with 48MP sensor (14 Pro or newer)
            if ProcessInfo.processInfo.physicalMemory > 6 * 1024 * 1024 * 1024 { // > 6GB RAM
                // Likely a Pro model with 48MP camera
                has2xOpticalQualityZoom = true
                print("Device likely has 2x optical-quality zoom capability")
            }
        }
        
        print("Available cameras: \(availableCameraTypes)")
        print("Telephoto zoom factor: \(telephotoZoomFactor)")
        print("Has 2x optical-quality zoom: \(has2xOpticalQualityZoom)")
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
        tapGesture.delaysTouchesBegan = false
        tapGesture.delaysTouchesEnded = false
        tapGesture.cancelsTouchesInView = false // Very important to prevent gesture gate timeouts
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
            
            // First reset any previous exposure compensation
            device.setExposureTargetBias(0.0)
            // Update EV label with current value
            currentEVLabel?.text = String(format: "EV: %.1f", 0.0)
            
            // Set focus and exposure point
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = pointInCamera
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = pointInCamera
                
                // Use continuous auto exposure to allow the camera to adjust
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // Reset the exposure compensation slider to zero
                self.exposureSlider.setValue(0.0, animated: true)
            }
            
            device.unlockForConfiguration()
            
            // Show and animate focus indicator
            let locationInMainView = previewView.convert(locationInPreviewView, to: view)
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

    // Update setupTopControlButtons to only include flash
    private func setupTopControlButtons() {
        // Create a container view for the flash button only
        let buttonContainer = UIView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        buttonContainer.layer.cornerRadius = 20
        view.addSubview(buttonContainer)
        
        // Flash button
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = .clear
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        buttonContainer.addSubview(flashButton)
        
        // Position just the flash button in the container
        NSLayoutConstraint.activate([
            // Container constraints - narrower for just one button
            buttonContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 40),
            buttonContainer.widthAnchor.constraint(equalToConstant: 50), // Width for one button
            
            // Flash button - centered in container
            flashButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            flashButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            flashButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: 40)
        ])
    }

    // Flash toggle method
    @objc private func toggleFlash() {
        isFlashOn.toggle()
        
        if isFlashOn {
            // Flash ON - yellow icon
            flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
            flashButton.tintColor = .yellow
        } else {
            // Flash OFF - white icon with slash
            flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
            flashButton.tintColor = .white
        }
        
        // Give haptic feedback when toggling
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func setupAdvancedSettings() {
        // Setup the advanced settings button (gear icon)
        advancedSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        advancedSettingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        advancedSettingsButton.tintColor = .white
        advancedSettingsButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        advancedSettingsButton.layer.cornerRadius = 20
        advancedSettingsButton.addTarget(self, action: #selector(toggleSettingsPanel), for: .touchUpInside)
        view.addSubview(advancedSettingsButton)
        
        // Settings panel with scroll view for dynamic content
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        settingsPanel.layer.cornerRadius = 15
        settingsPanel.alpha = 0
        settingsPanel.isHidden = true
        view.addSubview(settingsPanel)
        
        // Add a scroll view inside the settings panel
        let settingsScrollView = UIScrollView()
        settingsScrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.showsVerticalScrollIndicator = true
        settingsScrollView.indicatorStyle = .white
        settingsScrollView.alwaysBounceVertical = true
        settingsPanel.addSubview(settingsScrollView)
        
        // Create a content view for the scroll view
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.addSubview(contentView)
        
        // Format section title with dynamic type
        let formatSectionLabel = UILabel()
        formatSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        formatSectionLabel.text = "File Format"
        formatSectionLabel.textColor = .white
        formatSectionLabel.font = scaledDynamicFont(forTextStyle: .headline)
        formatSectionLabel.adjustsFontForContentSizeCategory = true
        contentView.addSubview(formatSectionLabel)
        
        // Format switch button with dynamic type
        formatButton.translatesAutoresizingMaskIntoConstraints = false
        formatButton.setTitle(currentFormat.rawValue, for: .normal)
        formatButton.setTitleColor(.white, for: .normal)
        formatButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
        formatButton.titleLabel?.adjustsFontForContentSizeCategory = true
        formatButton.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        formatButton.layer.cornerRadius = 8
        formatButton.addTarget(self, action: #selector(toggleFormat), for: .touchUpInside)
        contentView.addSubview(formatButton)

        // Update the hint label to use a proper arrow symbol and support wrapping
        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "← Click to change"  // Unicode left arrow instead of text arrow
        hintLabel.textColor = .lightGray
        hintLabel.font = scaledDynamicFont(forTextStyle: .caption1)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.numberOfLines = 0  // Allow multiple lines
        hintLabel.lineBreakMode = .byWordWrapping  // Wrap by word
        contentView.addSubview(hintLabel)
        
        // Format description with dynamic type
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        formatLabel.text = getFormatDescription(format: currentFormat)
        formatLabel.textColor = .lightGray
        formatLabel.font = scaledDynamicFont(forTextStyle: .caption1)
        formatLabel.adjustsFontForContentSizeCategory = true
        formatLabel.numberOfLines = 0 // Allow multiple lines
        contentView.addSubview(formatLabel)
        
        // Close button
        let closeButton = UIButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(hideSettingsPanel), for: .touchUpInside)
        settingsPanel.addSubview(closeButton) // Add directly to panel, not scrollview
        
        // Format indicator with dynamic type
        formatIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        formatIndicatorLabel.text = currentFormat.rawValue
        formatIndicatorLabel.textColor = .white
        formatIndicatorLabel.font = scaledDynamicFont(forTextStyle: .caption1)
        formatIndicatorLabel.adjustsFontForContentSizeCategory = true
        formatIndicatorLabel.textAlignment = .center
        formatIndicatorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        formatIndicatorLabel.layer.cornerRadius = 8
        formatIndicatorLabel.clipsToBounds = true
        view.addSubview(formatIndicatorLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Advanced settings button - align with capture button
            advancedSettingsButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            advancedSettingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            advancedSettingsButton.widthAnchor.constraint(equalToConstant: 40),
            advancedSettingsButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Settings panel
            settingsPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            settingsPanel.widthAnchor.constraint(equalToConstant: 220), // Slightly wider
            settingsPanel.heightAnchor.constraint(equalToConstant: 180), // Slightly taller
            
            // Scroll view fills the panel (except for close button space)
            settingsScrollView.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 40),
            settingsScrollView.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 10),
            settingsScrollView.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -10),
            settingsScrollView.bottomAnchor.constraint(equalTo: settingsPanel.bottomAnchor, constant: -10),
            
            // Content view for scrolling - equal width to scroll view but dynamic height
            contentView.topAnchor.constraint(equalTo: settingsScrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: settingsScrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: settingsScrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: settingsScrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: settingsScrollView.widthAnchor),
            
            // Format section
            formatSectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            formatSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            formatSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Format button
            formatButton.topAnchor.constraint(equalTo: formatSectionLabel.bottomAnchor, constant: 10),
            formatButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            formatButton.widthAnchor.constraint(equalToConstant: 70),
            formatButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Hint label - positioned to the right of the format button
            hintLabel.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: formatButton.trailingAnchor, constant: 8),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Format description - dynamic height
            formatLabel.topAnchor.constraint(equalTo: formatButton.bottomAnchor, constant: 10),
            formatLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            formatLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            formatLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            
            // Close button - stays at top right corner
            closeButton.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Format indicator
            formatIndicatorLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            formatIndicatorLabel.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 5),
            formatIndicatorLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),
            formatIndicatorLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @objc private func showSettingsPanel() {
        // Make the panel visible
        settingsPanel.isHidden = false
        
        // Apply rotation based on current device orientation
        var rotationAngle: CGFloat = 0
        switch currentOrientation {
        case .portrait: rotationAngle = 0
        case .portraitUpsideDown: rotationAngle = CGFloat.pi
        case .landscapeLeft: rotationAngle = CGFloat.pi / 2
        case .landscapeRight: rotationAngle = -CGFloat.pi / 2
        default: rotationAngle = 0
        }
        
        // Apply rotation
        settingsPanel.transform = CGAffineTransform(rotationAngle: rotationAngle)
        
        // Animate fade in
        UIView.animate(withDuration: 0.3, animations: {
            self.settingsPanel.alpha = 1.0
        }, completion: { _ in
            // Flash scroll indicators to make them immediately visible
            if let scrollView = self.settingsPanel.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.flashScrollIndicators()
            }
        })
        
        isSettingsPanelVisible = true
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    @objc private func hideSettingsPanel() {
        UIView.animate(withDuration: 0.3, animations: {
            self.settingsPanel.alpha = 0
        }, completion: { _ in
            self.settingsPanel.isHidden = true
        })
        
        isSettingsPanelVisible = false
    }

    @objc private func toggleSettingsPanel() {
        if isSettingsPanelVisible {
            hideSettingsPanel()
        } else {
            showSettingsPanel()
        }
    }

    @objc private func toggleFormat() {
        let formats = PhotoFormat.allCases
        if let currentIndex = formats.firstIndex(of: currentFormat) {
            let nextIndex = (currentIndex + 1) % formats.count
            currentFormat = formats[nextIndex]
            
            // Update format display in both places
            formatButton.setTitle(currentFormat.rawValue, for: .normal)
            formatIndicatorLabel.text = currentFormat.rawValue
            formatLabel.text = getFormatDescription(format: currentFormat)
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    private func getFormatDescription(format: PhotoFormat) -> String {
        switch format {
        case .heic:
            return "Smaller file size, better quality, iOS/macOS only"
        case .jpeg:
            return "Standard format compatible with all devices"
        case .png:
            return "Lossless format, best quality but larger files"
        }
    }

    private func setupExposureControl() {
        // Container view in the top black area
        exposureView = UIView()
        exposureView.translatesAutoresizingMaskIntoConstraints = false
        exposureView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        exposureView.layer.cornerRadius = 15
        exposureView.alpha = 1.0 // Always visible
        view.addSubview(exposureView)
        
        // Create label to display current EV value with dynamic type support
        let currentEVLabel = UILabel()
        currentEVLabel.translatesAutoresizingMaskIntoConstraints = false
        currentEVLabel.textColor = .white
        currentEVLabel.font = scaledDynamicFont(forTextStyle: .footnote) // Dynamic type support
        currentEVLabel.adjustsFontForContentSizeCategory = true // Adjust with system settings
        currentEVLabel.textAlignment = .center
        currentEVLabel.text = "EV: 0.0"
        view.addSubview(currentEVLabel)
        
        // Slider - will get min/max values dynamically
        exposureSlider = UISlider()
        exposureSlider.translatesAutoresizingMaskIntoConstraints = false
        
        // Dynamically determine the exposure range from the camera device
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if let device = device {
            // Get actual range from device capabilities
            let minExposure = device.minExposureTargetBias
            let maxExposure = device.maxExposureTargetBias
            
            exposureSlider.minimumValue = minExposure
            exposureSlider.maximumValue = maxExposure
        } else {
            // Fallback values based on common iPhone range (most models support approximately -6 to +6)
            exposureSlider.minimumValue = -8.0
            exposureSlider.maximumValue = 8.0
        }
        
        // Store reference to the label for updating from slider events
        self.currentEVLabel = currentEVLabel
        
        exposureSlider.value = 0.0  // Start at neutral exposure
        exposureSlider.minimumTrackTintColor = UIColor.yellow
        exposureSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.5)
        exposureSlider.thumbTintColor = UIColor.white
        exposureSlider.addTarget(self, action: #selector(exposureValueChanged(_:)), for: .valueChanged)
        exposureView.addSubview(exposureSlider)
        
        // Icons for min/max exposure
        let sunMinImage = UIImageView(image: UIImage(systemName: "sun.min"))
        let sunMaxImage = UIImageView(image: UIImage(systemName: "sun.max"))
        sunMinImage.translatesAutoresizingMaskIntoConstraints = false
        sunMaxImage.translatesAutoresizingMaskIntoConstraints = false
        sunMinImage.tintColor = .white
        sunMaxImage.tintColor = .white
        sunMinImage.contentMode = .scaleAspectFit
        sunMaxImage.contentMode = .scaleAspectFit
        exposureView.addSubview(sunMinImage)
        exposureView.addSubview(sunMaxImage)
        
        // Add value labels to show the actual range - will update with actual range
        let minValueLabel = UILabel()
        let maxValueLabel = UILabel()
        
        if let device = device {
            minValueLabel.text = String(format: "%.0f", device.minExposureTargetBias)
            maxValueLabel.text = String(format: "+%.0f", device.maxExposureTargetBias)
        } else {
            minValueLabel.text = "-8"
            maxValueLabel.text = "+8"
        }
        
        // Update EV min/max labels
        minValueLabel.textColor = .white
        minValueLabel.font = scaledDynamicFont(forTextStyle: .caption1)
        minValueLabel.adjustsFontForContentSizeCategory = true
        minValueLabel.translatesAutoresizingMaskIntoConstraints = false
        minValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        minValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        maxValueLabel.textColor = .white
        maxValueLabel.font = scaledDynamicFont(forTextStyle: .caption1)
        maxValueLabel.adjustsFontForContentSizeCategory = true
        maxValueLabel.translatesAutoresizingMaskIntoConstraints = false
        maxValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        maxValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Update current EV label without width constraints
        currentEVLabel.textColor = .white
        currentEVLabel.font = scaledDynamicFont(forTextStyle: .footnote)
        currentEVLabel.textAlignment = .center
        currentEVLabel.adjustsFontForContentSizeCategory = true
        currentEVLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        exposureView.addSubview(minValueLabel)
        exposureView.addSubview(maxValueLabel)
        
        // Store references to these labels for rotation
        minValueLabel.tag = 201 // Tag for identification
        maxValueLabel.tag = 202
        
        // Update constraints for the EV label to allow dynamic width;
        // Here we add a maximum width constraint (e.g., 100 points) so the label won't overflow
        NSLayoutConstraint.activate([
            exposureView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            exposureView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exposureView.widthAnchor.constraint(equalToConstant: 280),
            exposureView.heightAnchor.constraint(equalToConstant: 40),
            
            sunMinImage.leadingAnchor.constraint(equalTo: exposureView.leadingAnchor, constant: 10),
            sunMinImage.centerYAnchor.constraint(equalTo: exposureView.centerYAnchor),
            sunMinImage.widthAnchor.constraint(equalToConstant: 20),
            sunMinImage.heightAnchor.constraint(equalToConstant: 20),
            
            exposureSlider.leadingAnchor.constraint(equalTo: sunMinImage.trailingAnchor, constant: 5),
            exposureSlider.trailingAnchor.constraint(equalTo: sunMaxImage.leadingAnchor, constant: -5),
            exposureSlider.centerYAnchor.constraint(equalTo: exposureView.centerYAnchor),
            
            sunMaxImage.trailingAnchor.constraint(equalTo: exposureView.trailingAnchor, constant: -10),
            sunMaxImage.centerYAnchor.constraint(equalTo: exposureView.centerYAnchor),
            sunMaxImage.widthAnchor.constraint(equalToConstant: 20),
            sunMaxImage.heightAnchor.constraint(equalToConstant: 20),
            
            minValueLabel.centerXAnchor.constraint(equalTo: sunMinImage.centerXAnchor),
            minValueLabel.topAnchor.constraint(equalTo: sunMinImage.bottomAnchor, constant: 2),
            
            maxValueLabel.centerXAnchor.constraint(equalTo: sunMaxImage.centerXAnchor),
            maxValueLabel.topAnchor.constraint(equalTo: sunMaxImage.bottomAnchor, constant: 2),
            
            // Position the EV label under the exposure slider, but WITHOUT fixed width—and with a cap
            currentEVLabel.topAnchor.constraint(equalTo: exposureView.bottomAnchor, constant: 5),
            currentEVLabel.centerXAnchor.constraint(equalTo: exposureView.centerXAnchor),
            currentEVLabel.heightAnchor.constraint(equalToConstant: 20),
            currentEVLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 100)
        ])
    }

    @objc private func exposureValueChanged(_ slider: UISlider) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Use continuous auto exposure mode to keep adjusting to the scene
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Apply the exposure bias
            let bias = slider.value
            device.setExposureTargetBias(bias)
            
            // Update EV label with current value
            currentEVLabel?.text = String(format: "EV: %.1f", bias)
            
            device.unlockForConfiguration()
        } catch {
            print("Could not adjust exposure: \(error)")
        }
    }

    private func setupLocationServices() {
        // Configure location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        // Start updating location if authorized
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
        }
    }

    // Helper method to convert device orientation to image orientation
    private func getImageOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        // The mapping is not straightforward because the front/back camera are oriented differently
        let isUsingFrontCamera = videoDeviceInput?.device.position == .front
        
        switch currentOrientation {
        case .portrait:
            return isUsingFrontCamera ? .leftMirrored : .right
        case .portraitUpsideDown:
            return isUsingFrontCamera ? .rightMirrored : .left
        case .landscapeLeft:
            return isUsingFrontCamera ? .downMirrored : .up
        case .landscapeRight:
            return isUsingFrontCamera ? .upMirrored : .down
        default:
            return isUsingFrontCamera ? .leftMirrored : .right // Default to portrait
        }
    }

    // Update the rotation method to include EV min/max labels only
    private func rotateUIForCurrentOrientation() {
        // Calculate rotation angle based on orientation
        var rotationAngle: CGFloat = 0
        
        switch currentOrientation {
        case .portrait:
            rotationAngle = 0
        case .portraitUpsideDown:
            rotationAngle = CGFloat.pi
        case .landscapeLeft:
            rotationAngle = CGFloat.pi / 2
        case .landscapeRight:
            rotationAngle = -CGFloat.pi / 2
        default:
            return // Ignore face up/down orientations
        }
        
        // Animate rotation of UI elements
        UIView.animate(withDuration: rotationAnimationDuration) {
            // Camera toggle buttons (1x, 2x)
            self.wideAngleButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.telephotoButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            if self.has2xOpticalQualityZoom {
                self.twoXButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            }
            
            // Thumbnail button
            self.thumbnailButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
            // Format indicator
            self.formatIndicatorLabel.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
            // Zoom label in shutter
            self.permanentZoomLabel.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
            // Flash icon
            self.flashButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
            // Settings gear
            self.advancedSettingsButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
            
            // Aspect ratio label - hide in landscape
            if let aspectRatioLabel = self.view.viewWithTag(101) as? UILabel {
                aspectRatioLabel.transform = CGAffineTransform(rotationAngle: rotationAngle)
                // Always show the aspect ratio label so we can see the rotation
                aspectRatioLabel.isHidden = false
            }
            
            // Rotate EV min/max labels (keep these rotating)
            if let minLabel = self.exposureView.viewWithTag(201) as? UILabel,
               let maxLabel = self.exposureView.viewWithTag(202) as? UILabel {
                minLabel.transform = CGAffineTransform(rotationAngle: rotationAngle)
                maxLabel.transform = CGAffineTransform(rotationAngle: rotationAngle)
            }
            
            // DO NOT rotate any other EV elements.
        }
        
        // Handle settings panel rotation separately
        updateSettingsPanelForOrientation(angle: rotationAngle)
    }

    // New method to properly handle settings panel rotation
    private func updateSettingsPanelForOrientation(angle: CGFloat) {
        // Only adjust if the panel is visible
        guard isSettingsPanelVisible else { return }
        
        // Animate rotation of the panel
        UIView.animate(withDuration: rotationAnimationDuration) {
            self.settingsPanel.transform = CGAffineTransform(rotationAngle: angle)
        }
    }

    // Add this helper method to limit dynamic type scaling
    private func scaledDynamicFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        // Get the preferred font for the style
        let preferredFont = UIFont.preferredFont(forTextStyle: style)
        
        // Get the current content size category
        let currentCategory = UIApplication.shared.preferredContentSizeCategory
        
        // Define the maximum size category we'll respect
        let maxCategory: UIContentSizeCategory = .accessibilityLarge  // Limit to accessibilityLarge
        
        // If the current category is larger than our max, cap the font size
        if currentCategory > maxCategory {
            // Get the font size for our maximum category
            let traitCollection = UITraitCollection(preferredContentSizeCategory: maxCategory)
            let maxFont = UIFont.preferredFont(forTextStyle: style, compatibleWith: traitCollection)
            return maxFont
        }
        
        return preferredFont
    }

    // Make sure to clean up in deinit
    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}

// Keep this extension with CLLocationManagerDelegate implementation
extension CameraViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}
