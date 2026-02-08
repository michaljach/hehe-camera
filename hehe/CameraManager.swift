//
//  CameraManager.swift
//  hehe
//

import AVFoundation
import UIKit
import Combine
import CoreMedia
import Photos

public class CameraManager: NSObject, ObservableObject {
    @Published public var cameraPermissionGranted = false
    @Published public var photoLibraryPermissionGranted = false
    @Published public var sessionRunning = false
    @Published public var captureError: Error?
    @Published public var lastCapturedImage: UIImage?
    @Published public var currentZoomLevel: CGFloat = 1.0
    @Published public var availableLenses: [Lens] = []
    @Published public var exposureBias: Float = 0.0
    @Published public var minExposureBias: Float = -8.0
    @Published public var maxExposureBias: Float = 8.0
    @Published public var captureSession: AVCaptureSession?
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    private var rawPhotoProcessor: CIContext?
    private var currentCaptureID: Int64 = 0
    
    public struct Lens: Identifiable {
        public let id = UUID()
        public let deviceType: AVCaptureDevice.DeviceType
        public let label: String
        public let zoomLevel: CGFloat
        
        public init(deviceType: AVCaptureDevice.DeviceType, label: String, zoomLevel: CGFloat) {
            self.deviceType = deviceType
            self.label = label
            self.zoomLevel = zoomLevel
        }
    }
    
    public override init() {
        super.init()
        checkPermissions()
    }
    
    func setupAvailableLenses() {
        var lenses: [Lens] = []
        var usedZoomLevels: Set<CGFloat> = []
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        
        let devices = discoverySession.devices
        print("Available devices: \(devices.count)")
        
        for device in devices {
            print("Found device: \(device.localizedName) - \(device.deviceType)")
            
            var label: String
            var zoom: CGFloat
            
            switch device.deviceType {
            case .builtInUltraWideCamera:
                label = "0.5"
                zoom = 0.5
            case .builtInWideAngleCamera:
                label = "1"
                zoom = 1.0
            case .builtInTelephotoCamera:
                // Determine telephoto zoom level based on device
                // iPhone Pro models vary between 2x, 2.5x, 3x, 5x depending on model
                let format = device.activeFormat
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                // Approximate detection based on typical resolutions
                if dimensions.width >= 4000 {
                    label = "5"
                    zoom = 5.0
                } else if dimensions.width >= 3500 {
                    label = "3"
                    zoom = 3.0
                } else if dimensions.width >= 3000 {
                    label = "2.5"
                    zoom = 2.5
                } else {
                    label = "2"
                    zoom = 2.0
                }
            default:
                continue // Skip unknown device types
            }
            
            // Only add if we haven't seen this zoom level before
            if !usedZoomLevels.contains(zoom) {
                usedZoomLevels.insert(zoom)
                lenses.append(Lens(deviceType: device.deviceType, label: label, zoomLevel: zoom))
            }
        }
        
        // Sort lenses by zoom level
        lenses.sort { $0.zoomLevel < $1.zoomLevel }
        
        DispatchQueue.main.async {
            self.availableLenses = lenses
            if let first = lenses.first(where: { $0.zoomLevel == 1.0 }) ?? lenses.first {
                self.currentZoomLevel = first.zoomLevel
            }
        }
        
        print("Available lenses: \(lenses.map { $0.label })")
    }
    
