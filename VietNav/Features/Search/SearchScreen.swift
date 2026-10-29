import SwiftUI
import UIKit

@MainActor
final class PlaceSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var suggestions: [SearchSuggestion] = []
    @Published private(set) var favorites: [FavoritePlace] = []
    @Published private(set) var recent: [SearchResult] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var submittedQuery = ""
    private let service: SearchServiceProtocol
    private let storage: SearchPersistence
    private var searchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var suggestionID = UUID()
    init(service: SearchServiceProtocol = NominatimSearchService.shared, storage: SearchPersistence = .shared) {
        self.service = service; self.storage = storage
    }
    func loadSaved() {
        Task {
            do { favorites = try await storage.favorites(); recent = try await storage.recent() }
            catch { self.error = "Không thể đọc dữ liệu đã lưu: \(error.localizedDescription)" }
        }
    }
    func search() {
        guard !loading else { return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true; error = nil; submittedQuery = term
        searchTask = Task {
            do {
                let found = try await service.search(query: term)
                guard !Task.isCancelled else { return }
                results = found; hasSearched = true; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                results = []; hasSearched = true; self.error = error.localizedDescription; loading = false
            }
        }
    }
    func updateSuggestions() {
        suggestionTask?.cancel()
        let id = UUID(); suggestionID = id
        let term = query
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { suggestions = []; return }
        suggestionTask = Task {
            do {
                let found = try await service.autocomplete(query: term)
                guard !Task.isCancelled, suggestionID == id else { return }
                suggestions = found
            } catch {
                guard !Task.isCancelled, suggestionID == id else { return }
                suggestions = []; self.error = "Không thể đọc gợi ý cục bộ: \(error.localizedDescription)"
            }
        }
    }
    func select(_ place: SearchResult, onSelect: @escaping (SearchResult) -> Void) {
        selectionTask?.cancel()
        selectionTask = Task {
            do {
                try await storage.addRecent(place)
                guard !Task.isCancelled else { return }
                onSelect(place)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Không thể lưu lịch sử: \(error.localizedDescription)"
            }
        }
    }
    func favorite(_ place: SearchResult, kind: String) {
        let id = kind == "Nhà" ? "home" : kind == "Công ty" ? "work" : "place/\(place.id)"
        let label = kind == "Yêu thích" ? place.shortName : kind
        Task {
            do { try await storage.saveFavorite(FavoritePlace(id: id, label: label, place: place)); favorites = try await storage.favorites() }
            catch { self.error = "Không thể lưu yêu thích: \(error.localizedDescription)" }
        }
    }
    func removeFavorite(_ item: FavoritePlace) {
        Task {
            do { try await storage.removeFavorite(id: item.id); favorites = try await storage.favorites() }
            catch { self.error = "Không thể xóa yêu thích: \(error.localizedDescription)" }
        }
    }
    func clearRecent() {
        Task {
            do { try await storage.clearRecent(); recent = [] }
            catch { self.error = "Không thể xóa lịch sử: \(error.localizedDescription)" }
        }
    }
    func cancel() { searchTask?.cancel(); suggestionTask?.cancel(); selectionTask?.cancel(); suggestionID = UUID(); loading = false }
}

