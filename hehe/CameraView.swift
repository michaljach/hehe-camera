//
//  CameraView.swift
//  hehe
//

import SwiftUI

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showCapturedImage = false
    @State private var showExposureControls = false
    @State private var focusPoint: CGPoint? = nil
    @State private var isFocusing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if cameraManager.cameraPermissionGranted {
                CameraPreviewView(cameraManager: cameraManager, focusPoint: $focusPoint)
                    .ignoresSafeArea()
                
                // Focus indicator overlay
                if let point = focusPoint {
                    focusIndicator(at: point)
                        .transition(.scale.combined(with: .opacity))
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
    
    private func focusIndicator(at point: CGPoint) -> some View {
        ZStack {
            // Outer bracket - top left
            Path { path in
                let size: CGFloat = 60
                let bracketLength: CGFloat = 20
                
                // Top horizontal
                path.move(to: CGPoint(x: point.x - size/2, y: point.y - size/2))
                path.addLine(to: CGPoint(x: point.x - size/2 + bracketLength, y: point.y - size/2))
                
                // Top vertical
                path.move(to: CGPoint(x: point.x - size/2, y: point.y - size/2))
                path.addLine(to: CGPoint(x: point.x - size/2, y: point.y - size/2 + bracketLength))
                
                // Top right horizontal
                path.move(to: CGPoint(x: point.x + size/2 - bracketLength, y: point.y - size/2))
                path.addLine(to: CGPoint(x: point.x + size/2, y: point.y - size/2))
                
                // Top right vertical
                path.move(to: CGPoint(x: point.x + size/2, y: point.y - size/2))
                path.addLine(to: CGPoint(x: point.x + size/2, y: point.y - size/2 + bracketLength))
                
                // Bottom left horizontal
                path.move(to: CGPoint(x: point.x - size/2, y: point.y + size/2))
                path.addLine(to: CGPoint(x: point.x - size/2 + bracketLength, y: point.y + size/2))
                
                // Bottom left vertical
                path.move(to: CGPoint(x: point.x - size/2, y: point.y + size/2 - bracketLength))
                path.addLine(to: CGPoint(x: point.x - size/2, y: point.y + size/2))
                
                // Bottom right horizontal
                path.move(to: CGPoint(x: point.x + size/2 - bracketLength, y: point.y + size/2))
                path.addLine(to: CGPoint(x: point.x + size/2, y: point.y + size/2))
                
                // Bottom right vertical
                path.move(to: CGPoint(x: point.x + size/2, y: point.y + size/2 - bracketLength))
                path.addLine(to: CGPoint(x: point.x + size/2, y: point.y + size/2))
            }
            .stroke(Color.yellow, lineWidth: 2)
            
            // Center crosshair
            Plus()
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 12, height: 12)
        }
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
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(cameraManager.currentZoomLevel == lens.zoomLevel ? .black : .white)
                                .frame(width: 50, height: 50)
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
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 20))
                        Text(String(format: "%.1f", cameraManager.exposureBias))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(showExposureControls ? .black : .white)
                    .frame(width: 50, height: 50)
                    .background(showExposureControls ? Color.white : Color.white.opacity(0.2))
                    .clipShape(Circle())
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
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.6), .clear]),
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        )
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

// Shape for focus indicator crosshair
struct Plus: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let centerY = rect.midY
        let length = min(rect.width, rect.height) / 2
        
        // Horizontal line
        path.move(to: CGPoint(x: centerX - length, y: centerY))
        path.addLine(to: CGPoint(x: centerX + length, y: centerY))
        
        // Vertical line
        path.move(to: CGPoint(x: centerX, y: centerY - length))
        path.addLine(to: CGPoint(x: centerX, y: centerY + length))
        
        return path
    }
}

#Preview {
    CameraView()
}
