import SwiftUI

/// Interactive logo on the idle screen — tap for a playful bounce easter egg.
struct LogoButton: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    @State private var tapCount = 0

    private let messages = [
        "Rawr!",
        "Drop a video, I dare you",
        "Paws & Play",
        "MacPlayer goes brrr",
        "Popcorn ready?",
    ]

    @State private var showMessage = false
    @State private var currentMessage = ""

    var body: some View {
        VStack(spacing: 6) {
            Image("MacPlayerLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                .onTapGesture {
                    tapCount += 1
                    currentMessage = messages[tapCount % messages.count]

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                        scale = 1.15
                        rotation = Double.random(in: -8...8)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            scale = 1.0
                            rotation = 0
                        }
                    }

                    withAnimation(.easeOut(duration: 0.15)) {
                        showMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            showMessage = false
                        }
                    }
                }

            if showMessage {
                Text(currentMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