struct SearchScreen: View {
    let onSelect: (SearchResult) -> Void
    @StateObject private var model = PlaceSearchViewModel()
    @StateObject private var voice = VoiceSearchController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let categories: [(String, String, String)] = [
        ("Ăn uống", "fork.knife", "nhà hàng"), ("Cà phê", "cup.and.saucer.fill", "quán cà phê"),
        ("Xăng", "fuelpump.fill", "trạm xăng"), ("Bệnh viện", "cross.case.fill", "bệnh viện"),
        ("Bãi đỗ", "parkingsign.circle.fill", "bãi đỗ xe"), ("Khách sạn", "bed.double.fill", "khách sạn")
    ]
    private var editing: Bool { model.query.trimmingCharacters(in: .whitespacesAndNewlines) != model.submittedQuery }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(VNTheme.secondary)
                    TextField("Địa điểm, địa chỉ...", text: $model.query).submitLabel(.search).onSubmit { voice.stop(); model.search() }
                        .accessibilityLabel("Nhập địa điểm cần tìm")
                    Button { voice.isRecording ? voice.stop() : voice.start() } label: {
                        Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill").foregroundStyle(voice.isRecording ? VNTheme.danger : VNTheme.accent)
                    }.disabled(voice.isRequesting).accessibilityLabel(voice.isRecording ? "Dừng ghi âm" : "Nhập bằng giọng nói")
                    Button("Tìm") { voice.stop(); model.search() }.fontWeight(.bold).disabled(model.loading || voice.isRequesting)
                }.padding(14).background(VNTheme.canvas, in: RoundedRectangle(cornerRadius: 14)).padding()
                if voice.isRequesting { ProgressView("Đang xin quyền microphone...").padding(.horizontal) }
                if voice.isRecording { Text("Đang nghe… Dừng và nhấn Tìm để gửi.").font(.caption).foregroundStyle(VNTheme.accent) }
                if let error = voice.error ?? model.error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(VNTheme.danger)
                        if voice.error != nil, let url = URL(string: UIApplication.openSettingsURLString) { Button("Cài đặt") { openURL(url) }.font(.caption.bold()) }
                    }.padding(.horizontal)
                }
                if model.loading { ProgressView("Đang tìm địa điểm...").padding() }
                List {
                    if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section("TÌM NHANH Ở VIỆT NAM") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(categories, id: \.0) { item in
                                    Button { voice.stop(); model.query = item.2; model.search() } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: item.1).font(.title3).foregroundStyle(VNTheme.accent)
                                            Text(item.0).font(.caption).foregroundStyle(VNTheme.text)
                                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                                    }.disabled(model.loading || voice.isRecording || voice.isRequesting)
                                }
                            }.listRowBackground(VNTheme.surface)
                        }
                        if !model.favorites.isEmpty {
                            Section("YÊU THÍCH") {
                                ForEach(model.favorites) { favorite in
                                    placeRow(favorite.place, label: favorite.label)
                                        .swipeActions { Button("Xóa", role: .destructive) { model.removeFavorite(favorite) } }
                                }
                            }
                        }
                        if !model.recent.isEmpty {
                            Section {
                                ForEach(model.recent) { place in placeRow(place, label: nil) }
                                Button("Xóa lịch sử", role: .destructive) { model.clearRecent() }
                            } header: { Text("GẦN ĐÂY") }
                        }
                    } else if editing {
                        if !model.suggestions.isEmpty {
                            Section("GỢI Ý TRÊN THIẾT BỊ") { ForEach(model.suggestions) { item in placeRow(item.result, label: nil) } }
                        } else {
                            Text("Nhấn Tìm để tra cứu. Gợi ý chỉ lấy từ lịch sử và yêu thích trên thiết bị.").font(.caption).foregroundStyle(VNTheme.secondary)
                        }
                    } else if !model.results.isEmpty {
                        Section("KẾT QUẢ") { ForEach(model.results) { place in placeRow(place, label: nil) } }
                    } else if model.hasSearched && !model.loading && model.error == nil {
                        Text("Không tìm thấy địa điểm. Thử địa chỉ khác.").foregroundStyle(VNTheme.secondary)
                    }
                }.listStyle(.insetGrouped)
                Text("Từ khóa gửi tới Nominatim. Giọng nói có thể được xử lý bởi Apple. © OpenStreetMap contributors")
                    .font(.caption2).foregroundStyle(VNTheme.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.bottom, 10)
            }
            .background(VNTheme.surface).foregroundStyle(VNTheme.text)
            .navigationTitle("Tìm địa điểm").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
            .onAppear { model.loadSaved() }
            .onChange(of: model.query) { _ in model.updateSuggestions() }
            .onChange(of: voice.transcript) { model.query = $0 }
            .onDisappear { voice.stop(); model.cancel() }
        }
    }
    private func placeRow(_ place: SearchResult, label: String?) -> some View {
        HStack(alignment: .center) {
            Button { voice.stop(); model.select(place, onSelect: onSelect) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: label == "Nhà" ? "house.fill" : label == "Công ty" ? "briefcase.fill" : "mappin.circle.fill")
                        .font(.title2).foregroundStyle(VNTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        if let label { Text(label).font(.caption.bold()).foregroundStyle(VNTheme.accent) }
                        Text(place.shortName).font(.subheadline.bold()).foregroundStyle(VNTheme.text).multilineTextAlignment(.leading)
                        Text(place.displayName).font(.caption).foregroundStyle(VNTheme.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer()
                }.padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Chọn điểm đến")
            Menu {
                Button("Lưu vào yêu thích") { model.favorite(place, kind: "Yêu thích") }
                Button("Đặt làm Nhà") { model.favorite(place, kind: "Nhà") }
                Button("Đặt làm Công ty") { model.favorite(place, kind: "Công ty") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(VNTheme.accent).frame(width: 44, height: 44)
            }.accessibilityLabel("Tùy chọn cho \(place.shortName)")
        }
    }
}
struct SearchScreen_Previews: PreviewProvider { static var previews: some View { SearchScreen(onSelect: { _ in }) } }
