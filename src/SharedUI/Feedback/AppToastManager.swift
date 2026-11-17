//
//  AppToastManager.swift
//  Tweetintosh
//
//  The app's one transient message, shown over whatever page is in front.
//

import SwiftUI

final class AppToastManager: ObservableObject {
    static let shared = AppToastManager()

    @Published var message: String = ""
    @Published var icon: String? = nil
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ text: String, icon: String? = nil, duration: Double = 2.4) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissWorkItem?.cancel()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                self.message = text
                self.icon = icon
            }

            let item = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.message = ""
                    self?.icon = nil
                }
            }
            self.dismissWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        }
    }
}
