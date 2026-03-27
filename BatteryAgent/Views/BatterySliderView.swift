import SwiftUI

struct BatterySliderView: View {
    let currentCharge: Int
    @Binding var chargeLimit: Int
    let isCharging: Bool

    @State private var isDragging = false

    private let trackHeight: CGFloat = 28
    private let thumbSize: CGFloat = 22
    private let cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let limitFraction = CGFloat(chargeLimit) / 100.0

            ZStack(alignment: .leading) {
                // Track background (gray = right of thumb)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: trackHeight)

                // Active fill (blue/color = left of thumb, up to charge limit)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
                    .frame(width: max(0, trackWidth * limitFraction), height: trackHeight)

                // Current charge indicator (thin bright line inside the fill)
                if currentCharge < chargeLimit {
                    let chargeFraction = CGFloat(currentCharge) / 100.0
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 2, height: trackHeight - 4)
                        .offset(x: trackWidth * chargeFraction - 1)
                }

                // Draggable thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2, x: 0, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .offset(x: thumbOffset(trackWidth: trackWidth, limitFraction: limitFraction))
                    .animation(.easeOut(duration: 0.15), value: isDragging)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let newFraction = min(max(value.location.x / trackWidth, 0), 1)
                                let newLimit = Int(round(newFraction * 100))
                                chargeLimit = max(20, min(100, newLimit))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )

                // Always show charge limit
                Text("\(chargeLimit)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }

    private var fillColor: Color {
        if currentCharge <= 15 {
            return .red
        } else if currentCharge <= 30 {
            return .orange
        } else {
            return .blue
        }
    }

    private func thumbOffset(trackWidth: CGFloat, limitFraction: CGFloat) -> CGFloat {
        let rawX = trackWidth * limitFraction
        let halfThumb = thumbSize / 2
        return min(max(rawX - halfThumb, 0), trackWidth - thumbSize)
    }
}

#Preview {
    BatterySliderView(
        currentCharge: 65,
        chargeLimit: .constant(80),
        isCharging: false
    )
    .padding()
    .frame(width: 300)
}
