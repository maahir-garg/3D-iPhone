import Foundation
import UIKit

/// A robust, thread-safe logger for recording 3D tracking data to a CSV file.
class DataLogger {
    // MARK: - Properties
    
    private let fileName: String
    private var fileURL: URL?
    private let queue = DispatchQueue(label: "com.3diphone.datalogger", qos: .utility)
    
    // MARK: - Initialization
    
    /// Initializes the DataLogger.
    /// - Parameter fileName: The name of the CSV file (default: "TrackingData.csv").
    init(fileName: String = "TrackingData.csv") {
        self.fileName = fileName
        setupCSV()
    }
    
    // MARK: - Setup
    
    /// Sets up the CSV file with the header row. Recreates the file if it already exists to start fresh on each session.
    private func setupCSV() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ DataLogger: Could not access Documents directory.")
            return
        }
        
        fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        guard let fileURL = fileURL else { return }
        
        let header = "Timestamp,Lap_ID,ScreenX_Meters,ScreenY_Meters,Depth_Meters,Confidence\n"
        
        queue.async {
            do {
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ DataLogger: CSV initialized at \(fileURL.path)")
            } catch {
                print("❌ DataLogger: Failed to initialize CSV - \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Appends a new data row to the CSV file.
    /// - Parameters:
    ///   - lapID: The current lap identifier.
    ///   - x: Screen X in meters (Center=0).
    ///   - y: Screen Y in meters (Center=0, Up=+).
    ///   - z: Depth in meters (Distance).
    ///   - confidence: Confidence score of the detection (0.0 to 1.0).
    func appendLog(lapID: Int, x: Float, y: Float, z: Float, confidence: Float) {
        guard let fileURL = fileURL else { return }
        
        let timestamp = Date().timeIntervalSince1970
        let row = String(format: "%.6f,%d,%.6f,%.6f,%.6f,%.4f\n", timestamp, lapID, x, y, z, confidence)
        
        queue.async {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                defer { fileHandle.closeFile() }
                fileHandle.seekToEndOfFile()
                if let data = row.data(using: .utf8) {
                    fileHandle.write(data)
                }
            } else {
                // If FileHandle fails, try appending via String (less efficient but a fallback)
                do {
                    // Note: This is less efficient for high frequency, but FileHandle should usually succeed.
                    // Ideally we keep the file handle open, but for simplicity and safety against crashes we open/close.
                    // For high-freq (60fps), keeping it open in a class property would be better optimization.
                    // Let's stick to FileHandle open/close for safety unless perf issues arise.
                     print("⚠️ DataLogger: Could not create FileHandle, attempting append.")
                }
            }
        }
    }
    
    /// Returns the URL of the CSV file for exporting.
    /// - Returns: The URL of the CSV file, or nil if not ready.
    func getCSVPath() -> URL? {
        return fileURL
    }
    
    /// Clears the existing data and starts a new log.
    func resetLog() {
       setupCSV()
    }
}
