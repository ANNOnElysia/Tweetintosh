//
//  SearchSuggestions.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Suggestions under the top-bar search field: live typeahead (topics and people) from X while you type,
//  and recent searches when the field is empty.
//

import SwiftUI
import AppKit

// MARK: - Recent Searches

// Kept on this Mac only
final class SearchRecents {
    static let shared = SearchRecents()

    private let key = "Tweetintosh_RecentSearches"
    private let limit = 8

    var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = all.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    func remove(_ query: String) {
        UserDefaults.standard.set(all.filter { $0 != query }, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Typeahead API

struct TypeaheadResult {
    var topics: [String]
    var users: [TweetUser]
}

extension APIClient {
    func fetchTypeahead(query: String, completion: @escaping (Result<TypeaheadResult, APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        var comp = URLComponents(string: "https://x.com/i/api/1.1/search/typeahead.json")!
        comp.queryItems = [
            URLQueryItem(name: "include_ext_is_blue_verified", value: "1"),
            URLQueryItem(name: "include_ext_verified_type", value: "1"),
            URLQueryItem(name: "include_ext_profile_image_shape", value: "1"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "src", value: "search_box"),
            URLQueryItem(name: "result_type", value: "events,users,topics")
        ]
        guard let url = comp.url else { completion(.failure(.invalidResponse)); return }

        session.dataTask(with: authorizedRequest(url, method: "GET", creds: creds)) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.serverError(Self.errorMessage(from: data) ?? "HTTP \(status)")))
                return
            }

            let users: [TweetUser] = ((json["users"] as? [[String: Any]]) ?? []).compactMap { u in
                guard let id = (u["id_str"] as? String) ?? (u["id"] as? NSNumber)?.stringValue,
                      let screenName = u["screen_name"] as? String else { return nil }
                return TweetUser(
                    id: id,
                    name: (u["name"] as? String) ?? screenName,
                    screenName: screenName,
                    avatarUrl: (u["profile_image_url_https"] as? String)?.replacingOccurrences(of: "_normal", with: "_bigger"),
                    isVerified: (u["ext_is_blue_verified"] as? Bool) ?? (u["is_blue_verified"] as? Bool) ?? (u["verified"] as? Bool) ?? false
                )
            }
            let topics: [String] = ((json["topics"] as? [[String: Any]]) ?? []).compactMap { $0["topic"] as? String }
            completion(.success(TypeaheadResult(topics: topics, users: users)))
        }.resume()
    }
}

// MARK: - Model

enum SearchSuggestion: Identifiable {
    case query(String)      // search for exactly what is typed
    case topic(String)
    case user(TweetUser)
    case recent(String)

    var id: String {
        switch self {
        case .query(let q): return "q-" + q
        case .topic(let t): return "t-" + t
        case .user(let u): return "u-" + u.id
        case .recent(let r): return "r-" + r
        }
    }

    // The text this suggestion searches for; a person has a page of their own instead
    var queryText: String? {
        switch self {
        case .query(let q), .topic(let q), .recent(let q): return q
        case .user: return nil
        }
    }
}

final class SearchSuggestionsModel: ObservableObject {
    static let shared = SearchSuggestionsModel()

    @Published private(set) var items: [SearchSuggestion] = []
    @Published var highlighted: Int?

    private var pending: DispatchWorkItem?
    // Bumped per keystroke so a slow reply for old text can't replace newer suggestions
    private var generation = 0
    private var currentQuery = ""

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmed
        generation += 1
        highlighted = nil
        pending?.cancel()

        if trimmed.isEmpty {
            items = SearchRecents.shared.all.map { .recent($0) }
            return
        }

        // "Search for …" is available immediately; X's suggestions are added when they arrive
        items = [.query(trimmed)]
        let myGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            APIClient.shared.fetchTypeahead(query: trimmed) { result in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == myGeneration, case .success(let found) = result else { return }
                    let topics = found.topics
                        .filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
                        .prefix(4)
                        .map { SearchSuggestion.topic($0) }
                    let users = found.users.prefix(5).map { SearchSuggestion.user($0) }
                    self.items = [.query(trimmed)] + topics + users
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = (highlighted ?? (delta > 0 ? -1 : items.count)) + delta
        highlighted = min(items.count - 1, max(0, next))
    }

    func reset() {
        pending?.cancel()
        generation += 1
        items = []
        highlighted = nil
    }

    // Return in the field: the highlighted suggestion if one is selected, otherwise the typed text
    func submit(typed: String) {
        if let index = highlighted, items.indices.contains(index) {
            NavigationManager.shared.activate(items[index])
        } else {
            NavigationManager.shared.activate(.query(typed))
        }
    }
}

