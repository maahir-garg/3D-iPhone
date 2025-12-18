import SwiftUI
import SceneKit

struct TrajectorySceneView: UIViewRepresentable {
    
    var points: [TrackingPoint]
    var showArrows: Bool = true
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = UIColor.white // White Background
        
        // Setup Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 0.4) 
        scnView.scene?.rootNode.addChildNode(cameraNode)
        
        // Add Grid Helper (Grey Lines on XZ plane)
        let gridSize = 10
        let step: Float = 0.05
        let gridContainer = SCNNode()
        
        let lineMat = SCNMaterial()
        lineMat.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.5)
        
        for i in -gridSize...gridSize {
            let pos = Float(i) * step
            // Vertical lines (along Y) - actually we want a "wall" grid or "floor"? 
            // Hand tracking usually in front of user (XY plane mostly). depth is Z.
            // Let's make a grid on the back plane (Z is far) or just a box reference.
            // Let's do a 3D box grid? Or just XY Backplane grid since user moves in XY mostly.
            
            // Vertical (Y-axis) lines at varies X
            let vLine = SCNCylinder(radius: 0.0005, height: 1.0)
            vLine.firstMaterial = lineMat
            let vNode = SCNNode(geometry: vLine)
            vNode.position = SCNVector3(pos, 0, -0.2) // Behind data
            gridContainer.addChildNode(vNode)
            
            // Horizontal (X-axis) lines at varies Y
            let hLine = SCNCylinder(radius: 0.0005, height: 1.0)
            hLine.firstMaterial = lineMat
            let hNode = SCNNode(geometry: hLine)
            hNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            hNode.position = SCNVector3(0, pos, -0.2)
            gridContainer.addChildNode(hNode)
        }
        scnView.scene?.rootNode.addChildNode(gridContainer)
        
        // Origins
        let center = SCNNode(geometry: SCNSphere(radius: 0.003))
        center.geometry?.firstMaterial?.diffuse.contents = UIColor.black
        scnView.scene?.rootNode.addChildNode(center)
        
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        // Clear previous path
        scnView.scene?.rootNode.childNodes.forEach { node in
            if node.name == "path" || node.name == "arrow" || node.name == "joint" {
                node.removeFromParentNode()
            }
        }
        
        guard points.count > 1 else { return }
        
        // Draw Path
        // We will enable a "Tube" look by adding spheres at joints
        let radius: CGFloat = 0.002
        
        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i+1]
            
            let v1 = SCNVector3(p1.x, p1.y, p1.z)
            let v2 = SCNVector3(p2.x, p2.y, p2.z)
            
            let distance = distanceBetween(v1, v2)
            if distance < 0.001 { continue }
            
            // Color Logic
            let normalizedVel = CGFloat(min(p2.velocity, 1.0) / 1.0)
            let color = UIColor(hue: 0.66 - (0.66 * normalizedVel), saturation: 1.0, brightness: 1.0, alpha: 1.0)
            
            // Cylinder (Segment)
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
            cylinder.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: cylinder)
            node.name = "path"
            node.position = SCNVector3((v1.x + v2.x)/2, (v1.y + v2.y)/2, (v1.z + v2.z)/2)
            node.look(at: v2, up: scnView.scene!.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
            scnView.scene?.rootNode.addChildNode(node)
            
            // Sphere (Joint) - Smooths the connection
            let sphere = SCNSphere(radius: radius)
            sphere.firstMaterial?.diffuse.contents = color
            let jointNode = SCNNode(geometry: sphere)
            jointNode.name = "joint"
            jointNode.position = v1 
            scnView.scene?.rootNode.addChildNode(jointNode)
            
            // Ensure last point also has a joint cap
            if i == points.count - 2 {
                let endNode = SCNNode(geometry: sphere)
                endNode.name = "joint"
                endNode.position = v2
                scnView.scene?.rootNode.addChildNode(endNode)
            }
            
            // Arrows (Vector Field style)
            if showArrows && i % 15 == 0 {
                let cone = SCNCone(topRadius: 0, bottomRadius: 0.004, height: 0.01)
                cone.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.8)
                let arrowNode = SCNNode(geometry: cone)
                arrowNode.name = "arrow"
                arrowNode.position = v2
                arrowNode.look(at: p2 == points.last! ? v2 : SCNVector3(points[i+2].x, points[i+2].y, points[i+2].z), 
                               up: scnView.scene!.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
                arrowNode.eulerAngles.x -= Float.pi / 2 
                // Correction: SCNCone default is Y-up. look(at) aligns -Z. 
                // We want Cone Tip (+Y) to point to target.
                // Standard lookAt aligns Node -Z to target.
                // So we rotate Cone -90 around X to align Y with -Z ???
                // Actually, let's keep it simple: Cylinder points Y along axis. Cone points Y.
                // The implementation above for cylinder worked.
                
                scnView.scene?.rootNode.addChildNode(arrowNode)
            }
        }
    }
    
    private func distanceBetween(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
        let dx = v1.x - v2.x
        let dy = v1.y - v2.y
        let dz = v1.z - v2.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}

// Extension to Equate Points for UI updates
extension TrackingPoint: Equatable {
    static func == (lhs: TrackingPoint, rhs: TrackingPoint) -> Bool {
        return lhs.id == rhs.id
    }
}
