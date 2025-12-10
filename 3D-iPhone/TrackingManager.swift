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
    @Published var confidence: Float = 0.0
    @Published var statusMessage: String = "Initializing..."
    
    // MARK: - Internal Properties
    
    let arSession = ARSession()
    private let dataLogger = DataLogger()
    private var cancellables = Set<AnyCancellable>()
    
    // Vision Request
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    
    // Config
    // We want sceneDepth for LiDAR readings.
    private let arConfiguration: ARWorldTrackingConfiguration = {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [] // We don't strictly need planes, but good to have if we want to expand.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        // smoothedSceneDepth provides more stable readings but might have slightly more latency.
        // For finger tracking, smoothed is usually better for "glued" visualization.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
             config.frameSemantics.insert(.smoothedSceneDepth)
        }
        return config
    }()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        arSession.delegate = self
        handPoseRequest.maximumHandCount = 1 // Track only one hand for simplicity/performance
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
        statusMessage = "Recording..."
    }
    
    func stopRecording() {
        isRecording = false
        statusMessage = "Recording Stopped"
    }
    
    func getExportURL() -> URL? {
        return dataLogger.getCSVPath()
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 1. Prepare Vision Handler
        let pixelBuffer = frame.capturedImage
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // 2. Perform Vision Request (Async to not block ARKit delegate too much, though fast enough for main in simple apps)
        // Note: For high perf, we dispatch this. But we need sync results to match the CURRENT ARFrame for depth.
        // Since we need to raycast on *this specific frame*, we should do it synchronously here or capture the frame.
        // Given iPhone 17 Pro power, sync vision on delegate is usually acceptable for single hand.
        
        do {
            try handler.perform([handPoseRequest])
            
            guard let observation = handPoseRequest.results?.first else {
                // No hand detected
                DispatchQueue.main.async {
                    self.confidence = 0.0
                    self.statusMessage = self.isRecording ? "Recording (No Hand)" : "Searching for Hand..."
                }
                return
            }
            
            // 3. Get Index Tip
            let indexTipPoint = try observation.recognizedPoint(.indexTip)
            
            // 4. Unproject 2D -> 3D
            // Vision gives normalized coordinates (0,0 bottom-left to 1,1 top-right).
            if indexTipPoint.confidence > 0.3 {
                // Convert Vision point (Y-up) to ARKit/Screen point (Y-down usually for some APIs, but ARFrame raycast accepts normalized 0..1 with Y-up?
                // Wait, raycast(from:) takes a CGPoint in viewport capability.
                // It's safer to use the standard coordinate conversion.
                // Vision: (0,0) bottom-left.
                // Viewport: depends on orientation, but usually (0,0) top-left.
                // However, frame.raycastQuery uses normalized point in image coordinate system (0..1).
                // Let's verify. ARFrame.camera.transform puts identity in landscape.
                // Vision handler was passed .up.
                // Let's assume standard normalization and simple flip if needed.
                // Actually, `frame.raycastQuery` expects normalized point in image coordinate system (0..1).
                // Vision is (x, 1-y) relative to Metal/ARKit textures usually.
                
                // Let's try straight mapping first, but Vision y is inverted relative to UIKit.
                // Vision: (0,0) is bottom-left.
                // ARKit Image: (0,0) is usually top-left.
                // Vision: (0,0) is bottom-left.
                // We pass it as-is to unprojection, where we handle the coordinate flip for texture sampling.
                // Actually, wait. `visionPoint` uses Vision Coordinates (0..1, 0=Bottom).
                // The `get3DPosition` function expects `normalizedPoint` to be Vision Coordinates?
                // Yes, "normalizedPoint: CGPoint" (Vision 0..1).
                // Inside `get3DPosition`, we do `pixelY = (1 - normalizedPoint.y) * H`.
                // So we should pass the raw Vision Observation point here (0=Bottom).
                guard let visionPoint = try? observation.recognizedPoint(.indexTip).location else { return } // location is (x, y)
                
                if let worldPos = get3DPosition(for: visionPoint, using: frame) {
                    
                    let posVector = SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
                    
                    // Update State
                    DispatchQueue.main.async {
                        self.currentPosition = posVector
                        self.confidence = indexTipPoint.confidence
                        self.statusMessage = self.isRecording ? "Recording..." : "Tracking Hand"
                    }
                    
                    // Log if recording
                    if isRecording {
                        dataLogger.appendLog(x: worldPos.x, y: worldPos.y, z: worldPos.z, confidence: indexTipPoint.confidence)
                    }
                }
            } else {
                 DispatchQueue.main.async { self.confidence = 0.0 }
            }
            
        } catch {
            print("Vision Error: \(error)")
        }
    }
    
    // MARK: - 3D Unprojection Logic
    
    /// Calculates the 3D world position from a 2D normalized point using LiDAR depth.
    private func get3DPosition(for normalizedPoint: CGPoint, using frame: ARFrame) -> SIMD3<Float>? {
        // Method 1: Raycast against the estimated Scene Geometry (LiDAR Mesh / Plane)
        // This is robust for surfaces, but for a finger in mid-air, it might hit the wall BEHIND the finger.
        // We really want the depth of the pixel *at* the finger.
        // However, the finger itself is not part of the static scene mesh usually unless we are meshing constantly.
        // BUT, we have `sceneDepth` or `smoothedSceneDepth`. We can sample the depth map directly.
        
        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
            // Fallback: Raycast against estimated planes if no LiDAR depth map (shouldn't happen on Pro).
            return raycastPlane(point: normalizedPoint, frame: frame)
        }
        
        // Sample the depth map at the normalized coordinate.
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let col = Int(normalizedPoint.x * CGFloat(depthWidth))
        let row = Int(normalizedPoint.y * CGFloat(depthHeight))
        
        // Safety check
        guard col >= 0, col < depthWidth, row >= 0, row < depthHeight else { return nil }
        
        // Lock and read
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Depth maps are Float32 usually
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let widthStep = CVPixelBufferGetBytesPerRow(depthMap)
        let offset = row * widthStep + col * 4 // 4 bytes per Float32
        
        // Read depth value in meters
        let depthInMeters = baseAddress.load(fromByteOffset: offset, as: Float32.self)
        
        // Check for valid depth (non-zero)
        if depthInMeters > 0 {
            // Manual Unprojection using Camera Intrinsics
            // We convert the normalized point (0..1) to pixel coordinates.
            let intrinsics = frame.camera.intrinsics
            let textureSize = frame.camera.imageResolution
            
            // Vision Point: normalized (0,0 bottom-left).
            // Image Texture: (0,0 top-left).
            // We must flip Y to sample the texture correctly (Vision Y=1 -> Image Row 0).
            let pixelX = normalizedPoint.x * CGFloat(textureSize.width)
            let pixelY = (1 - normalizedPoint.y) * CGFloat(textureSize.height)
            
            // Camera Space Calculation
            // ARKit Camera: +X Right, +Y Up, -Z Forward.
            // Image Space: u increases Right, v increases Down.
            
            // Depth is distance (positive). Z_cam is -depth.
            // Pinhole Model (Virtual Plane): Left Pixel (u < ox) -> Left Camera Point (x < 0).
            // This requires scaling by POSITIVE depth. Using signed Z (-depth) flips the axes.
            
            let depth = Float(depthInMeters)
            
            // X = (u - ox) * depth / fx
            let x = (Float(pixelX) - intrinsics[2, 0]) * depth / intrinsics[0, 0]
            
            // Y = (v - oy) * depth / fy
            // BUT: Image Y increases DOWN. Camera Y increases UP.
            // So we must invert the Y delta.
            let y = -(Float(pixelY) - intrinsics[2, 1]) * depth / intrinsics[1, 1]
            
            // Z = -depth
            let z = -depth
            
            let localPoint = SIMD4<Float>(x, y, z, 1)
            let worldPos = frame.camera.transform * localPoint
            
            return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
            
        } else {
             return raycastPlane(point: normalizedPoint, frame: frame)
        }
    }
    
    // Fallback raycast
    private func raycastPlane(point: CGPoint, frame: ARFrame) -> SIMD3<Float>? {
        let query = frame.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any)
        
        // Use the session instance from the class
        if let result = arSession.raycast(query).first {
            let trans = result.worldTransform.columns.3
            return SIMD3<Float>(trans.x, trans.y, trans.z)
        }
        return nil
    }
}

