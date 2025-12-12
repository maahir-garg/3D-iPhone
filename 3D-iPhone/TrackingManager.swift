import Foundation
import ARKit
import Vision
import Combine
import SwiftUI

/// Core engine handling ARSession, Vision processing, and 3D coordinate calculation.
class TrackingManager: NSObject, ObservableObject, ARSessionDelegate {
    
    // MARK: - Published Properties for UI
    
    @Published var isRecording: Bool = false
    @Published var currentPosition: SIMD3<Float> = .zero
    @Published var currentWorldPosition: SIMD3<Float> = .zero // For AR Visualization
    @Published var confidence: Float = 0.0
    @Published var statusMessage: String = "Initializing..."
    @Published var currentLap: Int = 0 // 0 = No Lap / Setup
    
    // MARK: - Internal Properties
    
    let arSession = ARSession()
    private let dataLogger = DataLogger()
    private var cancellables = Set<AnyCancellable>()
    
    // Concurrency & Logic
    private let visionQueue = DispatchQueue(label: "com.3diphone.vision", qos: .userInitiated)
    private var isProcessingFrame = false
    private var smoothingAlpha: Float = 0.6
    
    // Robustness State
    private var lastValidPosition: SIMD3<Float>?
    private var lostFramesCount: Int = 0
    private let maxGhostingFrames = 5
    
