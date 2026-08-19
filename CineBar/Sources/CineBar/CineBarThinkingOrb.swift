import SwiftUI

/// 思考球体（对标 orbs.jakubantalik.com ThinkingOrb，2026-08-19）：
/// 三条 3D 轨道粒子旋转 + 中心核脉动，透明背景，用于 CineAI 思考、播放解析等加载场景。
struct CineBarThinkingOrb: View {
    var size: CGFloat = 40
    var accent: Color = .orange

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.35), lineWidth: 1.2)
                    Circle()
                        .fill(accent)
                        .frame(width: max(size * 0.12, 3), height: max(size * 0.12, 3))
                        .shadow(color: accent.opacity(0.7), radius: 3)
                        .offset(y: -size / 2)
                }
                .frame(width: size, height: size)
                .rotation3DEffect(.degrees(70), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(Double(i) * 45), axis: (x: 0, y: 0, z: 1))
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(
                    .linear(duration: [3.0, 2.2, 4.0][i]).repeatForever(autoreverses: false),
                    value: rotate
                )
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.9), accent.opacity(0.15)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.3
                    )
                )
                .frame(width: size * 0.34, height: size * 0.34)
                .scaleEffect(pulse ? 1.12 : 1.0)
                .opacity(pulse ? 1.0 : 0.72)
                .animation(
                    .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
        .frame(width: size, height: size)
        .onAppear {
            rotate = true
            pulse = true
        }
    }

    @State private var rotate = false
    @State private var pulse = false
}
