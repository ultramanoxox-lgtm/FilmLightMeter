import AVFoundation
import Combine
import UIKit
import CoreMedia
import CoreVideo

// 修复 Enum 语法
enum MeteringMode: String {
    case average = "AVERAGE"
    case spot = "SPOT"
}

class CameraManager: NSObject, ObservableObject {
    @Published var ev100: Double = 0
    @Published var isLocked: Bool = false
    @Published var exposurePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var visualPoint: CGPoint = CGPoint(x: 150, y: 200)
    @Published var meteringMode: String = "SPOT"
    @Published var distanceMeters: Double? = nil
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.filmlightmeter.sessionQueue")
    private var device: AVCaptureDevice?
    private var smoothedDistance: Double? = nil
    private let distanceSmoothingAlpha: Double = 0.2
    private let distanceMaxJumpMeters: Double = 1.5
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            guard let device = self.selectCaptureDevice() else { return }
            self.device = device
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                }

                let depthFormats = device.activeFormat.supportedDepthDataFormats
                let supportsDepth = !depthFormats.isEmpty && self.session.canAddOutput(self.depthOutput)

                if supportsDepth {
                    self.session.addOutput(self.depthOutput)
                    self.depthOutput.isFilteringEnabled = true
                    self.depthOutput.setDelegate(self, callbackQueue: self.sessionQueue)
                    self.depthOutput.alwaysDiscardsLateDepthData = true

                    if let depthConnection = self.depthOutput.connection(with: .depthData) {
                        depthConnection.isEnabled = true
                    }

                    let depthFloatFormats = depthFormats.filter { format in
                        CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_DepthFloat32
                    }
                    let depthFormat = depthFloatFormats.max { a, b in
                        let aDim = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                        let bDim = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                        let aArea = Int(aDim.width) * Int(aDim.height)
                        let bArea = Int(bDim.width) * Int(bDim.height)
                        return aArea < bArea
                    }
                    if let depthFormat = depthFormat {
                        try device.lockForConfiguration()
                        device.activeDepthDataFormat = depthFormat
                        device.unlockForConfiguration()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.smoothedDistance = nil
                        self.distanceMeters = nil
                    }
                }

                self.session.commitConfiguration()
                self.session.startRunning()
            } catch {
                print("Error: \(error)")
            }
        }
    }

    private func selectCaptureDevice() -> AVCaptureDevice? {
        let backSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInLiDARDepthCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        if let lidar = backSession.devices.first(where: { $0.deviceType == .builtInLiDARDepthCamera }) {
            return lidar
        }
        if let dual = backSession.devices.first(where: {
            $0.deviceType == .builtInDualCamera || $0.deviceType == .builtInDualWideCamera
        }) {
            return dual
        }
        if let wide = backSession.devices.first {
            return wide
        }

        let frontSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        return frontSession.devices.first
    }
    
    func updateManualExposure(iso: Double, shutterSpeed: Double, aperture: Double) {
        guard let device = device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clampedISO = Float(max(device.activeFormat.minISO, min(Float(iso), device.activeFormat.maxISO)))
                let deviceAperture = Double(device.lensAperture)
                let apertureRatio = (deviceAperture > 0 && aperture > 0) ? (deviceAperture / aperture) : 1.0
                let adjustedShutter = shutterSpeed * apertureRatio * apertureRatio

                let minDuration = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
                let maxDuration = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
                let clampedDurationSeconds = max(min(adjustedShutter, maxDuration), minDuration)
                let duration = CMTime(seconds: clampedDurationSeconds, preferredTimescale: 1000000)
                device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("Manual exposure error: \(error)")
            }
        }
    }
    
    func setExposurePoint(_ point: CGPoint, visualPoint: CGPoint) {
        guard let device = device, meteringMode == "SPOT" else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.exposurePoint = point
                    self.visualPoint = visualPoint
                }
            } catch {
                print("Point error: \(error)")
            }
        }
    }
    
    func toggleMeteringMode() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()
        meteringMode = (meteringMode == "SPOT") ? "AVERAGE" : "SPOT"
        guard let device = device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
            } catch {
                print("Mode toggle error: \(error)")
            }
        }
    }

    private func smoothDistance(_ rawMeters: Double) -> Double {
        guard let last = smoothedDistance else {
            smoothedDistance = rawMeters
            return rawMeters
        }
        let clamped = min(max(rawMeters, last - distanceMaxJumpMeters), last + distanceMaxJumpMeters)
        let filtered = last + (clamped - last) * distanceSmoothingAlpha
        smoothedDistance = filtered
        return filtered
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let device = self.device else { return }
        
        let iso = Double(device.iso)
        let duration = CMTimeGetSeconds(device.exposureDuration)
        // 修复 lensAperture 访问问题
        let aperture = Double(device.lensAperture)
        let offset = Double(device.exposureTargetOffset)
        
        // 假设您已经有了 MeteringEngine.swift
        let evBase = log2(pow(aperture, 2) / duration) - log2(iso / 100.0)
        let calculatedEV = evBase + offset
        
        DispatchQueue.main.async {
            self.ev100 = calculatedEV
        }
    }
}

extension CameraManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthMap = converted.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return }

        let x = min(max(Int(CGFloat(width - 1) * exposurePoint.x), 0), width - 1)
        let y = min(max(Int(CGFloat(height - 1) * exposurePoint.y), 0), height - 1)

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let row = baseAddress.advanced(by: y * bytesPerRow)
        let depthValue = row.assumingMemoryBound(to: Float32.self)[x]

        guard depthValue.isFinite, depthValue > 0 else { return }

        let filteredMeters = smoothDistance(Double(depthValue))
        DispatchQueue.main.async {
            self.distanceMeters = filteredMeters
        }
    }
}
