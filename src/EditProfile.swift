//
//  EditProfile.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Editing your own profile, as X's Edit profile sheet does: the header image, the photo, name, bio, location and
//  website, with X's own limits. Changes are sent only when Save is pressed, and only the parts that changed.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

final class EditProfileModel: ObservableObject {
    // X's limits, which it enforces on the server too
    static let nameLimit = 50
    static let bioLimit = 160
    static let locationLimit = 30
    static let websiteLimit = 100

    @Published var name: String
    @Published var bio: String
    @Published var location: String
    @Published var website: String
    // New images picked here, already cropped and sized, with a preview
    @Published private(set) var newPhoto: (jpeg: Data, preview: NSImage)?
    @Published private(set) var newHeader: (jpeg: Data, preview: NSImage)?
    @Published private(set) var isSaving = false

    let original: (name: String, bio: String, location: String, website: String)
    let photoUrl: String?
    let headerUrl: String?

    init(profile: UserProfile) {
        let user = profile.user
        // X keeps the bio with its links shortened to t.co; the reader wrote, and expects to edit, the real addresses
        var bio = user.bio ?? ""
        for link in user.bioLinks ?? [] where !link.url.isEmpty {
            bio = bio.replacingOccurrences(of: link.url, with: link.expandedUrl)
        }
        let website = profile.websiteUrl?.absoluteString ?? ""
        original = (user.name, bio, user.location ?? "", website)
        name = user.name
        self.bio = bio
        location = user.location ?? ""
        self.website = website
        photoUrl = user.avatarUrl?.replacingOccurrences(of: "_bigger", with: "_400x400")
        headerUrl = user.bannerUrl.map { $0 + "/1500x500" }
    }

    var textChanged: Bool {
        name != original.name || bio != original.bio || location != original.location || website != original.website
    }

    var hasChanges: Bool { textChanged || newPhoto != nil || newHeader != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= Self.nameLimit && bio.count <= Self.bioLimit
            && location.count <= Self.locationLimit && website.count <= Self.websiteLimit
    }

    func pickPhoto() {
        pickImage(size: CGSize(width: 400, height: 400)) { [weak self] in self?.newPhoto = $0 }
    }

    func pickHeader() {
        pickImage(size: CGSize(width: 1500, height: 500)) { [weak self] in self?.newHeader = $0 }
    }

