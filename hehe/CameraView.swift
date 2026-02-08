//
//  CameraView.swift
//  hehe
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var cameraManager: CameraManager
    @State private var showCapturedImage = false
    @State private var showExposureControls = false
    @State private var focusPoint: CGPoint? = nil
    @State private var isFocusing = false
    @State private var isAdjustingExposure = false
    @State private var exposureAdjustmentStartY: CGFloat = 0
    @State private var exposureAdjustmentValue: Float = 0
    
    init(cameraManager: CameraManager? = nil) {
        _cameraManager = StateObject(wrappedValue: cameraManager ?? CameraManager())
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if cameraManager.cameraPermissionGranted {
                CameraPreviewView(cameraManager: cameraManager, focusPoint: $focusPoint)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleExposureDrag(value: value)
                            }
                            .onEnded { _ in
                                isAdjustingExposure = false
                            }
                    )
                
                // Focus indicator overlay
                if let point = focusPoint {
                    focusIndicator()
                        .position(point)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Exposure adjustment indicator
                if isAdjustingExposure {
                    exposureAdjustmentIndicator
                }
                
                VStack {
                    Spacer()
                    
                    controlsOverlay
                }
                
                if let capturedImage = cameraManager.lastCapturedImage, showCapturedImage {
                    capturedImagePreview(image: capturedImage)
                }
            } else {
                permissionDeniedView
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: focusPoint) { newPoint in
            if newPoint != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFocusing = true
                }
            } else {
                isFocusing = false
            }
        }
    }
    
    private func handleExposureDrag(value: DragGesture.Value) {
        if !isAdjustingExposure {
            isAdjustingExposure = true
            exposureAdjustmentStartY = value.location.y
            exposureAdjustmentValue = cameraManager.exposureBias
        }
        
        // Calculate drag distance (negative because dragging up should increase exposure)
        let dragDistance = (exposureAdjustmentStartY - value.location.y) / 300
        let exposureStep: Float = 0.1
        let newBias = exposureAdjustmentValue + Float(dragDistance) * 3.0
        
        // Apply the new exposure bias
        let clampedBias = max(cameraManager.minExposureBias, min(cameraManager.maxExposureBias, newBias))
        cameraManager.setExposureBias(clampedBias)
    }
    
    private var exposureAdjustmentIndicator: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 24))
                .foregroundColor(.yellow)
            
            Text(String(format: "%.1f", cameraManager.exposureBias))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
        .position(x: UIScreen.main.bounds.width - 60, y: UIScreen.main.bounds.height / 2)
    }
    
    private func focusIndicator() -> some View {
        FocusIndicatorShape()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .scaleEffect(isFocusing ? 0.8 : 1.2)
            .animation(.easeInOut(duration: 0.3), value: isFocusing)
    }
    
    private var controlsOverlay: some View {
        VStack(spacing: 20) {
            // Exposure controls
            if showExposureControls {
                exposureControlView
                    .transition(.move(edge: .bottom))
            }
            
            // Lens selector
            if cameraManager.availableLenses.count > 1 {
                HStack(spacing: 20) {
                    ForEach(cameraManager.availableLenses) { lens in
                        Button(action: {
                            cameraManager.switchLens(to: lens)
                        }) {
                            Text(lens.label + "x")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospaced()
                                .foregroundColor(cameraManager.currentZoomLevel == lens.zoomLevel ? .black : .white)
                                .frame(width: 44, height: 44)
                                .background(
                                    cameraManager.currentZoomLevel == lens.zoomLevel
                                    ? Color.white
                                    : Color.white.opacity(0.2)
                                )
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            
            HStack(spacing: 60) {
                Button(action: {
                    showExposureControls.toggle()
                }) {
                    VStack(spacing: 4) {
                        Text(String(format: "EV %.1f", cameraManager.exposureBias))
                              .font(.subheadline)
                              .monospaced()
                              .fontWeight(.semibold)
                              .foregroundStyle(.yellow)
                    }
                    .foregroundColor(showExposureControls ? .black : .white)
                }
                
                Button(action: {
                    cameraManager.capturePhoto()
                    withAnimation {
                        showCapturedImage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            showCapturedImage = false
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)
                    }
                }
                
                Button(action: {
                    cameraManager.switchCamera()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    private var exposureControlView: some View {
        VStack(spacing: 15) {
            Text("Exposure")
                .font(.caption)
                .foregroundColor(.white)
            
            HStack {
                Button(action: {
                    let newBias = max(cameraManager.minExposureBias, cameraManager.exposureBias - 0.5)
                    cameraManager.setExposureBias(newBias)
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                
                Slider(
                    value: Binding(
                        get: { Double(cameraManager.exposureBias) },
                        set: { cameraManager.setExposureBias(Float($0)) }
                    ),
                    in: Double(cameraManager.minExposureBias)...Double(cameraManager.maxExposureBias),
                    step: 0.1
                )
                .tint(.white)
                .frame(width: 200)
                
                Button(action: {
                    let newBias = min(cameraManager.maxExposureBias, cameraManager.exposureBias + 0.5)
                    cameraManager.setExposureBias(newBias)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            
            Text(String(format: "%.1f EV", cameraManager.exposureBias))
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
    }
    
    private func capturedImagePreview(image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .padding()
                .overlay(
                    VStack {
                        Spacer()
                        Text("RAW Captured")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .padding(.bottom, 20)
                    }
                )
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please enable camera access in Settings to capture RAW photos.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Open Settings")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

// Shape for focus indicator with brackets and crosshair
struct FocusIndicatorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        // Adjust Y to account for safe area - draw higher up
        let centerY = rect.midY - 80
        let bracketSize: CGFloat = 60
        let bracketLength: CGFloat = 20
        let halfBracket = bracketSize / 2
        let crosshairLength: CGFloat = 6
        
        // Top left corner bracket
        path.move(to: CGPoint(x: centerX - halfBracket, y: centerY - halfBracket))
        path.addLine(to: CGPoint(x: centerX - halfBracket + bracketLength, y: centerY - halfBracket))
        path.move(to: CGPoint(x: centerX - halfBracket, y: centerY - halfBracket))
        path.addLine(to: CGPoint(x: centerX - halfBracket, y: centerY - halfBracket + bracketLength))
        
        // Top right corner bracket
        path.move(to: CGPoint(x: centerX + halfBracket - bracketLength, y: centerY - halfBracket))
        path.addLine(to: CGPoint(x: centerX + halfBracket, y: centerY - halfBracket))
        path.move(to: CGPoint(x: centerX + halfBracket, y: centerY - halfBracket))
        path.addLine(to: CGPoint(x: centerX + halfBracket, y: centerY - halfBracket + bracketLength))
        
        // Bottom left corner bracket
        path.move(to: CGPoint(x: centerX - halfBracket, y: centerY + halfBracket))
        path.addLine(to: CGPoint(x: centerX - halfBracket + bracketLength, y: centerY + halfBracket))
        path.move(to: CGPoint(x: centerX - halfBracket, y: centerY + halfBracket - bracketLength))
        path.addLine(to: CGPoint(x: centerX - halfBracket, y: centerY + halfBracket))
        
        // Bottom right corner bracket
        path.move(to: CGPoint(x: centerX + halfBracket - bracketLength, y: centerY + halfBracket))
        path.addLine(to: CGPoint(x: centerX + halfBracket, y: centerY + halfBracket))
        path.move(to: CGPoint(x: centerX + halfBracket, y: centerY + halfBracket - bracketLength))
        path.addLine(to: CGPoint(x: centerX + halfBracket, y: centerY + halfBracket))
        
        // Center crosshair - horizontal
        path.move(to: CGPoint(x: centerX - crosshairLength, y: centerY))
        path.addLine(to: CGPoint(x: centerX + crosshairLength, y: centerY))
        
        // Center crosshair - vertical
        path.move(to: CGPoint(x: centerX, y: centerY - crosshairLength))
        path.addLine(to: CGPoint(x: centerX, y: centerY + crosshairLength))
        
        return path
    }
}

class PreviewCameraManager: CameraManager {
    override init() {
        super.init()
        // Override to show camera UI in preview without real camera hardware
        self.cameraPermissionGranted = true
        self.availableLenses = [
            Lens(deviceType: .builtInUltraWideCamera, label: "0.5", zoomLevel: 0.5),
            Lens(deviceType: .builtInWideAngleCamera, label: "1", zoomLevel: 1.0),
            Lens(deviceType: .builtInTelephotoCamera, label: "3", zoomLevel: 3.0)
        ]
        self.currentZoomLevel = 1.0
        self.exposureBias = 0.0
        self.minExposureBias = -8.0
        self.maxExposureBias = 8.0
    }
}

#Preview("Camera View - UI Preview") {
    CameraView(cameraManager: PreviewCameraManager())
}
