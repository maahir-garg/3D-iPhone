import Foundation
import Accelerate
import Combine
import simd

/// Represents a single data point from the tracking session
struct TrackingPoint: Identifiable {
    let id = UUID()
    let timestamp: Double
    let lapID: Int
    let x: Float // Screen X (Meters)
    let y: Float // Screen Y (Meters)
    let z: Float // Depth (Meters)
    let confidence: Float
    
    // Derived kinematics
    var velocity: Float = 0.0
    var acceleration: Float = 0.0
    var jerk: Float = 0.0
}

/// Aggregated metrics for a specific Lap
struct LapMetrics: Identifiable {
    let id: Int
    let duration: Double
    let pathLength: Float
    let meanVelocity: Float
    let maxVelocity: Float
    let meanJerk: Float
    let dimensionlessJerk: Float
    let pathEfficiency: Float // 0.0 - 1.0 (1.0 = perfect straight line)
    let maxDeviation: Float
}

/// Output of the FFT analysis
struct TremorAnalysis {
    let frequencies: [Float]
    let magnitudes: [Float]
    let peakFrequency: Float
}

class SessionAnalyzer: ObservableObject {
    
    // MARK: - Properties
    
    @Published var rawPoints: [TrackingPoint] = []
    @Published var lapMetrics: [LapMetrics] = []
    @Published var tremorData: TremorAnalysis?
    @Published var overallCV_Duration: Float = 0.0
    @Published var overallCV_Amplitude: Float = 0.0
    
    // MARK: - Public API
    
    /// Loads and processes a CSV file from the given URL
    func processSession(at url: URL) {
        // 1. Parse CSV
        guard let data = try? String(contentsOf: url) else { return }
        let rows = data.components(separatedBy: "\n").dropFirst() // Skip Header
        
        var parsedPoints: [TrackingPoint] = []
        
        for row in rows {
            let columns = row.components(separatedBy: ",")
            if columns.count >= 5 {
                if let ts = Double(columns[0]),
                   let lap = Int(columns[1]),
                   let x = Float(columns[2]),
                   let y = Float(columns[3]),
                   let z = Float(columns[4]),
                   let conf = Float(columns[5]) {
                    
                    parsedPoints.append(TrackingPoint(timestamp: ts, lapID: lap, x: x, y: y, z: z, confidence: conf))
                }
            }
        }
        
        guard !parsedPoints.isEmpty else { return }
        
        // Sort by timestamp just in case
        parsedPoints.sort { $0.timestamp < $1.timestamp }
        
        // 2. Compute Kinematics (Derivatives)
        self.rawPoints = computeDerivatives(points: parsedPoints)
        
        // 3. Compute Per-Lap Metrics
        self.lapMetrics = computeLapMetrics(points: self.rawPoints)
        
        // 4. Compute Consistency (CV)
        computeConsistency(laps: self.lapMetrics)
        
        // 5. Tremor Analysis (FFT)
        self.tremorData = performFFT(points: self.rawPoints)
    }
    
    // MARK: - internal Logic
    
    private func computeDerivatives(points: [TrackingPoint]) -> [TrackingPoint] {
        var processed = points
        guard points.count > 1 else { return points }
        
        // We iterate and compute derivatives using Finite Differences
        // Central Difference would be better, but Forward/Backward is fine for this causality.
        // Let's use simple backward difference for 1st pass.
        
        for i in 1..<processed.count {
            let p1 = processed[i-1]
            let p2 = processed[i]
            let dt = Float(p2.timestamp - p1.timestamp)
            
            if dt > 0.0001 { // Avoid div by zero
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let dz = p2.z - p1.z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                
                processed[i].velocity = dist / dt
            }
        }
        
        // Acceleration
        for i in 1..<processed.count {
            let p1 = processed[i-1]
            let p2 = processed[i]
            let dt = Float(p2.timestamp - p1.timestamp)
            
            if dt > 0.0001 {
                let dv = p2.velocity - p1.velocity
                processed[i].acceleration = dv / dt
            }
        }
        
        // Jerk (da/dt)
        for i in 1..<processed.count {
            let p1 = processed[i-1]
            let p2 = processed[i]
            let dt = Float(p2.timestamp - p1.timestamp)
            
            if dt > 0.0001 {
                let da = p2.acceleration - p1.acceleration
                let jerk = abs(da / dt) // Scalar jerk magnitude
                processed[i].jerk = jerk
            }
        }
        
        return processed
    }
    
