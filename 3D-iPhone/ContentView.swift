import SwiftUI
import RealityKit
import Charts

struct ContentView: View {
    @StateObject private var trackingManager = TrackingManager()
    @State private var showShareSheet = false
    @State private var showDebugGraph = false
    @State private var chartData: [ChartPoint] = []
    
    // Config
    private let maxChartPoints = 300 // Keep last ~5 seconds at 60fps
    
    var body: some View {
        ZStack {
            // AR View (Full Screen)
            ARViewContainer(trackingManager: trackingManager)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay UI
            VStack {
                // Top Info Bar & Lap Counter
                HStack {
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
                        }
                    }
                    
                    Spacer()
                    
                    // Lap Counter Display
                    if trackingManager.isRecording {
                        VStack {
                            Text("Lap")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(trackingManager.currentLap)")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.4)) // Visual container for top bar
                .cornerRadius(15)
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // Debug Graph
                if showDebugGraph {
                    VStack(alignment: .leading) {
                        Text("Live Axis Data")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.leading)
                        
                        Chart(chartData) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(by: .value("Axis", point.axis))
                        }
                        .chartForegroundStyleScale([
                            "X": .red, "Y": .green, "Z": .blue
                        ])
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 150)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Bottom Controls
                HStack(spacing: 20) {
                    
                    // Toggle Debug
                    Button(action: {
                        withAnimation {
                            showDebugGraph.toggle()
                        }
                    }) {
                        VStack {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 24))
                            Text("Debug")
                                .font(.caption2)
                        }
                        .foregroundColor(showDebugGraph ? .yellow : .white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                    }
                    
                    if trackingManager.isRecording {
                        // Lap Control Button
                        Button(action: {
                            if trackingManager.currentLap == 0 {
                                trackingManager.startLap()
                            } else {
                                trackingManager.nextLap()
                            }
                        }) {
                            Text(trackingManager.currentLap == 0 ? "Start Lap 1" : "Next Lap")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(minWidth: 120)
                                .background(Color.orange)
                                .cornerRadius(30)
                        }
                    }
                    
                    // Record Button
                    Button(action: {
                        if trackingManager.isRecording {
                            trackingManager.stopRecording()
                            chartData = [] // Clear chart on stop
                        } else {
                            trackingManager.startRecording()
                            chartData = []
                        }
                    }) {
                        VStack {
                            Image(systemName: trackingManager.isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 50))
                                .foregroundColor(trackingManager.isRecording ? .red : .white)
                        }
                    }
                    
                    // Export Button
                    Button(action: {
                        showShareSheet = true
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24))
                            Text("Export")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .clipShape(Circle())
                    }
                    .disabled(trackingManager.isRecording)
                    .opacity(trackingManager.isRecording ? 0.5 : 1.0)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            trackingManager.startSession()
        }
        .onDisappear {
            trackingManager.pauseSession()
        }
        .onChange(of: trackingManager.currentPosition) { newPos in
            if showDebugGraph {
                updateChart(position: newPos)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = trackingManager.getExportURL() {
                ShareSheet(activityItems: [fileURL])
            } else {
                Text("No data to export.")
            }
        }
    }
    
    // MARK: - Chart Helper
    
    private func updateChart(position: SIMD3<Float>) {
        let now = Date()
        let pX = ChartPoint(timestamp: now, value: position.x, axis: "X")
        let pY = ChartPoint(timestamp: now, value: position.y, axis: "Y")
        let pZ = ChartPoint(timestamp: now, value: position.z, axis: "Z")
        
        var newPoints = [pX, pY, pZ]
        
        // Append
        chartData.append(contentsOf: newPoints)
        
        // Trim
        if chartData.count > maxChartPoints * 3 { // 3 points per frame
            chartData.removeFirst(3)
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