    // Vision Request
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    
    // Config
    private let arConfiguration: ARWorldTrackingConfiguration = {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
             config.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        // Focus Locking (Best Effort)
        config.isAutoFocusEnabled = false 
        
        return config
    }()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        arSession.delegate = self
        handPoseRequest.maximumHandCount = 1
    }
    
    // MARK: - Session Control
    
    func startSession() {
        statusMessage = "Starting AR Session..."
        arSession.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func pauseSession() {
        arSession.pause()
        statusMessage = "Session Paused"
    }
    
    func startRecording() {
        isRecording = true
        dataLogger.resetLog()
        currentLap = 0 
        statusMessage = "Recording..."
    }
    
    func stopRecording() {
        isRecording = false
        statusMessage = "Recording Stopped"
    }
    
    func getExportURL() -> URL? {
        return dataLogger.getCSVPath()
    }

    // MARK: - Lap Control
    
    func startLap() {
        currentLap = 1
    }
    
    func nextLap() {
        currentLap += 1
    }
    
    func resetLaps() {
        currentLap = 0
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        // Capture frame data
        let pixelBuffer = frame.capturedImage
        let cameraTransform = frame.camera.transform
        
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isProcessingFrame = false }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            
            do {
                try handler.perform([self.handPoseRequest])
                
                var foundValidPoint = false
                var currentPos: SIMD3<Float> = .zero
                var currentWorld: SIMD3<Float> = .zero
                var currentConf: Float = 0.0
                
                if let observation = self.handPoseRequest.results?.first,
                   let indexTipPoint = try? observation.recognizedPoint(.indexTip),
                   indexTipPoint.confidence > 0.3 {
                    
                    let visionPoint = CGPoint(x: indexTipPoint.location.x, y: indexTipPoint.location.y)
                    
                    // Unproject
                    if let (metricPos, worldPos) = self.get25DMetricPosition(for: visionPoint, using: frame, cameraTransform: cameraTransform) {
                        currentPos = metricPos
                        currentWorld = worldPos
                        currentConf = indexTipPoint.confidence
                        foundValidPoint = true
                        
                        self.lostFramesCount = 0
                        self.lastValidPosition = currentPos
                    }
                }
                
                // Ghosting Logic
                if !foundValidPoint {
                    self.lostFramesCount += 1
                    if self.lostFramesCount <= self.maxGhostingFrames, let lastPos = self.lastValidPosition {
                        currentPos = lastPos
                        // Estimate world pos for ghost based on current camera? 
                        // It's shaky, but better than zero. Let's just zero world for ghost or keep last?
                        // Keeping last known world pos might be wrong if camera moved.
                        // Reconstruct world from stored metric + current camera?
                        // Too complex for ghosting. Let's just hide the dot (Zero World) if ghosting.
                        currentWorld = .zero 
                        currentConf = 0.1 
                        foundValidPoint = true
                    }
                }
                
                DispatchQueue.main.async {
                    if foundValidPoint {
                        // Smoothing (EMA)
                        let oldPos = self.currentPosition
                        let isReset = oldPos == .zero || self.lostFramesCount > 0
                        
                        let smoothedX = (self.smoothingAlpha * currentPos.x + (1 - self.smoothingAlpha) * oldPos.x)
                        let smoothedY = (self.smoothingAlpha * currentPos.y + (1 - self.smoothingAlpha) * oldPos.y)
                        let smoothedZ = (self.smoothingAlpha * currentPos.z + (1 - self.smoothingAlpha) * oldPos.z)
                        
                        let finalPos = isReset ? currentPos : SIMD3<Float>(smoothedX, smoothedY, smoothedZ)
                        
                        self.currentPosition = finalPos
                        self.currentWorldPosition = currentWorld // No smoothing on visual dot for snappy response? Or smooth it too?
                        // Visually, jittery dot is bad. Let's smooth world too.
                        // Or just use the Raw World for now.
                        
                        self.confidence = currentConf
                        
                        if finalPos.z < 0.15 {
                            self.statusMessage = "Too Close! Move Back"
                        } else if self.lostFramesCount > 0 {
                            self.statusMessage = "Tracking... (Ghost)"
                        } else {
                            self.statusMessage = self.isRecording ? "Recording..." : "Tracking Hand"
                        }
                        
                        if self.isRecording {
                            self.dataLogger.appendLog(lapID: self.currentLap, x: finalPos.x, y: finalPos.y, z: finalPos.z, confidence: currentConf)
                        }
                        
                    } else {
                        self.confidence = 0.0
                        self.statusMessage = self.isRecording ? "Rec (Lost Focus)" : "Searching..."
                        self.lastValidPosition = nil
                        self.currentWorldPosition = .zero
                    }
                }
                
            } catch {
                print("Vision Error: \(error)")
            }
        }
    }
    
    // MARK: - 2.5D Metric Logic + Kernel Depth
    
    // Returns (ScreenMetric, WorldPosition)
    private func get25DMetricPosition(for normalizedPoint: CGPoint, using frame: ARFrame, cameraTransform: simd_float4x4) -> (SIMD3<Float>, SIMD3<Float>)? {
        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else { return nil }
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let col = Int(normalizedPoint.x * CGFloat(depthWidth))
        let row = Int(normalizedPoint.y * CGFloat(depthHeight))
        
        guard col >= 0, col < depthWidth, row >= 0, row < depthHeight else { return nil }
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let widthStep = CVPixelBufferGetBytesPerRow(depthMap)
        
        // Kernel Search (3x3)
        // We want the MINIMUM valid depth in the kernel (closest object = finger).
        // Background wall will be further away.
        var minDepth: Float32 = .greatestFiniteMagnitude
        var foundDepth = false
        
        let kernelSize = 2 // -2 to +2 = 5x5. Let's do 1 (-1 to +1 = 3x3) for speed/tightness.
        
        for dy in -1...1 {
            for dx in -1...1 {
                let c = col + dx
                let r = row + dy
                if c >= 0 && c < depthWidth && r >= 0 && r < depthHeight {
                    let off = r * widthStep + c * 4
                    let d = baseAddress.load(fromByteOffset: off, as: Float32.self)
                    if d > 0 && d < minDepth {
                        minDepth = d
                        foundDepth = true
                    }
                }
            }
        }
        
        if foundDepth {
            let Z = Float(minDepth)
            
            // Intrinsic Pinhole Math
            let intrinsics = frame.camera.intrinsics
            let textureSize = frame.camera.imageResolution
            
            let pixelX = normalizedPoint.x * CGFloat(textureSize.width)
            let pixelY = (1 - normalizedPoint.y) * CGFloat(textureSize.height)
            
            // Metric on Screen Plane
            let X_metric = (Float(pixelX) - intrinsics[2, 0]) * Z / intrinsics[0, 0]
            let Y_metric = -(Float(pixelY) - intrinsics[2, 1]) * Z / intrinsics[1, 1] // Up is Positive
            
            // World Space Calculation
            // Camera Space Point (Right Handed: X Right, Y Up, Z Backwards/Toward User)
            // Depth Z is positive distance in front. So Camera Space Z is -Z.
            let localPoint = SIMD4<Float>(X_metric, Y_metric, -Z, 1)
            let worldPos4 = cameraTransform * localPoint
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            
            return (SIMD3<Float>(X_metric, Y_metric, Z), worldPos)
        }
        
        return nil
    }
}

