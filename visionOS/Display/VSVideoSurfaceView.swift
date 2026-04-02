import AVFoundation
import SwiftUI
import Shared

#if os(visionOS)
import UIKit

public struct VSVideoSurfaceView: UIViewRepresentable {
    public let displayLayer: AVSampleBufferDisplayLayer

    public init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }

    public func makeUIView(context: Context) -> VSVideoSurfaceContainerView {
        let view = VSVideoSurfaceContainerView()
        view.configure(with: displayLayer)
        return view
    }

    public func updateUIView(_ uiView: VSVideoSurfaceContainerView, context: Context) {
        uiView.configure(with: displayLayer)
    }
}

public final class VSVideoSurfaceContainerView: UIView {
    private var hostedLayer: AVSampleBufferDisplayLayer?

    public override class var layerClass: AnyClass {
        CALayer.self
    }

    public func configure(with layer: AVSampleBufferDisplayLayer) {
        guard hostedLayer !== layer else { return }
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = layer
        layer.videoGravity = .resizeAspect
        self.layer.addSublayer(layer)
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }
}

#else
public struct VSVideoSurfaceView: View {
    public let displayLayer: AVSampleBufferDisplayLayer

    public init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }

    public var body: some View {
        Text("Video surface is only available on visionOS.")
            .foregroundStyle(.secondary)
    }
}
#endif
