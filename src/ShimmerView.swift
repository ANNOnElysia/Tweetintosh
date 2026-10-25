//
//  ShimmerView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI

struct ShimmerModifier: ViewModifier {
    func body(content: Content) -> some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = CGFloat((time.truncatingRemainder(dividingBy: 1.2)) / 1.2) // 0.0 to 1.0
            
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.white.opacity(0.10), location: 0.42),
                                .init(color: Color.white.opacity(0.24), location: 0.5),
                                .init(color: Color.white.opacity(0.10), location: 0.58),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .rotationEffect(.degrees(20))
                        .offset(x: (progress * 2.0 - 1.0) * geo.size.width * 2)
                    }
                )
                .mask(content)
        }
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

// MARK: - Tweet Skeleton Placeholder View
struct TweetSkeletonRow: View {
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        let blockColor = theme.isLight ? Color.black.opacity(0.07) : Color(white: 0.13)
        let subtleColor = theme.isLight ? Color.black.opacity(0.05) : Color(white: 0.10)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar skeleton
                Circle()
                    .fill(blockColor)
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Header skeleton
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(blockColor)
                            .frame(width: 100, height: 14)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(subtleColor)
                            .frame(width: 70, height: 14)
                    }
                    
                    // Text body lines skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(blockColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(blockColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(subtleColor)
                        .frame(width: 180, height: 14)
                }
            }
            
            Divider()
                .background(ThemeManager.divider)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .shimmering()
    }
}
