import SwiftUI
import RealityKit

struct ContentView: View {
    @StateObject private var trackingManager = TrackingManager()
    @State private var showShareSheet = false
    
    var body: some View {
        ZStack {
            // AR View (Full Screen)
            ARViewContainer(trackingManager: trackingManager)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay UI
            VStack {
                // Top Info Bar
                VStack(alignment: .leading, spacing: 5) {
                    Text("3D Finger Tracking")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(trackingManager.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(getStatusColor())
                    
                    if trackingManager.confidence > 0 {
                        Text("X: \(String(format: "%.3f", trackingManager.currentPosition.x)) m")
                        Text("Y: \(String(format: "%.3f", trackingManager.currentPosition.y)) m")
                        Text("Z: \(String(format: "%.3f", trackingManager.currentPosition.z)) m")
                        Text("Conf: \(String(format: "%.0f%%", trackingManager.confidence * 100))")
                    } else {
                        Text("No Hand Detected")
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
                .foregroundColor(.white)
                .padding(.top, 50)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal)
                
                Spacer()
                
                // Bottom Controls
                HStack(spacing: 30) {
                    // Record Button
                    Button(action: {
                        if trackingManager.isRecording {
                            trackingManager.stopRecording()
                        } else {
                            trackingManager.startRecording()
                        }
                    }) {
                        VStack {
                            Image(systemName: trackingManager.isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 60))
                                .foregroundColor(trackingManager.isRecording ? .red : .white)
                            Text(trackingManager.isRecording ? "Stop" : "Record")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                    
                    // Export Button
                    Button(action: {
                        showShareSheet = true
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 30))
                                .padding(15)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .foregroundColor(.white)
                            Text("Export CSV")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                    .disabled(trackingManager.isRecording)
                    .opacity(trackingManager.isRecording ? 0.5 : 1.0)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            trackingManager.startSession()
        }
        .onDisappear {
            trackingManager.pauseSession()
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = trackingManager.getExportURL() {
                ShareSheet(activityItems: [fileURL])
            } else {
                Text("No data to export.")
            }
        }
    }
    
    private func getStatusColor() -> Color {
        if trackingManager.isRecording {
            return .red
        }
        if trackingManager.confidence > 0.3 {
            return .green
        }
        return .yellow
    }
}

// MARK: - Helper Views

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
