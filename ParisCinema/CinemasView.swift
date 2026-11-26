import SwiftUI
import MapKit

struct CinemasView: View {
    @Environment(Store.self) private var store
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.8600, longitude: 2.3400),
        span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)))
    @State private var selected: String?
    @State private var type: String = ""
    @State private var showList = false

    private var shown: [Cinema] {
        store.allCinemas.filter { c in
            type.isEmpty || c.type == type || (type == "My cinemas" && store.isPreferred(c.name))
        }
    }
    private var typeChoices: [String] {
        Cinema.types + (store.extraCinemas.isEmpty ? [] : ["Other"])
    }

    var body: some View {
        NavigationStack {
            Group {
                if showList { list } else { map }
            }
            .navigationTitle("Cinemas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Type", selection: $type) {
                            Text("All cinemas").tag("")
                            Text("My cinemas").tag("My cinemas")
                            ForEach(typeChoices, id: \.self) { t in Text(t).tag(t) }
                        }
                    } label: {
                        Label(type.isEmpty ? "All" : type, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showList.toggle() } label: {
                        Image(systemName: showList ? "map" : "list.bullet")
                    }
                    .accessibilityLabel(showList ? "Show map" : "Show list")
                }
            }
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
        }
    }

    private var map: some View {
        Map(position: $position, selection: $selected) {
            ForEach(shown) { c in
                Marker(c.name, systemImage: store.isPreferred(c.name) ? "star.fill" : "film", coordinate: c.coordinate)
                    .tint(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : c.typeColor)
                    .tag(c.name)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .bottom) {
            if let name = selected, let c = store.cinema(named: name) {
                card(c)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected)
    }

    private var list: some View {
        List {
            let mine = store.myCinemas.compactMap { store.cinema(named: $0) }
            if (type.isEmpty || type == "My cinemas") {
                Section {
                    if mine.isEmpty {
                        Text("Tap the star on a cinema to add it here. New plans use your cinemas first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(mine) { c in listRow(c) }
                } header: {
                    Text("My cinemas")
                }
            }
            ForEach(typeChoices.filter { type.isEmpty || $0 == type }, id: \.self) { t in
                Section {
                    ForEach(store.allCinemas.filter { $0.type == t }) { c in listRow(c) }
                } header: {
                    Text(t)
                } footer: {
                    Text(Cinema.typeBlurb(t))
                }
            }
        }
    }

    private func listRow(_ c: Cinema) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name).font(.headline)
                Text(c.address).font(.subheadline).foregroundStyle(.secondary)
                plannedHere(c)
                if let u = c.directionsURL {
                    Link(destination: u) { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                        .font(.subheadline)
                }
            }
            Spacer()
            starButton(c)
        }
        .padding(.vertical, 2)
    }

    private func starButton(_ c: Cinema) -> some View {
        Button { store.togglePreferred(c) } label: {
            Image(systemName: store.isPreferred(c.name) ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(store.isPreferred(c.name) ? "Remove from My cinemas" : "Add to My cinemas")
    }

    private func card(_ c: Cinema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline)
                    Text("\(c.type) · \(c.address)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                starButton(c)
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .accessibilityLabel("Close")
            }
            plannedHere(c)
            if let u = c.directionsURL {
                Link(destination: u) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func plannedHere(_ c: Cinema) -> some View {
        let planned = store.plannedFilms.filter { $0.1.cn == c.name }
        ForEach(planned, id: \.0.id) { item in
            NavigationLink(value: item.0.id) {
                Label("\(item.0.title) · \(D.fmt(item.1.d, "EEE d MMM")) \(item.1.t)", systemImage: "calendar")
                    .font(.subheadline)
            }
        }
        let showing: [Film] = store.showtimes.compactMap { entry -> Film? in
            guard (entry.value.cinemas ?? []).contains(where: { $0.name == c.name }) else { return nil }
            return store.index[entry.key]
        }.sorted { $0.title < $1.title }
        ForEach(showing) { f in
            NavigationLink(value: f.id) {
                Label("Showing \(f.title)", systemImage: "clock").font(.subheadline)
            }
        }
    }
}