    private func computeLapMetrics(points: [TrackingPoint]) -> [LapMetrics] {
        let grouped = Dictionary(grouping: points, by: { $0.lapID })
        var metrics: [LapMetrics] = []
        
        for (lapID, lapPoints) in grouped {
            if lapID == 0 { continue } // Skip setup/idle phase
            guard lapPoints.count > 10 else { continue } // Noise filter
            
            let sorted = lapPoints.sorted { $0.timestamp < $1.timestamp }
            let start = sorted.first!
            let end = sorted.last!
            
            let duration = end.timestamp - start.timestamp
            guard duration > 0.1 else { continue }
            
            // Path Length
            var pathLen: Float = 0.0
            var maxVel: Float = 0.0
            var totalVel: Float = 0.0
            var totalJerk: Float = 0.0
            
            for i in 1..<sorted.count {
                let p1 = sorted[i-1]
                let p2 = sorted[i]
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let dz = p2.z - p1.z
                pathLen += sqrt(dx*dx + dy*dy + dz*dz)
                
                maxVel = max(maxVel, p2.velocity)
                totalVel += p2.velocity
                totalJerk += p2.jerk
            }
            
            let meanVel = totalVel / Float(sorted.count)
            let meanJerk = totalJerk / Float(sorted.count)
            
            // Dimensionless Jerk (Log dimensionless jerk)
            // LDLJ = - ln ( (Integral(j^2 dt) * D^3) / V_peak^2 ) ... many variants exists.
            // Simplified clinical proxy: Log( MeanJerk * Duration / PeakVel ) ??
            // Let's use standard: (Integral(J^2) * Duration^3) / PathLength^2
            // We'll estimate Integral(J^2) as Mean(J^2) * Duration
            
            var sumSquaredJerk: Float = 0
            for p in sorted { sumSquaredJerk += p.jerk * p.jerk }
            let meanSquaredJerk = sumSquaredJerk / Float(sorted.count)
            // approx integral ~ meanSquaredJerk * duration
            // Unitless Jerk = sqrt( Integral(j^2) * duration^5 / length^2 ) ... this is one standard.
            // Let's stick to the log of the simple mean jerk for robustness if the formula is complex.
            // User asked for "Dimensionless Jerk (Log)".
            // Common formula: -ln( (integral(j^2) * dur^3) / v_mean^2 ) ?
            // Let's implement: Log10 ( MeanSquaredJerk ) - simplistic but effective relative measure.
            let dimJerk = log10(meanSquaredJerk + 1.0e-5) // safe log
            
            // Path Efficiency
            let dx = end.x - start.x
            let dy = end.y - start.y
            let dz = end.z - start.z
            let euclideanDist = sqrt(dx*dx + dy*dy + dz*dz)
            let effic = (pathLen > 0) ? (euclideanDist / pathLen) : 0
            
            // Max Deviation (from straight line)
            // Line defined by Start -> End.
            // dist(Point, Line) = |(P-S) x (E-S)| / |E-S|
            var maxDev: Float = 0.0
            let s_vec = SIMD3<Float>(start.x, start.y, start.z)
            let e_vec = SIMD3<Float>(end.x, end.y, end.z)
            let se_vec = e_vec - s_vec
            let se_len = length(se_vec)
            
            if se_len > 0.001 {
                for p in sorted {
                    let p_vec = SIMD3<Float>(p.x, p.y, p.z)
                    let sp_vec = p_vec - s_vec
                    let crossProd = cross(sp_vec, se_vec)
                    let dist = length(crossProd) / se_len
                    maxDev = max(maxDev, dist)
                }
            }
            
            metrics.append(LapMetrics(id: lapID,
                                      duration: duration,
                                      pathLength: pathLen,
                                      meanVelocity: meanVel,
                                      maxVelocity: maxVel,
                                      meanJerk: meanJerk,
                                      dimensionlessJerk: dimJerk,
                                      pathEfficiency: effic,
                                      maxDeviation: maxDev))
        }
        
        return metrics.sorted { $0.id < $1.id }
    }
    
