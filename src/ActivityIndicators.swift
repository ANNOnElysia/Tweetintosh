//
//  ActivityIndicators.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI

struct GrowingArcIndicator: View {
    var color: Color = ThemeManager.accent
    var lineWidth: CGFloat = 2.0
    var size: CGFloat = 20.0
    
    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let angle = (time.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360.0
            
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle))
        }
    }
}

struct PulseWaveIndicator: View {
    var color: Color = ThemeManager.accent
    
    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    let offset = Double(index) * 0.2
                    let progress = (time + offset).truncatingRemainder(dividingBy: 0.8) / 0.8
                    let scale = 0.4 + 0.6 * sin(progress * .pi)
                    let opacity = 0.3 + 0.7 * sin(progress * .pi)
                    
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
        }
    }
}
