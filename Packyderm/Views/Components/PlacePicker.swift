import SwiftUI

/// Search field that resolves to a `Place`.
struct PlacePicker: View {
    var title: String
    var onPick: (Place) -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(title, text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if searching { ProgressView() }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            ForEach(results) { place in
                Button {
                    onPick(place)
                    query = ""
                    results = []
                } label: {
                    Text(place.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .task(id: query) {
            // Debounce typing.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; return }
        searching = true
        let found = await Geocoder.shared.search(trimmed)
        // Collapse duplicate names (e.g. several POIs in the same city).
        var seen: Set<String> = []
        results = found.filter { seen.insert($0.name).inserted }
        searching = false
    }
}
