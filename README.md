# 3D-iPhone

An iOS app that tracks a fingertip with the iPhone camera and records its position over time. It is the iPhone side of a hand and eye tracking project built at the Interactive 3D Design Lab at the National University of Singapore (May to December 2025), aimed at stroke-rehabilitation assessment and done in collaboration with Apple.

Status: research prototype, not maintained here.

## What the app does

- Runs an ARKit world-tracking session and shows the camera feed in a RealityKit `ARView`.
- Runs a Vision hand-pose request on camera frames and reads the index fingertip.
- Shows the current X, Y and Z position, a status message and a live chart of the three axes.
- Records positions to a CSV file in the app's Documents directory, with a lap counter that the user advances by hand.
- Exports the CSV through the iOS share sheet.
- Opens a dashboard for the recorded session, with charts and a SceneKit 3D view of the trajectory.

## Requirements

- Xcode with an iOS 26.1 SDK. The deployment target in the project file is iOS 26.1.
- An iPhone or iPad that supports ARKit (`arkit` is listed under required device capabilities). The simulator has no camera, so run on a device.
- Scene depth data. The code requests it when the device supports it, and position calculation returns nothing without a depth map.
- Camera permission, requested on first launch.
- Swift 5 language mode. The Charts, SceneKit and Accelerate frameworks come with the SDK; there are no third-party dependencies.

## Run it

1. Open `3D-iPhone.xcodeproj` in Xcode.
2. Select the `3D-iPhone` target and set your own team under Signing & Capabilities. The project file contains the original author's team and bundle identifier.
3. Choose a connected device and run.

## Layout

- `3D-iPhone/TrackingManager.swift`: ARKit session, Vision request and position output.
- `3D-iPhone/DataLogger.swift`: CSV logging.
- `3D-iPhone/ContentView.swift`: main screen and controls.
- `3D-iPhone/ARViewContainer.swift`: SwiftUI wrapper for `ARView`.
- `3D-iPhone/SessionAnalyzer.swift`, `DashboardView.swift`, `ChartData.swift`: loading and charting a recorded session.
- `3D-iPhone/TrajectorySceneView.swift`: SceneKit trajectory view.
- `3D-iPhone/AppDelegate.swift`, `SceneDelegate.swift`: app lifecycle.
- `3D-iPhone/Test/advanced_visualization.py`: standalone matplotlib script that plots a JSON file. It is not part of the Xcode target.
- `3D-iPhoneTests/`, `3D-iPhoneUITests/`: Xcode template test targets.

## Credits

The Swift source files in this repository carry no third-party copyright or licence headers.
