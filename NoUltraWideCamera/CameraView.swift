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

    // Add these properties at the class level (near your other UI element properties)
    private let mainCameraToggle = UISwitch()
    private let telephotoToggle = UISwitch()
    private let opticalQualityToggle = UISwitch()
    private let ultraWideToggle = UISwitch() // This looks like it might be missing too

    // Add this enum for photo formats
    private enum PhotoFormat: String, CaseIterable {
        case heic = "HEIC"
        case jpeg = "JPEG"
        case raw = "RAW"
        
        var fileExtension: String {
            switch self {
            case .heic: return "heic"
            case .jpeg: return "jpeg"
            case .raw: return "dng"
            }
        }
        
        var mimeType: String {
            switch self {
            case .heic: return "image/heic"
            case .jpeg: return "image/jpeg"
            case .raw: return "image/x-adobe-dng"
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
        
        // Updated constraints to place label in top LEFT
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10), // Changed to leading
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
        checkAvailableCameras()
        
        // Wide angle button (1x)
        wideAngleButton.translatesAutoresizingMaskIntoConstraints = false
        wideAngleButton.setTitle("1x", for: .normal)
        wideAngleButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
        wideAngleButton.titleLabel?.adjustsFontForContentSizeCategory = true
        wideAngleButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        wideAngleButton.layer.cornerRadius = 25
        wideAngleButton.addTarget(self, action: #selector(switchToWideAngle), for: .touchUpInside)
        wideAngleButton.alpha = 1.0 // Start with wide angle as active
        view.addSubview(wideAngleButton)
        
        // Telephoto button (2x, 3x or 5x) - if available
        if hasTelephotoCamera {
            telephotoButton.translatesAutoresizingMaskIntoConstraints = false
            telephotoButton.setTitle("\(Int(telephotoZoomFactor))x", for: .normal)
            telephotoButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
            telephotoButton.titleLabel?.adjustsFontForContentSizeCategory = true
            telephotoButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            telephotoButton.layer.cornerRadius = 25
            telephotoButton.addTarget(self, action: #selector(switchToTelephoto), for: .touchUpInside)
            telephotoButton.alpha = 0.4
            view.addSubview(telephotoButton)
        }
        
        // Add 2x optical quality zoom button if available and telephoto > 2
        if has2xOpticalQualityZoom && telephotoZoomFactor > 2.0 {
            twoXButton.translatesAutoresizingMaskIntoConstraints = false
            twoXButton.setTitle("2x", for: .normal)
            twoXButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
            twoXButton.titleLabel?.adjustsFontForContentSizeCategory = true
            twoXButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            twoXButton.layer.cornerRadius = 25
            twoXButton.addTarget(self, action: #selector(switchTo2X), for: .touchUpInside)
            twoXButton.alpha = 0.4
            view.addSubview(twoXButton)
        }
        
        // Create a container for buttons to help with centering
        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalSpacing
        buttonStack.spacing = 10
        view.addSubview(buttonStack)
        
        // Add buttons to stack
        buttonStack.addArrangedSubview(wideAngleButton)
        if has2xOpticalQualityZoom && telephotoZoomFactor > 2.0 {
            buttonStack.addArrangedSubview(twoXButton)
        }
        if hasTelephotoCamera {
            buttonStack.addArrangedSubview(telephotoButton)
        }
        
        // Center the stack view
        NSLayoutConstraint.activate([
            buttonStack.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Fixed sizes for buttons
            wideAngleButton.widthAnchor.constraint(equalToConstant: 50),
            wideAngleButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Add height/width constraints for other buttons
        if has2xOpticalQualityZoom && telephotoZoomFactor > 2.0 {
            NSLayoutConstraint.activate([
                twoXButton.widthAnchor.constraint(equalToConstant: 50),
                twoXButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        if hasTelephotoCamera {
            NSLayoutConstraint.activate([
                telephotoButton.widthAnchor.constraint(equalToConstant: 50),
                telephotoButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
    }

    // Implement a helper method to update all button states
    private func updateCameraButtonHighlighting(activeButton: UIButton) {
        // Set all buttons to dimmed state first
        if let ultraWideButton = view.viewWithTag(301) as? UIButton {
            ultraWideButton.alpha = 0.4
        }
        wideAngleButton.alpha = 0.4
        if has2xOpticalQualityZoom {
            twoXButton.alpha = 0.4
        }
        telephotoButton.alpha = 0.4
        
        // Then highlight only the active button
        activeButton.alpha = 1.0
    }

    // Replace the switchToWideAngle method with this corrected version
    @objc private func switchToWideAngle() {
        guard let captureSession = captureSession else { return }
        
        // Update button states
        updateCameraButtonHighlighting(activeButton: wideAngleButton)
        
        // Skip if already using wide angle camera with no flags set
        if !isUsingTelephoto && !isUsingUltraWide &&
           videoDeviceInput?.device.deviceType == .builtInWideAngleCamera {
            return
        }
        
        do {
            captureSession.beginConfiguration()
            
            // Remove current input
            if let input = videoDeviceInput {
                captureSession.removeInput(input)
            }
            
            // Add wide angle camera input
            if let wideAngleCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let wideAngleInput = try? AVCaptureDeviceInput(device: wideAngleCamera) {
                if captureSession.canAddInput(wideAngleInput) {
                    captureSession.addInput(wideAngleInput)
                    videoDeviceInput = wideAngleInput
                    isUsingTelephoto = false
                    isUsingUltraWide = false
                    
                    // Update zoom label
                    permanentZoomLabel.text = "1.0×"
                }
            }
            
            captureSession.commitConfiguration()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Error switching to wide angle camera: \(error)")
        }
    }

    // Update the switchToTelephoto method for consistency
    @objc private func switchToTelephoto() {
        guard let captureSession = captureSession, hasTelephotoCamera else { return }
        
        // Update button states
        updateCameraButtonHighlighting(activeButton: telephotoButton)
        
        do {
            captureSession.beginConfiguration()
            
            // Remove current input
            if let input = videoDeviceInput {
                captureSession.removeInput(input)
            }
            
            // Add telephoto camera input
            if let telephotoCamera = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back),
               let telephotoInput = try? AVCaptureDeviceInput(device: telephotoCamera) {
                if captureSession.canAddInput(telephotoInput) {
                    captureSession.addInput(telephotoInput)
                    videoDeviceInput = telephotoInput
                    isUsingTelephoto = true
                    isUsingUltraWide = false
                    
                    // Update zoom label
                    permanentZoomLabel.text = String(format: "%.1f×", telephotoZoomFactor)
                }
            }
            
            captureSession.commitConfiguration()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Error switching to telephoto camera: \(error)")
        }
    }

    // Update switchTo2X method for consistency
    @objc private func switchTo2X() {
        // Update button states
        updateCameraButtonHighlighting(activeButton: twoXButton)
        
        // First ensure we're using the wide angle camera (not telephoto or ultra-wide)
        if isUsingTelephoto || isUsingUltraWide {
            switchToWideAngle()
        }
        
        // Then apply 2x zoom
        do {
            if let device = videoDeviceInput?.device {
                try device.lockForConfiguration()
                device.videoZoomFactor = 2.0
                device.unlockForConfiguration()
                
                // Update zoom label
                permanentZoomLabel.text = "2.0×"
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        } catch {
            print("Error setting zoom: \(error)")
        }
    }

    // Update switchToUltraWide method for consistency
    @objc private func switchToUltraWide() {
        guard let captureSession = captureSession else { return }
        
        // Only proceed if we have an ultra-wide camera
        guard hasUltraWideCamera else { return }
        
        // Get the ultra-wide button and update highlights
        if let ultraWideButton = view.viewWithTag(301) as? UIButton {
            updateCameraButtonHighlighting(activeButton: ultraWideButton)
        }
        
        do {
            captureSession.beginConfiguration()
            
            // Remove existing input
            if let input = videoDeviceInput {
                captureSession.removeInput(input)
            }
            
            // Add ultra-wide camera input
            if let ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
               let ultraWideInput = try? AVCaptureDeviceInput(device: ultraWideCamera) {
                if captureSession.canAddInput(ultraWideInput) {
                    captureSession.addInput(ultraWideInput)
                    videoDeviceInput = ultraWideInput
                    isUsingUltraWide = true
                    isUsingTelephoto = false
                    
                    // Update the zoom label
                    permanentZoomLabel.text = "0.5×"
                }
            }
            
            captureSession.commitConfiguration()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Error switching to ultra-wide camera: \(error)")
        }
    }

    @objc private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        // Create settings based on the selected format
        var settings: AVCapturePhotoSettings
        
        switch currentFormat {
        case .heic:
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                // Fall back to JPEG if HEVC isn't available
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
        case .jpeg:
            // Maximum quality JPEG
            settings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: AVVideoCodecType.jpeg,
                AVVideoCompressionPropertiesKey: [
                    AVVideoQualityKey: 1.0, // Maximum quality
                    AVVideoMaxKeyFrameIntervalKey: 1 // Every frame is a keyframe for maximum quality
                ]
            ])
            
        case .raw:
            // Check if RAW is supported
            if hasRawSupport(), let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                // Create settings for RAW+JPEG capture (using correct initialization)
                let processedFormat = [AVVideoCodecKey: AVVideoCodecType.jpeg]
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
            } else {
                // Fall back to HEIC if RAW isn't available
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                }
            }
        }
        
        // Configure flash if enabled
        if isFlashOn {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        
        // Set high resolution mode for all formats
        settings.isHighResolutionPhotoEnabled = true
        
        // Add location metadata if available and supported
        if let location = currentLocation {
            // Location is supported for all formats
            settings.metadata = [kCGImagePropertyGPSDictionary as String: location.gpsDictionary]
        }
        
        // Capture the photo
        photoOutput.capturePhoto(with: settings, delegate: self)
        
        // Update UI to show capturing state
        showCapturingState()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Hide capturing UI
        hideCapturingState()
        
        // Check for errors
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        // Process the captured photo based on format
        var finalImageData: Data?
        var actualFormat = currentFormat
        
        switch currentFormat {
        case .heic, .jpeg:
            // Use the file data directly
            finalImageData = photo.fileDataRepresentation()
            
        case .raw:
            // Check if we have RAW data
            if hasRawSupport(), let rawFileData = photo.fileDataRepresentation() {
                finalImageData = rawFileData
            } else {
                // Fall back to HEIC if RAW isn't available
                finalImageData = photo.fileDataRepresentation()
                actualFormat = .heic // Record that we're actually using HEIC
            }
        }
        
        // Save the image if we have data
        if let imageData = finalImageData {
            savePhotoToLibrary(imageData: imageData, format: actualFormat)
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
        // Format indicator label
        formatIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        formatIndicatorLabel.text = currentFormat.rawValue
        formatIndicatorLabel.textColor = .white
        formatIndicatorLabel.font = scaledDynamicFont(forTextStyle: .body)
        formatIndicatorLabel.adjustsFontForContentSizeCategory = true
        formatIndicatorLabel.textAlignment = .center
        formatIndicatorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        formatIndicatorLabel.layer.cornerRadius = 12
        formatIndicatorLabel.clipsToBounds = true
        formatIndicatorLabel.numberOfLines = 1 // Keep to 1 line but expand the container
        view.addSubview(formatIndicatorLabel)
        
        // Better constraints for the format indicator
        NSLayoutConstraint.activate([
            formatIndicatorLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            formatIndicatorLabel.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 15),
            // Remove fixed width, let it expand to fit content
            formatIndicatorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            // Add padding around text
            formatIndicatorLabel.widthAnchor.constraint(greaterThanOrEqualTo: formatIndicatorLabel.heightAnchor)
        ])
        
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
        // Setup the advanced settings button (gear icon) - BIGGER SIZE
        advancedSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        advancedSettingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        advancedSettingsButton.tintColor = .white
        advancedSettingsButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        advancedSettingsButton.layer.cornerRadius = 25 // Increased from 20
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
        settingsScrollView.showsHorizontalScrollIndicator = true // Enable horizontal indicators
        settingsScrollView.indicatorStyle = .white
        settingsScrollView.alwaysBounceVertical = true
        settingsScrollView.alwaysBounceHorizontal = true // Enable horizontal bounce
        settingsPanel.addSubview(settingsScrollView)
        
        // Create a content view for the scroll view with minimum width
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.addSubview(contentView)
        
        // Update the content view constraints to allow for horizontal scrolling
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: settingsScrollView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: settingsScrollView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: settingsScrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: settingsScrollView.trailingAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualTo: settingsScrollView.widthAnchor) // Ensure minimum width
        ])
        
        // FORMAT SECTION
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
        formatButton.titleLabel?.numberOfLines = 0
        formatButton.titleLabel?.lineBreakMode = .byWordWrapping
        formatButton.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        formatButton.layer.cornerRadius = 8
        formatButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        formatButton.sizeToFit()
        formatButton.addTarget(self, action: #selector(toggleFormat), for: .touchUpInside)
        contentView.addSubview(formatButton)
        
        // Update constraints for format button (removing fixed width)
        NSLayoutConstraint.activate([
            formatButton.topAnchor.constraint(equalTo: formatSectionLabel.bottomAnchor, constant: 10),
            formatButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            // No fixed width constraint here - let it resize based on content
            formatButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
        
        // Hint label - positioned to the right of the format button
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
        formatLabel.preferredMaxLayoutWidth = contentView.bounds.width - 10
        formatLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(formatLabel)
        
        // RAW availability note (if applicable)
        if currentFormat == .raw && !hasRawSupport() {
            let rawUnavailableLabel = UILabel()
            rawUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
            rawUnavailableLabel.text = "RAW is unavailable on this device. Using HEIC instead."
            rawUnavailableLabel.textColor = .systemRed
            rawUnavailableLabel.font = scaledDynamicFont(forTextStyle: .caption1)
            rawUnavailableLabel.adjustsFontForContentSizeCategory = true
            rawUnavailableLabel.numberOfLines = 0
            contentView.addSubview(rawUnavailableLabel)
            
            NSLayoutConstraint.activate([
                rawUnavailableLabel.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 5),
                rawUnavailableLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
                rawUnavailableLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5)
            ])
        }
        
        // LENS SECTION - Add camera lens toggles
        // Add a separator
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
        contentView.addSubview(separator)
        
        // Add lens section title
        let lensSectionLabel = UILabel()
        lensSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        lensSectionLabel.text = "Camera Lenses"
        lensSectionLabel.textColor = .white
        lensSectionLabel.font = scaledDynamicFont(forTextStyle: .headline)
        lensSectionLabel.adjustsFontForContentSizeCategory = true
        contentView.addSubview(lensSectionLabel)
        
        // Add main camera toggle (1x) - always enabled
        let mainCameraLabel = UILabel()
        mainCameraLabel.translatesAutoresizingMaskIntoConstraints = false
        mainCameraLabel.text = "Show Main Camera (1×)"
        mainCameraLabel.textColor = .white
        mainCameraLabel.font = scaledDynamicFont(forTextStyle: .body)
        mainCameraLabel.adjustsFontForContentSizeCategory = true
        mainCameraLabel.numberOfLines = 0
        contentView.addSubview(mainCameraLabel)
        
        // Use the class property instead of local variable
        mainCameraToggle.translatesAutoresizingMaskIntoConstraints = false
        mainCameraToggle.isOn = true
        mainCameraToggle.onTintColor = .systemBlue
        mainCameraToggle.addTarget(self, action: #selector(toggleMainCamera(_:)), for: .valueChanged)
        contentView.addSubview(mainCameraToggle)
        
        // Add 2x optical quality zoom toggle
        let opticalQualityLabel = UILabel()
        opticalQualityLabel.translatesAutoresizingMaskIntoConstraints = false
        opticalQualityLabel.text = "Show 2× Optical Quality Zoom"
        opticalQualityLabel.textColor = .white
        opticalQualityLabel.font = scaledDynamicFont(forTextStyle: .body)
        opticalQualityLabel.adjustsFontForContentSizeCategory = true
        opticalQualityLabel.numberOfLines = 0
        contentView.addSubview(opticalQualityLabel)
        
        // Use the class property instead of local variable
        opticalQualityToggle.translatesAutoresizingMaskIntoConstraints = false
        opticalQualityToggle.isOn = has2xOpticalQualityZoom
        opticalQualityToggle.onTintColor = .systemBlue
        opticalQualityToggle.isEnabled = has2xOpticalQualityZoom
        opticalQualityToggle.addTarget(self, action: #selector(toggleOpticalQualityZoom(_:)), for: .valueChanged)
        contentView.addSubview(opticalQualityToggle)
        
        // Add telephoto toggle
        let telephotoLabel = UILabel()
        telephotoLabel.translatesAutoresizingMaskIntoConstraints = false
        telephotoLabel.text = "Show \(Int(telephotoZoomFactor))× Telephoto Lens"
        telephotoLabel.textColor = .white
        telephotoLabel.font = scaledDynamicFont(forTextStyle: .body)
        telephotoLabel.adjustsFontForContentSizeCategory = true
        telephotoLabel.numberOfLines = 0
        contentView.addSubview(telephotoLabel)
        
        // Use the class property instead of local variable
        telephotoToggle.translatesAutoresizingMaskIntoConstraints = false
        telephotoToggle.isOn = hasTelephotoCamera
        telephotoToggle.onTintColor = .systemBlue
        telephotoToggle.isEnabled = hasTelephotoCamera
        telephotoToggle.addTarget(self, action: #selector(toggleTelephotoCamera(_:)), for: .valueChanged)
        contentView.addSubview(telephotoToggle)
        
        // Add ultra-wide lens toggle LAST
        let ultraWideLensLabel = UILabel()
        ultraWideLensLabel.translatesAutoresizingMaskIntoConstraints = false
        ultraWideLensLabel.text = "Show 0.5× Ultra-Wide Lens"
        ultraWideLensLabel.textColor = .white
        ultraWideLensLabel.font = scaledDynamicFont(forTextStyle: .body)
        ultraWideLensLabel.adjustsFontForContentSizeCategory = true
        ultraWideLensLabel.numberOfLines = 0
        contentView.addSubview(ultraWideLensLabel)
        
        // Use the class property instead of local variable
        ultraWideToggle.translatesAutoresizingMaskIntoConstraints = false
        ultraWideToggle.isOn = false // Default to off
        ultraWideToggle.onTintColor = .systemBlue
        ultraWideToggle.isEnabled = hasUltraWideCamera
        ultraWideToggle.addTarget(self, action: #selector(toggleUltraWideLens(_:)), for: .valueChanged)
        contentView.addSubview(ultraWideToggle)
        
        // Close button
        let closeButton = UIButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(hideSettingsPanel), for: .touchUpInside)
        settingsPanel.addSubview(closeButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Advanced settings button - align with capture button and BIGGER
            advancedSettingsButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            advancedSettingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            advancedSettingsButton.widthAnchor.constraint(equalToConstant: 55), // Even bigger
            advancedSettingsButton.heightAnchor.constraint(equalToConstant: 55), // Even bigger
            
            // Settings panel - make even taller and wider for all the new controls
            settingsPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            settingsPanel.widthAnchor.constraint(equalToConstant: 280), // Back to a reasonable width
            settingsPanel.heightAnchor.constraint(equalToConstant: 400), // Keep taller height
            
            // Scroll view fills the panel (except for close button space)
            settingsScrollView.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 40),
            settingsScrollView.bottomAnchor.constraint(equalTo: settingsPanel.bottomAnchor),
            settingsScrollView.leftAnchor.constraint(equalTo: settingsPanel.leftAnchor),
            settingsScrollView.rightAnchor.constraint(equalTo: settingsPanel.rightAnchor),
            
            // Close button at the top
            closeButton.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Content view to allow for scrolling
            contentView.topAnchor.constraint(equalTo: settingsScrollView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: settingsScrollView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: settingsScrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: settingsScrollView.trailingAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualTo: settingsScrollView.widthAnchor), // Ensure minimum width
            
            // Format section title
            formatSectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            formatSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            formatSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Format button
            formatButton.topAnchor.constraint(equalTo: formatSectionLabel.bottomAnchor, constant: 10),
            formatButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            // formatButton.widthAnchor.constraint(equalToConstant: 70),
            formatButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            
            // Hint label - positioned to the right of the format button
            hintLabel.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: formatButton.trailingAnchor, constant: 8),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Format description - dynamic height
            formatLabel.topAnchor.constraint(equalTo: formatButton.bottomAnchor, constant: 5),
            formatLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            formatLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Separator
            separator.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 15),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            separator.heightAnchor.constraint(equalToConstant: 1),
            
            // Lens section title
            lensSectionLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 15),
            lensSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            lensSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Main camera (1x) toggle
            mainCameraLabel.topAnchor.constraint(equalTo: lensSectionLabel.bottomAnchor, constant: 10),
            mainCameraLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            mainCameraLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.7), // 70% of content width

            mainCameraToggle.centerYAnchor.constraint(equalTo: mainCameraLabel.centerYAnchor),
            mainCameraToggle.leadingAnchor.constraint(equalTo: mainCameraLabel.trailingAnchor, constant: 5),
            // 2x Optical Quality toggle
            opticalQualityLabel.topAnchor.constraint(equalTo: mainCameraLabel.bottomAnchor, constant: 15),
            opticalQualityLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            opticalQualityLabel.trailingAnchor.constraint(equalTo: opticalQualityToggle.leadingAnchor, constant: -10),
            
            opticalQualityToggle.centerYAnchor.constraint(equalTo: opticalQualityLabel.centerYAnchor),
            opticalQualityToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Telephoto toggle
            telephotoLabel.topAnchor.constraint(equalTo: opticalQualityLabel.bottomAnchor, constant: 15),
            telephotoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            telephotoLabel.trailingAnchor.constraint(equalTo: telephotoToggle.leadingAnchor, constant: -10),
            
            telephotoToggle.centerYAnchor.constraint(equalTo: telephotoLabel.centerYAnchor),
            telephotoToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            // Ultra-wide toggle (LAST)
            ultraWideLensLabel.topAnchor.constraint(equalTo: telephotoLabel.bottomAnchor, constant: 15),
            ultraWideLensLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            ultraWideLensLabel.trailingAnchor.constraint(equalTo: ultraWideToggle.leadingAnchor, constant: -10),
            
            ultraWideToggle.centerYAnchor.constraint(equalTo: ultraWideLensLabel.centerYAnchor),
            ultraWideToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            ultraWideToggle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
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
            self.isSettingsPanelVisible = false
        })
        
        // Add haptic feedback when closing - same as when opening
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    @objc private func toggleSettingsPanel() {
        if isSettingsPanelVisible {
            hideSettingsPanel()
        } else {
            showSettingsPanel()
        }
    }

    @objc private func toggleFormat() {
        let allFormats = PhotoFormat.allCases
        let rawSupported = hasRawSupport()
        
        // Find current format and get the next one
        if let currentIndex = allFormats.firstIndex(of: currentFormat) {
            var nextIndex = (currentIndex + 1) % allFormats.count
            
            // Skip RAW if not supported by the device
            if allFormats[nextIndex] == .raw && !rawSupported {
                nextIndex = (nextIndex + 1) % allFormats.count
            }
            
            currentFormat = allFormats[nextIndex]
        }
        
        // Check if we need to add RAW unavailable note
        if currentFormat == .raw && !rawSupported {
            // Add note about RAW unavailability
            formatLabel.text = getFormatDescription(format: currentFormat) + "\n\nRAW is unavailable on this device. Using HEIC instead."
            formatLabel.textColor = .systemRed
        } else {
            formatLabel.text = getFormatDescription(format: currentFormat)
            formatLabel.textColor = .lightGray
        }
        
        // Update UI
        formatButton.setTitle(currentFormat.rawValue, for: .normal)
        formatIndicatorLabel.text = currentFormat.rawValue
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func getFormatDescription(format: PhotoFormat) -> String {
        switch format {
        case .heic:
            return "High efficiency format with smaller file size. Best for most photos."
        case .jpeg:
            return "Universal compatibility. Maximum quality with larger file size."
        case .raw:
            return "Unprocessed sensor data. Maximum editing flexibility, very large files."
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

    // Add this method to handle the ultra-wide lens toggle
    @objc private func toggleUltraWideLens(_ toggle: UISwitch) {
        isUsingUltraWide = toggle.isOn
        
        if isUsingUltraWide && hasUltraWideCamera {
            // Enable/show the 0.5x button
            addUltraWideButton()
        } else {
            // Hide the ultra-wide button
            if let ultraWideButton = view.viewWithTag(301) as? UIButton {
                ultraWideButton.isHidden = true
            }
            
            // If we're currently using ultra-wide camera and turning off the toggle,
            // switch back to the wide angle (1x) camera
            if videoDeviceInput?.device.deviceType == .builtInUltraWideCamera {
                switchToWideAngle()
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // Add this method to set up the ultra-wide camera button
    private func addUltraWideButton() {
        // Check if button already exists (by tag)
        if let ultraWideButton = view.viewWithTag(301) as? UIButton {
            ultraWideButton.isHidden = false
            return
        }
        
        // Create a new button for ultra-wide camera
        let ultraWideButton = UIButton()
        ultraWideButton.tag = 301 // Tag for identification
        ultraWideButton.translatesAutoresizingMaskIntoConstraints = false
        ultraWideButton.setTitle("0.5x", for: .normal)
        ultraWideButton.titleLabel?.font = scaledDynamicFont(forTextStyle: .body)
        ultraWideButton.titleLabel?.adjustsFontForContentSizeCategory = true
        ultraWideButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        ultraWideButton.layer.cornerRadius = 25
        ultraWideButton.addTarget(self, action: #selector(switchToUltraWide), for: .touchUpInside)
        ultraWideButton.alpha = 0.4 // Dimmed initially
        
        // Find our button stack if it exists
        if let buttonStack = view.subviews.first(where: { $0 is UIStackView && $0.subviews.contains(wideAngleButton) }) as? UIStackView {
            // Add the ultra-wide button at the beginning of the stack
            buttonStack.insertArrangedSubview(ultraWideButton, at: 0)
            
            // Set size constraints
            NSLayoutConstraint.activate([
                ultraWideButton.widthAnchor.constraint(equalToConstant: 50),
                ultraWideButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        } else {
            // Fallback if stack view not found (shouldn't happen)
            view.addSubview(ultraWideButton)
            NSLayoutConstraint.activate([
                ultraWideButton.centerYAnchor.constraint(equalTo: wideAngleButton.centerYAnchor),
                ultraWideButton.trailingAnchor.constraint(equalTo: wideAngleButton.leadingAnchor, constant: -10),
                ultraWideButton.widthAnchor.constraint(equalToConstant: 50),
                ultraWideButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        // Apply current rotation if needed
        if currentOrientation.isLandscape {
            var rotationAngle: CGFloat = 0
            switch currentOrientation {
            case .landscapeLeft: rotationAngle = CGFloat.pi / 2
            case .landscapeRight: rotationAngle = -CGFloat.pi / 2
            default: break
            }
            ultraWideButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
    }

    // Add this method to correctly check for RAW support
    private func hasRawSupport() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return false
        }
        
        // Check if the photoOutput supports RAW capture
        if let photoOutput = photoOutput {
            return !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        }
        
        return false
    }

    // Add the missing showCapturingState and hideCapturingState methods
    private func showCapturingState() {
        // Change appearance of capture button to indicate photo is being captured
        captureButton.alpha = 0.5
        captureButton.isEnabled = false
        
        // Optionally add a visual indicator or animation
        // ...
    }

    private func hideCapturingState() {
        // Reset appearance of capture button
        captureButton.alpha = 1.0
        captureButton.isEnabled = true
        
        // Remove any visual indicators if added
        // ...
    }

    // Add these methods to handle the new toggles
    @objc private func toggleMainCamera(_ toggle: UISwitch) {
        // Main camera cannot be disabled if all others are off
        if !toggle.isOn &&
           !(telephotoToggle.isOn && hasTelephotoCamera) &&
           !(opticalQualityToggle.isOn && has2xOpticalQualityZoom) &&
           !(ultraWideToggle.isOn && hasUltraWideCamera) {
            // Force toggle back on
            toggle.setOn(true, animated: true)
            return
        }
        
        // If turning off main camera while it's active, switch to something else
        if !toggle.isOn && !isUsingTelephoto && !isUsingUltraWide && videoDeviceInput?.device.deviceType == .builtInWideAngleCamera {
            // Try to switch to another enabled camera
            if telephotoToggle.isOn && hasTelephotoCamera {
                switchToTelephoto()
            } else if ultraWideToggle.isOn && hasUltraWideCamera {
                switchToUltraWide()
            } else if opticalQualityToggle.isOn && has2xOpticalQualityZoom {
                switchTo2X()
            }
        }
        
        // Update button visibility
        wideAngleButton.isHidden = !toggle.isOn
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    @objc private func toggleOpticalQualityZoom(_ toggle: UISwitch) {
        // If turning off while active, switch to main camera
        if !toggle.isOn && !isUsingTelephoto && !isUsingUltraWide &&
           videoDeviceInput?.device.deviceType == .builtInWideAngleCamera &&
           videoDeviceInput?.device.videoZoomFactor == 2.0 {
            // Reset zoom and switch to main 1x
            if let device = videoDeviceInput?.device {
                try? device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
                
                // Update button highlight
                updateCameraButtonHighlighting(activeButton: wideAngleButton)
                permanentZoomLabel.text = "1.0×"
            }
        }
        
        // Update button visibility
        if let twoXButton = view.viewWithTag(201) as? UIButton {
            twoXButton.isHidden = !toggle.isOn
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    @objc private func toggleTelephotoCamera(_ toggle: UISwitch) {
        // If turning off while active, switch to main camera
        if !toggle.isOn && isUsingTelephoto {
            switchToWideAngle()
        }
        
        // Update button visibility
        telephotoButton.isHidden = !toggle.isOn
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // Update savePhotoToLibrary method to handle format tracking
    private func savePhotoToLibrary(imageData: Data, format: PhotoFormat = .heic) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                }, completionHandler: { success, error in
                    if let error = error {
                        print("Error saving photo: \(error.localizedDescription)")
                    }
                })
            }
        }
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

// Add this extension to help with GPS metadata
extension CLLocation {
    var gpsDictionary: [String: Any] {
        // Create GPS metadata dictionary according to EXIF standard
        var gps: [String: Any] = [:]
        
        // Latitude
        let latitudeRef = coordinate.latitude < 0 ? "S" : "N"
        let latitude = abs(coordinate.latitude)
        gps[kCGImagePropertyGPSLatitudeRef as String] = latitudeRef
        gps[kCGImagePropertyGPSLatitude as String] = latitude
        
        // Longitude
        let longitudeRef = coordinate.longitude < 0 ? "W" : "E"
        let longitude = abs(coordinate.longitude)
        gps[kCGImagePropertyGPSLongitudeRef as String] = longitudeRef
        gps[kCGImagePropertyGPSLongitude as String] = longitude
        
        // Altitude
        if altitude >= 0 {
            gps[kCGImagePropertyGPSAltitudeRef as String] = 0
            gps[kCGImagePropertyGPSAltitude as String] = altitude
        } else {
            gps[kCGImagePropertyGPSAltitudeRef as String] = 1
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitude)
        }
        
        // Timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSSSSS"
        gps[kCGImagePropertyGPSTimeStamp as String] = dateFormatter.string(from: timestamp)
        
        dateFormatter.dateFormat = "yyyy:MM:dd"
        gps[kCGImagePropertyGPSDateStamp as String] = dateFormatter.string(from: timestamp)
        
        return gps
    }
}
