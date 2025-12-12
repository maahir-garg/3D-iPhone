import SwiftUI
import RealityKit
import ARKit

/// A SwiftUI wrapper for the RealityKit ARView.
struct ARViewContainer: UIViewRepresentable {
    
    @ObservedObject var trackingManager: TrackingManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Use the session from our manager
        arView.session = trackingManager.arSession
        
        // Configure the view
        // .cameraMode = .ar is default
        // .automaticallyConfigureSession = false is implicitly true if we set the session manually? 
        // Actually, if we assign `arView.session`, we control the delegate.
        // It's safer to let ARView own the session usually, but we need the delegate.
        // Since we created `ARSession` in `TrackingManager`, assigning it here is correct.
        
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update the visual indicator based on the tracking position
        context.coordinator.updateSphere(at: trackingManager.currentWorldPosition)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        private var sphereEntity: ModelEntity?
        
        // Create the sphere once
        private func getSphere() -> ModelEntity {
            if let entity = sphereEntity { return entity }
            
            // Create a small sphere
            let mesh = MeshResource.generateSphere(radius: 0.01) // 1cm radius
            let material = SimpleMaterial(color: .cyan, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Create an anchor
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            
            arView?.scene.addAnchor(anchor)
            
            sphereEntity = entity
            return entity
        }
        
        func updateSphere(at position: SIMD3<Float>) {
            guard let arView = arView else { return }
            
            // Perform UI work on main thread just in case, though updateUIView is main.
            let sphere = getSphere()
            
            // Validate position is not zero (initial state)
            if position != .zero {
                sphere.isEnabled = true
                
                // Move sphere to world position
                // Note: The sphere needs to be attached to an anchor in the scene.
                // In `getSphere`, we attached it to an AnchorEntity at world zero.
                // So setting `position` on the sphere entity moves it relative to world zero.
                // Ideally, we maintain the AnchorEntity and move that, or separate them.
                // Easier: Set world position of the sphere entity.
                
                sphere.setPosition(position, relativeTo: nil) // relativeTo: nil means world space
            } else {
                sphere.isEnabled = false // Hide if no tracking
            }
        }
    }
}
