# Kiến trúc VietNav (bản thử nghiệm)

## Build và module

`project.yml` (XcodeGen) định nghĩa app SwiftUI, Live Activity extension, test targets và scheme. `Package.swift` định nghĩa `VietNavCore`, `NavigationActivityShared`, `OSMData` và CLI `OSMDataFetcher`; iOS 16+, Swift 5.9. `VietNavCore` chứa cả domain và platform adapters, không phải các package Clean Architecture tách biệt hoàn toàn. `VietNav/App` là composition root, `AppCoordinator` mở DB nền và đặt màn hình bản đồ.

## Luồng dữ liệu

- `Core/Location/LocationManager`: nguồn Core Location/heading chung trên main actor; Simulator mặc định phát GPX nội bộ. Quản lý quyền và phiên navigation; không bảo đảm chạy vô hạn ở background.
- `Features/Map`: MapLibre wrapper, style, camera và ViewModel; màn hình sở hữu `NavigationEngine`, `SpeedWarningEngine`, route preview, search và các sheet.
- `Features/Navigation`: URLSession OSRM adapter sau `RoutingServiceProtocol`, model Route/steps, renderer, route VM và engine snap/progress/off-route. OSRM yêu cầu GeoJSON, không parse encoded polyline. Engine chạy GPS qua Combine, heuristic không phải map matching production.
- `Features/SpeedWarning`: query theo vị trí/hướng, cảnh báo tốc độ theo dữ liệu SQLite và hàng đợi âm thanh. Điểm, heading và giới hạn chỉ là ước lượng; không thay biển báo.
- `Core/Audio`: queue audio/TTS có priority, nhường microphone. `Core/Background`: thông báo và ActivityKit, `ActivityShared` là attributes dùng chung widget/app.
- `Features/Search`: Nominatim search/reverse, cache/lịch sử/favorites GRDB riêng; autocomplete hoàn toàn cục bộ; Speech vi-VN. Dịch vụ công cộng có giới hạn.
- `Core/Database`: `TrafficDatabase` quản lý một GRDB DatabaseQueue, migration v1/v2, bảng node/segments/report và trigger R-Tree. `Core/DataUpdate` có API cập nhật tường minh, chưa có UI/scheduler/config server. Download kiểm tra HTTPS, schema, hash, integrity và version trước transaction; file và manifest cần host tin cậy. `user_reports` giữ nguyên; các road segment được coi là dữ liệu OSM và thay thế toàn bộ. Không dùng nếu DB chứa segment tự tạo cần giữ.
- `Data/OSM`, `Tools/OSMDataFetcher`, `Tools/PBFConverter`, `Tools/TrafficDatabaseBuilder`: thu thập/xây dựng seed bên ngoài app, không tự tạo dữ liệu thực. Kiểm tra độ bao phủ, policy dịch vụ và ODbL.

## Lifecycle & bảo mật

Navigation duy trì location/audio trong nền theo khả năng iOS, screen giữ speed engine; app bị kill/force-quit, quyền bị thu hồi hay GPS stale sẽ làm gián đoạn. Background manager không thay thế background execution entitlement/capability. Live Activity có thể công khai tên đường. TLS + SHA-256 phát hiện lỗi tải nhưng không chống máy chủ bị xâm nhập; chưa có chữ ký manifest/public key pinning. Truy vấn Nominatim, route và tile dùng mạng công cộng thử nghiệm và có thể tiết lộ địa chỉ/tọa độ/IP. Không có Crashlytics, Sentry hay analytics server. Xem `docs/PRODUCTION_SETUP.md`, `docs/TESTING_RELEASE.md` và `docs/APP_STORE.md` trước triển khai.