    func checkPermissions() {
        checkCameraPermission()
        checkPhotoLibraryPermission()
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraPermissionGranted = granted
                    if granted {
                        self?.setupCaptureSession()
                    }
                }
            }
        case .denied, .restricted:
            cameraPermissionGranted = false
        @unknown default:
            cameraPermissionGranted = false
        }
    }
    
    func checkPhotoLibraryPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            photoLibraryPermissionGranted = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                DispatchQueue.main.async {
                    self?.photoLibraryPermissionGranted = (status == .authorized || status == .limited)
                }
            }
        case .denied, .restricted:
            photoLibraryPermissionGranted = false
        @unknown default:
            photoLibraryPermissionGranted = false
        }
    }
    
    func setupCaptureSession() {
        guard cameraPermissionGranted else { return }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
            session.sessionPreset = .photo
        
        do {
            setupAvailableLenses()
            
            let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video)
            
            guard let videoDevice = videoDevice else {
                throw NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera not found"])
            }
            
            print("Using device: \(videoDevice.localizedName)")
            print("Device type: \(videoDevice.deviceType)")
            
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
            }
            
            let photoOutput = AVCapturePhotoOutput()
            
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                self.photoOutput = photoOutput
                
                photoOutput.maxPhotoQualityPrioritization = .quality
                
                // Enable high resolution capture
                if #available(iOS 16.0, *) {
                    // Use maxPhotoDimensions instead
                } else {
                    photoOutput.isHighResolutionCaptureEnabled = true
                }
                
                let dimensions = photoOutput.maxPhotoDimensions
                print("Photo output max dimensions: \(dimensions.width)x\(dimensions.height)")
                print("Available RAW formats: \(photoOutput.availableRawPhotoPixelFormatTypes)")
                print("Available photo codecs: \(photoOutput.availablePhotoCodecTypes)")
                print("Is high resolution enabled: \(photoOutput.isHighResolutionCaptureEnabled)")
            }
            
            session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.captureSession = session
                
                // Create and store the preview layer
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill
                self.previewLayer = previewLayer
            }
            
            // Setup exposure observer
            setupExposureObserver()
            
        } catch {
            DispatchQueue.main.async {
                self.captureError = error
            }
            print("Error setting up capture session: \(error)")
        }
    }
    
    public func startSession() {
        guard let session = captureSession else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !session.isRunning {
                session.startRunning()
                DispatchQueue.main.async {
                    self?.sessionRunning = session.isRunning
                }
            }
        }
    }
    
    public func stopSession() {
        guard let session = captureSession else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if session.isRunning {
                session.stopRunning()
                DispatchQueue.main.async {
                    self?.sessionRunning = session.isRunning
                }
            }
        }
    }
    
    public func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        let photoSettings: AVCapturePhotoSettings
        
        let dimensions = photoOutput.maxPhotoDimensions
        print("Capturing with max dimensions: \(dimensions.width)x\(dimensions.height)")
        
        if photoOutput.availableRawPhotoPixelFormatTypes.count > 0 {
            let rawFormatType = photoOutput.availableRawPhotoPixelFormatTypes[0]
            let processedFormat: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg]
            photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType, processedFormat: processedFormat)
        } else {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        
        photoSettings.maxPhotoDimensions = dimensions
        
        if let photoPreviewType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoPreviewType]
        }
        
        currentCaptureID = photoSettings.uniqueID
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    public func toggleFlash() {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            if device.hasFlash {
                device.flashMode = device.flashMode == .on ? .off : .on
            }
            device.unlockForConfiguration()
        } catch {
            print("Error toggling flash: \(error)")
        }
    }
    
    public func setExposureBias(_ bias: Float) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Clamp bias to supported range
            let clampedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            device.setExposureTargetBias(clampedBias)
            
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.exposureBias = clampedBias
            }
            print("Set exposure bias to \(clampedBias)")
        } catch {
            print("Error setting exposure bias: \(error)")
        }
    }
    
    public func setupExposureObserver() {
        guard let device = videoDeviceInput?.device else { return }
        
        DispatchQueue.main.async {
            self.minExposureBias = device.minExposureTargetBias
            self.maxExposureBias = device.maxExposureTargetBias
            self.exposureBias = device.exposureTargetBias
        }
    }
    
    public func switchLens(to lens: Lens) {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
            
            if let newDevice = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) {
                do {
                    let newInput = try AVCaptureDeviceInput(device: newDevice)
                    if session.canAddInput(newInput) {
                        session.addInput(newInput)
                        videoDeviceInput = newInput
                        DispatchQueue.main.async {
                            self.currentZoomLevel = lens.zoomLevel
                        }
                        print("Switched to lens: \(lens.label)x")
                        
                        // Setup exposure for new lens
                        setupExposureObserver()
                    }
                } catch {
                    print("Error switching lens: \(error)")
                    // Try to restore previous input
                    if session.canAddInput(currentInput) {
                        session.addInput(currentInput)
                    }
                }
            }
        }
        
        session.commitConfiguration()
    }
    
    public func switchCamera() {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
            
            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
            
            if let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) {
                do {
                    let newInput = try AVCaptureDeviceInput(device: newDevice)
                    if session.canAddInput(newInput) {
                        session.addInput(newInput)
                        videoDeviceInput = newInput
                    }
                } catch {
                    print("Error switching camera: \(error)")
                }
            }
        }
        
        session.commitConfiguration()
    }
    
    public func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
    
    public func focus(at pointOfInterest: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = pointOfInterest
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = pointOfInterest
                device.exposureMode = .autoExpose
            }
            
            // Reset exposure bias to 0 (auto) when tapping to focus
            device.setExposureTargetBias(0)
            
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.exposureBias = 0
            }
            
            print("Focus set to: \(pointOfInterest), exposure reset to auto")
        } catch {
            print("Error setting focus: \(error)")
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            DispatchQueue.main.async {
                self.captureError = error
            }
            return
        }
        
        print("Processing photo - isRaw: \(photo.isRawPhoto), uniqueID: \(photo.resolvedSettings.uniqueID)")
        print("Photo dimensions: \(photo.resolvedSettings.photoDimensions.width)x\(photo.resolvedSettings.photoDimensions.height)")
        
        // Only save RAW photos to Photo Library, skip processed JPEG
        if !photo.isRawPhoto {
            // Update preview with processed image but don't save to Photos
            if let imageData = photo.fileDataRepresentation(),
               let image = UIImage(data: imageData) {
                print("Processed image size: \(image.size.width)x\(image.size.height)")
                DispatchQueue.main.async {
                    self.lastCapturedImage = image
                }
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("No RAW data available")
            return
        }
        
        // Save RAW to Photo Library
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("RAW photo saved to Photo Library successfully")
                } else if let error = error {
                    print("Error saving RAW to Photo Library: \(error)")
                }
            }
        }
    }
}
