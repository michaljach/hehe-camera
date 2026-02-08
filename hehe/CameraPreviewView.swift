//
//  CameraPreviewView.swift
//  hehe
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    @Binding var focusPoint: CGPoint?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.isUserInteractionEnabled = true
        
        if let previewLayer = cameraManager.getPreviewLayer() {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
        
        context.coordinator.previewView = uiView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(cameraManager: cameraManager, focusPoint: $focusPoint)
    }
    
    class Coordinator: NSObject {
        let cameraManager: CameraManager
        @Binding var focusPoint: CGPoint?
        weak var previewView: UIView?
        var focusTimer: Timer?
        
        init(cameraManager: CameraManager, focusPoint: Binding<CGPoint?>) {
            self.cameraManager = cameraManager
            self._focusPoint = focusPoint
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: previewView)
            
            // Convert to camera coordinates (0.0 - 1.0)
            guard let previewView = previewView else { return }
            let bounds = previewView.bounds
            
            let focusX = location.y / bounds.height
            let focusY = 1.0 - (location.x / bounds.width)
            
            let pointOfInterest = CGPoint(x: focusX, y: focusY)
            
            // Cancel any existing timer
            focusTimer?.invalidate()
            
            // Reset focus point to nil first to trigger animation reset
            DispatchQueue.main.async {
                self.focusPoint = nil
            }
            
            // Small delay then set new focus point to trigger fresh animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.focusPoint = location
            }
            
            // Perform focus
            cameraManager.focus(at: pointOfInterest)
            
            // Clear focus point after animation
            focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.focusPoint = nil
                }
            }
        }
    }
}

#Preview("Camera Preview") {
    // Preview shows placeholder since CameraManager requires actual camera hardware
    Text("Camera Preview View")
        .font(.title)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