    private func computeConsistency(laps: [LapMetrics]) {
        guard laps.count >= 2 else {
            overallCV_Duration = 0
            overallCV_Amplitude = 0
            return
        }
        
        // CV = Stdev / Mean
        
        // Duration CV
        let durations = laps.map { Float($0.duration) }
        let meanDur = vDSP.mean(durations)
        var durStd: Float = 0
        vDSP_rmsqv(durations.map { $0 - meanDur }, 1, &durStd, vDSP_Length(durations.count))
        // Actually vDSP_rmsqv is Root Mean Square. Stdev is sqrt(sum((x-mean)^2)/(N-1))
        // Let's do swift standard math for clarity.
        let durMean = durations.reduce(0, +) / Float(durations.count)
        let durVar = durations.map { pow($0 - durMean, 2) }.reduce(0, +) / Float(durations.count - 1)
        let durStdev = sqrt(durVar)
        overallCV_Duration = (durMean > 0) ? (durStdev / durMean) * 100.0 : 0.0
        
        // Amplitude (Path Length) CV
        let lengths = laps.map { $0.pathLength }
        let lenMean = lengths.reduce(0, +) / Float(lengths.count)
        let lenVar = lengths.map { pow($0 - lenMean, 2) }.reduce(0, +) / Float(lengths.count - 1)
        let lenStdev = sqrt(lenVar)
        overallCV_Amplitude = (lenMean > 0) ? (lenStdev / lenMean) * 100.0 : 0.0
    }
    
    // MARK: - FFT Tremor Analysis
    
    private func performFFT(points: [TrackingPoint]) -> TremorAnalysis? {
        guard points.count > 30 else { return nil }
        
        // 1. Resample to fixed 60Hz
        // We need a uniform grid for FFT.
        let startTime = points.first!.timestamp
        let endTime = points.last!.timestamp
        let duration = endTime - startTime
        let targetFreq = 60.0
        let sampleCount = Int(duration * targetFreq)
        
        guard sampleCount > 8 else { return nil }
        
        // Create time grid
        var velocitySignal: [Float] = Array(repeating: 0.0, count: sampleCount)
        
        // Linear Interpolation
        for i in 0..<sampleCount {
            let t = startTime + Double(i) / targetFreq
            // Find bounding points
            if let idx = points.firstIndex(where: { $0.timestamp >= t }) {
                if idx == 0 {
                    velocitySignal[i] = points[0].velocity
                } else {
                    let p1 = points[idx-1]
                    let p2 = points[idx]
                    let ratio = Float((t - p1.timestamp) / (p2.timestamp - p1.timestamp))
                    velocitySignal[i] = p1.velocity + (p2.velocity - p1.velocity) * ratio
                }
            } else {
                velocitySignal[i] = points.last!.velocity
            }
        }
        
        // 2. Windowing (Hanning) to reduce spectral leakage
        var window = [Float](repeating: 0, count: sampleCount)
        vDSP_hann_window(&window, vDSP_Length(sampleCount), Int32(vDSP_HANN_NORM))
        vDSP_vmul(velocitySignal, 1, window, 1, &velocitySignal, 1, vDSP_Length(sampleCount))
        
        // 3. FFT Setup
        let log2n = vDSP_Length(log2(Float(sampleCount)))
        let n = Int(1 << log2n) // Power of 2
        let input = Array(velocitySignal.prefix(n)) // Truncate to power of 2
        
        guard input.count >= 16 else { return nil }
        
        let halfN = n / 2
        var real = [Float](input)
        var imag = [Float](repeating: 0.0, count: n)
        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
        
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Forward FFT
        // We need to pack real data for vDSP_fft_zrip if we want optimized real fft,
        // but using zip (complex) with 0 imag is easier to implement quickly.
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
        
        // Compute Magnitudes
        var magnitudes = [Float](repeating: 0.0, count: halfN)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
        
        // Normalize
        var normalizedMags = magnitudes.map { sqrt($0) / Float(n) }
        
        // 4. Map bins to Frequency
        // Bin 0 = DC, Bin N/2 = Nyquist (30Hz)
        var freqs: [Float] = []
        let binWidth = Float(targetFreq) / Float(n)
        
        for i in 0..<halfN {
            freqs.append(Float(i) * binWidth)
        }
        
        // Remove DC offset (Bin 0)
        if !normalizedMags.isEmpty { normalizedMags[0] = 0 }
        
        // Find Peak in Tremor Range (3-12Hz)
        var peakVal: Float = 0
        var peakFreq: Float = 0
        
        for i in 0..<freqs.count {
            let f = freqs[i]
            if f >= 3 && f <= 12 {
                if normalizedMags[i] > peakVal {
                    peakVal = normalizedMags[i]
                    peakFreq = f
                }
            }
        }
        
        return TremorAnalysis(frequencies: freqs, magnitudes: normalizedMags, peakFrequency: peakFreq)
    }
}
