import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var analyzer = SessionAnalyzer()
    let csvURL: URL
    
    @State private var selectedLapID: Int = -1 // -1 = All
    
    // Grid Layout for Metrics
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                
                // MARK: - Header
                VStack(spacing: 10) {
                    Text("Session Analysis")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Picker("Lap View", selection: $selectedLapID) {
                        Text("All Laps").tag(-1)
                        ForEach(analyzer.lapMetrics) { lap in
                            Text("Lap \(lap.id)").tag(lap.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                
                // MARK: - 3D Trajectory Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("3D Trajectory (Space-Time Cube)", systemImage: "cube.transparent")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Text("Z-Axis represents Time. Color represents Velocity (Plasma).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    TrajectorySceneView(points: filteredPoints, showArrows: selectedLapID == -1)
                        .frame(height: 350)
                        .cornerRadius(4)
                        .shadow(radius: 3)
                        .padding(.horizontal)
                }
                
                if selectedLapID == -1 {
                    // MARK: - Temporal Evolution Series (The "10 Charts")
                    Group {
                         Text("Temporal Evolution (Learning Curves)")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        // Row 1: Path Length & Duration
                        HStack {
                            SmallChartCard(title: "Path Length") {
                                Chart(analyzer.lapMetrics) { lap in
                                    AreaMark(x: .value("Lap", lap.id), y: .value("Meters", lap.pathLength))
                                        .foregroundStyle(Color(red: 0.18, green: 0.53, blue: 0.67).opacity(0.3)) // #2E86AB
                                    
                                    LineMark(x: .value("Lap", lap.id), y: .value("Meters", lap.pathLength))
                                        .foregroundStyle(Color(red: 0.18, green: 0.53, blue: 0.67))
                                        .symbol(Circle())
                                    
                                    if let trend = calculateTrend(for: analyzer.lapMetrics.map { $0.pathLength }) {
                                        LineMark(x: .value("Lap", lap.id), y: .value("Trend", trend[lap.id-1]))
                                            .foregroundStyle(.red)
                                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    }
                                }
                            }
                            SmallChartCard(title: "Duration") {
                                Chart(analyzer.lapMetrics) { lap in
                                    AreaMark(x: .value("Lap", lap.id), y: .value("Sec", lap.duration))
                                        .foregroundStyle(Color(red: 0.64, green: 0.23, blue: 0.45).opacity(0.3)) // #A23B72
                                    
                                    LineMark(x: .value("Lap", lap.id), y: .value("Sec", lap.duration))
                                        .foregroundStyle(Color(red: 0.64, green: 0.23, blue: 0.45))
                                        .symbol(Circle())
                                    
                                    if let trend = calculateTrend(for: analyzer.lapMetrics.map { Float($0.duration) }) {
                                        LineMark(x: .value("Lap", lap.id), y: .value("Trend", trend[lap.id-1]))
                                            .foregroundStyle(.red)
                                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Row 2: Efficiency & Velocity
                        HStack {
                            SmallChartCard(title: "Path Efficiency (%)") {
                                Chart(analyzer.lapMetrics) { lap in
                                    LineMark(x: .value("Lap", lap.id), y: .value("Eff", lap.pathEfficiency * 100))
                                        .foregroundStyle(Color(red: 0.95, green: 0.56, blue: 0.00)) // #F18F01
                                        .symbol(Circle())
                                    
                                    if let trend = calculateTrend(for: analyzer.lapMetrics.map { $0.pathEfficiency * 100 }) {
                                        LineMark(x: .value("Lap", lap.id), y: .value("Trend", trend[lap.id-1]))
                                            .foregroundStyle(.red)
                                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    }
                                }
                            }
                            SmallChartCard(title: "Mean Velocity") {
                                Chart(analyzer.lapMetrics) { lap in
                                    AreaMark(x: .value("Lap", lap.id), y: .value("Vel", lap.meanVelocity))
                                        .foregroundStyle(Color(red: 0.78, green: 0.24, blue: 0.11).opacity(0.3)) // #C73E1D
                                        
                                    LineMark(x: .value("Lap", lap.id), y: .value("Vel", lap.meanVelocity))
                                        .foregroundStyle(Color(red: 0.78, green: 0.24, blue: 0.11))
                                        .symbol(Circle())
                                    
                                    if let trend = calculateTrend(for: analyzer.lapMetrics.map { $0.meanVelocity }) {
                                        LineMark(x: .value("Lap", lap.id), y: .value("Trend", trend[lap.id-1]))
                                            .foregroundStyle(.red)
                                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Row 3: Deviation & Jerk
                        HStack {
                             SmallChartCard(title: "Max Deviation") {
                                Chart(analyzer.lapMetrics) { lap in
                                    BarMark(x: .value("Lap", lap.id), y: .value("Dev", lap.maxDeviation))
                                        .foregroundStyle(Color.gray.opacity(0.5))
                                }
                            }
                             SmallChartCard(title: "Smoothness (Log Jerk)") {
                                Chart(analyzer.lapMetrics) { lap in
                                    BarMark(x: .value("Lap", lap.id), y: .value("Jerk", lap.dimensionlessJerk))
                                        .foregroundStyle(Color.green.opacity(0.5))
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // MARK: - Detailed Consistency
                    VStack(alignment: .leading) {
                         Text("Consistency (CV Analysis)")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 15) {
                            MetricCard(title: "Time Consistency", value: String(format: "CV: %.1f%%", analyzer.overallCV_Duration), sub: "Lower is better", icon: "clock")
                            MetricCard(title: "Spatial Consistency", value: String(format: "CV: %.1f%%", analyzer.overallCV_Amplitude), sub: "Lower is better", icon: "ruler")
                        }
                        .padding(.horizontal)
                    }

                } else {
                    // Single Lap Details
                     VStack(alignment: .leading) {
                        Text("Lap \(selectedLapID) Details")
                           .font(.title3.bold())
                           .padding(.horizontal)
                           
                        if let lap = getSelectedLap() {
                             LazyVGrid(columns: columns, spacing: 15) {
                                MetricCard(title: "Duration", value: String(format: "%.2fs", lap.duration), sub: "", icon: "timer")
                                MetricCard(title: "Length", value: String(format: "%.2fm", lap.pathLength), sub: "", icon: "ruler")
                                MetricCard(title: "Max Vel", value: String(format: "%.2fm/s", lap.maxVelocity), sub: "", icon: "speedometer")
                                MetricCard(title: "Efficiency", value: String(format: "%.0f%%", lap.pathEfficiency*100), sub: "", icon: "percent")
                            }
                            .padding(.horizontal)
                            
                            ChartCard(title: "Velocity Profile (Time Series)") {
                                Chart(filteredPoints) { p in
                                    LineMark(x: .value("Time", p.timestamp - filteredPoints.first!.timestamp), y: .value("Velocity", p.velocity))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal)
                        }
                     }
                }
                
                // MARK: - Frequency Analysis (Always Visible)
                VStack(alignment: .leading) {
                    Label("Tremor Analysis (FFT)", systemImage: "waveform.path.ecg")
                        .font(.title3.bold())
                        .padding(.horizontal)
                    
                    if let tremor = analyzer.tremorData {
                        Chart {
                            ForEach(Array(zip(tremor.frequencies, tremor.magnitudes)), id: \.0) { (freq, mag) in
                                LineMark(x: .value("Hz", freq), y: .value("Power", mag))
                                    .foregroundStyle(.indigo)
                            }
                            RectangleMark(xStart: .value("L", 3), xEnd: .value("H", 12))
                                .foregroundStyle(.red.opacity(0.1))
                        }
                        .chartXScale(domain: 0...15)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 200)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            analyzer.processSession(at: csvURL)
        }
    }
    
    // MARK: - Helpers
    
    var filteredPoints: [TrackingPoint] {
        if selectedLapID == -1 {
            return analyzer.rawPoints
        } else {
            return analyzer.rawPoints.filter { $0.lapID == selectedLapID }
        }
    }
    
    func getSelectedLap() -> LapMetrics? {
        return analyzer.lapMetrics.first(where: { $0.id == selectedLapID })
    }
    
    // Simple Linear Regression for Trend Line
    func calculateTrend(for values: [Float]) -> [Float]? {
        guard values.count > 1 else { return nil }
        let n = Float(values.count)
        let x = Array(0..<Int(n)).map { Float($0) }
        let sumX = x.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(x, values).map(*).reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        return x.map { slope * $0 + intercept }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let sub: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2)
    }
}

struct SmallChartCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
            content
                .frame(height: 100)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2)
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
                .frame(height: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3)
    }
}
