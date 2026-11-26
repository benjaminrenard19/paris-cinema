import SwiftUI
import MapKit
import CoreLocation

// MARK: - Choosing a cinema: My cinemas first, search, sort by distance, Apple Maps

struct CinemaPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let film: Film?
    @Binding var selected: String

    enum Sort: String, CaseIterable, Identifiable {
        case mine = "My cinemas", me = "Near me", place = "Near a place"
        var id: String { rawValue }
    }

    @State private var sort: Sort = .mine
    @State private var query = ""
    @State private var placeQuery = ""
    @State private var anchor: CLLocation?
    @State private var status: String?
    @State private var nearby: [Cinema] = []
    @State private var mapResults: [Cinema] = []
    @State private var searchingMaps = false

    var body: some View {
        List {
            Section {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { s in Text(LocalizedStringKey(s.rawValue)).tag(s) }
                }
                .pickerStyle(.segmented)
                if sort == .place {
                    HStack {
                        TextField("Address, métro station or postcode", text: $placeQuery)
                            .submitLabel(.search)
                            .onSubmit { Task { await findPlace() } }
                        Button("Go") { Task { await findPlace() } }
                            .disabled(placeQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Tap the star to add a cinema to My cinemas. New plans use your cinemas first.")
            }

            let list = filtered
            let mine = list.filter { store.isPreferred($0.name) }
            let others = list.filter { !store.isPreferred($0.name) }
            if !mine.isEmpty {
                Section("My cinemas") {
                    ForEach(mine) { c in row(c) }
                }
            }
            if !others.isEmpty {
                Section(store.myCinemas.isEmpty ? String(localized: "All cinemas") : String(localized: "Other cinemas")) {
                    ForEach(others) { c in row(c) }
                }
            }
            let extra = sorted((query.isEmpty ? nearby : mapResults).filter { m in
                !store.allCinemas.contains { $0.name == m.name }
            })
            if !extra.isEmpty {
                Section(query.isEmpty ? String(localized: "More cinemas nearby (Apple Maps)") : String(localized: "Found on Apple Maps")) {
                    ForEach(extra) { c in row(c) }
                }
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty && mapResults.isEmpty {
                Section {
                    Button { Task { await searchMaps() } } label: {
                        Label(searchingMaps ? String(localized: "Searching…") : String(localized: "Search Apple Maps for “\(query)”"), systemImage: "magnifyingglass")
                    }
                    .disabled(searchingMaps)
                }
            }
        }
        .navigationTitle("Cinema")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cinema name or postcode")
        .onChange(of: query) { _, _ in mapResults = [] }
        .onChange(of: sort) { _, s in Task { await sortChanged(s) } }
    }

    // MARK: Rows

    private func row(_ c: Cinema) -> some View {
        HStack(spacing: 12) {
            Button {
                store.addExtra(c)
                selected = c.name
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).foregroundStyle(.primary)
                        Text(verbatim: c.type == "Other" ? c.address : "\(NSLocalizedString(c.type, comment: "Cinema type")) · \(c.address)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let n = showCount(c), n > 0 {
                            Text(n == 1 ? String(localized: "1 showtime for this film") : String(localized: "\(n) showtimes for this film"))
                                .font(.caption2.weight(.semibold)).foregroundStyle(Color.theme)
                        }
                    }
                    Spacer(minLength: 4)
                    if let a = anchor {
                        Text(distanceText(distance(c, a))).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    if c.name == selected {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.theme)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { store.togglePreferred(c) } label: {
                Image(systemName: store.isPreferred(c.name) ? "star.fill" : "star")
                    .foregroundStyle(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(store.isPreferred(c.name) ? String(localized: "Remove from My cinemas") : String(localized: "Add to My cinemas"))
        }
    }

    // MARK: Filtering and sorting

    private var filtered: [Cinema] {
        let q = query.folded.trimmingCharacters(in: .whitespaces)
        let list = store.allCinemas.filter { c in
            q.isEmpty || c.name.folded.contains(q) || c.address.folded.contains(q) || c.type.folded.contains(q)
        }
        return sorted(list)
    }

    private func sorted(_ list: [Cinema]) -> [Cinema] {
        if let a = anchor {
            return list.sorted { distance($0, a) < distance($1, a) }
        }
        let order = Cinema.types + ["Other"]
        return list.sorted { x, y in
            let kx = (store.myCinemas.firstIndex(of: x.name) ?? 999, order.firstIndex(of: x.type) ?? 9)
            let ky = (store.myCinemas.firstIndex(of: y.name) ?? 999, order.firstIndex(of: y.type) ?? 9)
            if kx != ky { return kx < ky }
            return x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending
        }
    }

    private func distance(_ c: Cinema, _ a: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: c.lat, longitude: c.lng).distance(from: a)
    }

    private func showCount(_ c: Cinema) -> Int? {
        guard let film, let list = store.showtimes[film.id]?.cinemas else { return nil }
        let today = D.today
        let n = c.name.folded
        var count = 0
        for s in list {
            let m = (s.name ?? "").folded
            guard !m.isEmpty, m.contains(n) || n.contains(m) else { continue }
            for (day, times) in s.times ?? [:] where day >= today { count += times.count }
        }
        return count
    }

    // MARK: Location and Apple Maps

    private func sortChanged(_ s: Sort) async {
        status = nil
        nearby = []
        switch s {
        case .mine:
            anchor = nil
        case .me:
            anchor = nil
            status = String(localized: "Finding where you are…")
            if let loc = await LocationFinder.shared.current() {
                anchor = loc
                status = String(localized: "Sorted by distance from you.")
                nearby = await PlaceSearch.cinemas(near: loc.coordinate)
            } else {
                status = String(localized: "Your location isn't available. Allow it in Settings › Privacy & Security › Location Services, or use Near a place.")
            }
        case .place:
            anchor = nil
            if !placeQuery.trimmingCharacters(in: .whitespaces).isEmpty { await findPlace() }
        }
    }

    private func findPlace() async {
        let q = placeQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        status = String(localized: "Looking up \(q)…")
        if let p = await PlaceSearch.place(q) {
            anchor = CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude)
            status = String(localized: "Sorted by distance from \(p.name).")
            nearby = await PlaceSearch.cinemas(near: p.coordinate)
        } else {
            status = String(localized: "Couldn't find “\(q)”. Try a street, a métro station or a postcode.")
        }
    }

    private func searchMaps() async {
        searchingMaps = true
        mapResults = await PlaceSearch.cinemas(matching: query)
        searchingMaps = false
        if mapResults.isEmpty { status = String(localized: "No cinema called “\(query)” on Apple Maps.") }
    }
}

func distanceText(_ m: CLLocationDistance) -> String {
    if m < 1000 { return "\(Int((m / 50).rounded()) * 50) m" }
    return String(format: "%.1f km", m / 1000)
}

// MARK: - Current location (asks permission the first time)

final class LocationFinder: NSObject, CLLocationManagerDelegate {
    static let shared = LocationFinder()
    private let manager = CLLocationManager()
    private var waiters: [(CLLocation?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async -> CLLocation? {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                self.locate { cont.resume(returning: $0) }
            }
        }
    }

    private func locate(_ done: @escaping (CLLocation?) -> Void) {
        waiters.append(done)
        guard waiters.count == 1 else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard !waiters.isEmpty else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .notDetermined: break
        default: finish(nil)
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ l: CLLocation?) {
        let w = waiters
        waiters = []
        w.forEach { $0(l) }
    }
}

// MARK: - Apple Maps searches

enum PlaceSearch {
    static let paris = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))

    /// An address, station or area in or around Paris.
    static func place(_ q: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = q
        r.region = paris
        guard let item = try? await MKLocalSearch(request: r).start().mapItems.first else { return nil }
        return (item.name ?? q, item.placemark.coordinate)
    }

    /// Cinemas whose name matches the text.
    static func cinemas(matching q: String) async -> [Cinema] {
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = q
        r.region = paris
        r.resultTypes = .pointOfInterest
        r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        guard let items = try? await MKLocalSearch(request: r).start().mapItems else { return [] }
        return items.compactMap(cinema(from:))
    }

    /// Cinemas within 2.5 km of a point.
    static func cinemas(near c: CLLocationCoordinate2D) async -> [Cinema] {
        let r = MKLocalPointsOfInterestRequest(center: c, radius: 2500)
        r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        guard let items = try? await MKLocalSearch(request: r).start().mapItems else { return [] }
        return items.compactMap(cinema(from:))
    }

    private static func cinema(from item: MKMapItem) -> Cinema? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let p = item.placemark
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, p.postalCode ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return Cinema(name: name, type: "Other", address: address.isEmpty ? (p.locality ?? "Paris") : address,
                      lat: p.coordinate.latitude, lng: p.coordinate.longitude)
    }
}