extension NavigationManager {
    // Opens what a suggestion stands for and closes the search field behind it
    func activate(_ suggestion: SearchSuggestion) {
        switch suggestion {
        case .query(let text), .topic(let text), .recent(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            openSearch(trimmed)
        case .user(let user):
            openProfile(user)
        }
        searchQuery = ""
        if isSearchActive { toggleSearch() }
        SearchSuggestionsModel.shared.reset()
    }
}

// What a key does inside a search field is the same wherever the field is: typing feeds the shared suggestion model,
// the arrow keys move through it, and Return submits. Only what Return submits to differs.
private struct SearchFieldBehavior: ViewModifier {
    @Binding var text: String
    let onChange: (String) -> Void
    let onSubmit: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onSubmit { onSubmit(text) }
            .onChange(of: text) { _, typed in onChange(typed) }
            .onKeyPress(.downArrow) {
                SearchSuggestionsModel.shared.move(1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                SearchSuggestionsModel.shared.move(-1)
                return .handled
            }
    }
}

extension View {
    // The search page passes its own `onChange`, because filling the field with a suggestion it just took must not
    // reopen the panel for that same query.
    func searchFieldBehavior(
        _ text: Binding<String>,
        onChange: @escaping (String) -> Void = { SearchSuggestionsModel.shared.update(query: $0) },
        onSubmit: @escaping (String) -> Void
    ) -> some View {
        modifier(SearchFieldBehavior(text: text, onChange: onChange, onSubmit: onSubmit))
    }
}

// MARK: - Panel

struct SearchSuggestionsPanel: View {
    // The search results page answers in place; every other field opens a page of its own
    var onChoose: ((SearchSuggestion) -> Void)?

    @ObservedObject private var model = SearchSuggestionsModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var hovered: String?

    var body: some View {
        if !model.items.isEmpty {
            Group {
                // Ten suggestions do not fit under a short window; past eight rows the list scrolls instead
                if model.items.count > 8 {
                    ScrollView(.vertical, showsIndicators: false) { rows }
                        .frame(maxHeight: 420)
                } else {
                    rows
                }
            }
            .frame(maxWidth: 440)
            .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isInteractive: false))
            .padding(.horizontal, 16)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                header(before: index)
                row(for: item, highlighted: model.highlighted == index)
            }
        }
        .padding(8)
    }

    @ViewBuilder private func header(before index: Int) -> some View {
        if let title = sectionTitle(before: index) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ThemeManager.tertiaryText)
                Spacer(minLength: 0)
                if case .recent = model.items[index] {
                    Button(loc.t("search_clear_recents")) {
                        SearchRecents.shared.clear()
                        SearchSuggestionsModel.shared.update(query: "")
                    }
                    .buttonStyle(.target)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeManager.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, index == 0 ? 2 : 8)
            .padding(.bottom, 2)
        }
    }

    private func sectionTitle(before index: Int) -> String? {
        let item = model.items[index]
        let previous = index > 0 ? model.items[index - 1] : nil
        switch item {
        case .recent:
            if case .recent? = previous { return nil }
            return loc.t("search_recent")
        case .user:
            if case .user? = previous { return nil }
            return loc.t("search_tab_people")
        default:
            return nil
        }
    }

    private func row(for item: SearchSuggestion, highlighted: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                choose(item)
            } label: {
                label(for: item)
                    .padding(.leading, 12)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.target)

            // Removing a recent search is a button of its own: nested inside the row's button, VoiceOver could not
            // reach it and the mouse could not tell the two apart
            if case .recent(let text) = item {
                Button {
                    SearchRecents.shared.remove(text)
                    SearchSuggestionsModel.shared.update(query: "")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeManager.tertiaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.target)
                .help(loc.t("search_clear"))
                .accessibilityLabel(loc.t("search_clear"))
                .padding(.trailing, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlighted || hovered == item.id ? ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.2) : Color.clear)
        )
        .onHover { hovered = $0 ? item.id : nil }
    }

    @ViewBuilder private func label(for item: SearchSuggestion) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .query(let text):
                icon("magnifyingglass")
                Text(loc.format("search_for_query", ["query": text]))
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
            case .topic(let text):
                icon(text.hasPrefix("#") ? "number" : "magnifyingglass")
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
            case .recent(let text):
                icon("clock")
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
            case .user(let user):
                CachedAsyncImage(urlString: user.avatarUrl, targetSize: CGSize(width: 28, height: 28))
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(1)
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    Text(user.formattedHandle)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func choose(_ item: SearchSuggestion) {
        if let onChoose = onChoose {
            onChoose(item)
        } else {
            NavigationManager.shared.activate(item)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(ThemeManager.secondaryText)
            .frame(width: 28)
    }
}