    // Images are cropped to the shape X shows them in, from the middle, and sent at the size X stores
    private func pickImage(size: CGSize, apply: @escaping ((jpeg: Data, preview: NSImage)) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
                  let result = Self.cropped(image, to: size) else { return }
            apply(result)
        }
    }

    static func cropped(_ image: NSImage, to size: CGSize) -> (jpeg: Data, preview: NSImage)? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(source.width), height = CGFloat(source.height)
        let scale = max(size.width / width, size.height / height)
        let drawn = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(origin: origin, size: drawn))
        guard let output = ctx.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: output).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        else { return nil }
        return (jpeg, NSImage(cgImage: output, size: size))
    }

    // Images first, then the text, so a refused image doesn't leave half an edit behind it unnoticed
    func save(completion: @escaping (Bool) -> Void) {
        guard hasChanges, isValid, !isSaving else { return }
        isSaving = true
        var steps: [(@escaping (Result<Void, APIError>) -> Void) -> Void] = []
        if let photo = newPhoto { steps.append { APIClient.shared.updateProfileImage(photo.jpeg, completion: $0) } }
        if let header = newHeader { steps.append { APIClient.shared.updateProfileBanner(header.jpeg, completion: $0) } }
        if textChanged {
            let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let (bio, location, website) = (self.bio, self.location, self.website.trimmingCharacters(in: .whitespacesAndNewlines))
            steps.append { APIClient.shared.updateProfile(name: name, bio: bio, location: location, website: website, completion: $0) }
        }
        run(steps, completion: completion)
    }

    private func run(_ steps: [(@escaping (Result<Void, APIError>) -> Void) -> Void], completion: @escaping (Bool) -> Void) {
        guard let step = steps.first else {
            isSaving = false
            AppToastManager.shared.show(LocalizationManager.shared.t("edit_profile_saved"), icon: "checkmark.circle.fill")
            completion(true)
            return
        }
        step { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.run(Array(steps.dropFirst()), completion: completion)
                case .failure(let error):
                    self.isSaving = false
                    EngagementGuard.reportFailure(error)
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Sheet

struct EditProfileView: View {
    let onSaved: () -> Void
    @StateObject private var model: EditProfileModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    init(profile: UserProfile, onSaved: @escaping () -> Void) {
        _model = StateObject(wrappedValue: EditProfileModel(profile: profile))
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(loc.t("edit_profile"))
                .font(theme.appFont(size: 15, weight: .semibold))
                .foregroundColor(ThemeManager.primaryText)
                .padding(.top, 18)
                .padding(.bottom, 14)

            images
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 14) {
                field(loc.t("edit_profile_name"), text: $model.name, limit: EditProfileModel.nameLimit)
                bioField
                field(loc.t("edit_profile_location"), text: $model.location, limit: EditProfileModel.locationLimit)
                field(loc.t("edit_profile_website"), text: $model.website, limit: EditProfileModel.websiteLimit)
            }
            .padding(.horizontal, 22)
            .padding(.top, 56)

            Spacer(minLength: 16)

            HStack {
                if model.isSaving {
                    LoadingIndicator(compactHeight: 18)
                }
                Spacer()
                Button(loc.t("cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSaving)
                Button {
                    model.save { saved in
                        guard saved else { return }
                        onSaved()
                        dismiss()
                    }
                } label: {
                    Text(loc.t("save")).foregroundStyle(ThemeManager.onAccent)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(ThemeManager.accent)
                .disabled(!model.hasChanges || !model.isValid || model.isSaving)
            }
            .controlSize(.large)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(width: 520, height: 640)
        .background(ThemeManager.background)
    }

    // The header with the photo over its lower edge, each with a button to replace it
    private var images: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let header = model.newHeader {
                    Image(nsImage: header.preview).resizable().aspectRatio(contentMode: .fill)
                } else if let url = model.headerUrl {
                    CachedAsyncImage(urlString: url, placeholderColor: ThemeManager.cardBackground, targetSize: CGSize(width: 476, height: 159))
                } else {
                    ThemeManager.accent.opacity(0.25)
                }
            }
            .frame(height: 159)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .center) { changeButton("edit_profile_change_header", action: model.pickHeader) }

            Group {
                if let photo = model.newPhoto {
                    Image(nsImage: photo.preview).resizable()
                } else {
                    CachedAsyncImage(urlString: model.photoUrl, targetSize: CGSize(width: 96, height: 96))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(ThemeManager.background, lineWidth: 4))
            .overlay { changeButton("edit_profile_change_photo", action: model.pickPhoto, compact: true) }
            .offset(x: 16, y: 48)
        }
    }

    private func changeButton(_ key: String, action: @escaping () -> Void, compact: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: "camera")
                .font(.system(size: compact ? 15 : 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: compact ? 36 : 42, height: compact ? 36 : 42)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.target)
        .help(loc.t(key))
        .accessibilityLabel(loc.t(key))
        .disabled(model.isSaving)
    }

    private func field(_ title: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(theme.appFont(size: 12, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                Spacer()
                counter(text.wrappedValue.count, limit: limit)
            }
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(theme.appFont(size: 13))
                .disabled(model.isSaving)
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(loc.t("edit_profile_bio"))
                    .font(theme.appFont(size: 12, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                Spacer()
                counter(model.bio.count, limit: EditProfileModel.bioLimit)
            }
            TextEditor(text: $model.bio)
                .font(theme.appFont(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 6).fill(ThemeManager.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ThemeManager.border, lineWidth: 0.6))
                .disabled(model.isSaving)
        }
    }

    // Shown in red once the text is over X's limit, which also turns Save off
    private func counter(_ count: Int, limit: Int) -> some View {
        Text("\(count)/\(limit)")
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(count > limit ? Color(nsColor: .systemRed) : ThemeManager.tertiaryText)
    }
}
