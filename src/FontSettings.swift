//
//  FontSettings.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The font-family chooser and its specimen, kept apart from the rest of Settings so typing in the filter does not
//  redraw the 480 × 860 page. Families are read when the chooser opens: a Mac may have hundreds, and most are never
//  looked at.
//

import AppKit
import SwiftUI

/// The families installed for the current user, as Font Book sees them.
enum InstalledFonts {
    struct Family: Identifiable, Equatable, Sendable {
        let name: String
        let displayName: String

        var id: String { name }
    }

    static func families() -> [Family] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies
            .map { Family(name: $0, displayName: manager.localizedName(forFamily: $0, face: nil)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Fills NSFontManager's cache before the chooser opens. The first enumeration costs about 110 ms on a Mac with
    /// a few hundred families; doing it here keeps that cost off the main thread when the popover appears.
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool { _ = families() }
        }
    }

    /// The family's regular face, used to record which font the reader picked and to check that it is still installed.
    static func baseFont(forFamily family: String) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)
    }
}

struct FontFamilyPickerPopover: View {
    let selectedFamily: String?
    let onPick: (InstalledFonts.Family) -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var query = ""
    @State private var families: [InstalledFonts.Family] = []
    @State private var isLoading = true

    var body: some View {
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = filter.isEmpty
            ? families
            : families.filter {
                $0.displayName.localizedCaseInsensitiveContains(filter)
                    || $0.name.localizedCaseInsensitiveContains(filter)
            }

        VStack(spacing: 0) {
            TextField(loc.t("font_search_placeholder"), text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .padding(8)

            Divider()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text(loc.t("font_no_results"))
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { family in
                    row(family)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 36)
            }
        }
        .frame(width: 300, height: 320)
        .task {
            if families.isEmpty {
                families = await Task.detached(priority: .userInitiated) {
                    InstalledFonts.families()
                }.value
            }
            isLoading = false
        }
    }

    private func row(_ family: InstalledFonts.Family) -> some View {
        Button {
            onPick(family)
        } label: {
            HStack(spacing: 6) {
                Group {
                    if family.name == selectedFamily {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(ThemeManager.accent)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 12, height: 12)

                Text(family.displayName)
                    // The name stays in the system font: a script face would make the list itself hard to scan.
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        // The row is already a full-width, 36-point target. .target would add a geometry pass to every one of the
        // hundreds of rows just to learn a size it does not need.
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .frame(height: 36)
    }
}

struct FontPreviewCard: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc.t("font_preview_title"))
                .font(theme.appFont(size: 15, weight: .semibold))
                .foregroundColor(ThemeManager.primaryText)

            Text(loc.t("font_preview_body"))
                .font(theme.tweetFont(size: 12.5))
                .lineSpacing(theme.lineSpacing())
                .foregroundColor(ThemeManager.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(loc.t("font_preview_meta"))
                .font(theme.appFont(size: 10.5))
                .foregroundColor(ThemeManager.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ThemeManager.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ThemeManager.border, lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
    }
}
