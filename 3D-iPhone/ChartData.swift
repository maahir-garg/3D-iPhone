import Foundation
import Charts

/// Represents a single data point for the 3D coordinate chart.
struct ChartPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Float
    let axis: String // "X", "Y", or "Z"
}
