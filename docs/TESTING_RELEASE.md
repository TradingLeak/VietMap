# Kiểm thử, cập nhật dữ liệu và release

## Xcode và CI

Trên macOS có Xcode 15+, XcodeGen và simulator iOS 16+: `xcodegen generate`, `xcodebuild build-for-testing -project VietNav.xcodeproj -scheme VietNav -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO`, sau đó `xcodebuild test-without-building` với cùng project/scheme/destination. Chọn simulator thực tế có trên máy. Scheme gồm unit/UI tests. CI macOS tự chọn iPhone có sẵn, tạo project, build/test và giữ `.xcresult`; CI chưa được chạy trong môi trường hiện tại. Scheme package `OSMData` có tests riêng; package core dùng UIKit nên không thể `swift test` trên Linux/macOS host thông thường.

Unit tests trong `VietNav/Tests` kiểm tra SQLite/R-Tree và migration v1→v2, search, hướng/cảnh báo/tolerance, OSRM GeoJSON với mock URLProtocol, snap/progress/off-route/steps và audio. Route service yêu cầu `geometries=geojson` nên test geometry JSON, **không có decoder encoded polyline**. UI test dùng launch argument DEBUG `-vietnav-ui-testing`, trả fixture search/routing, không gửi hai request đó ra mạng; tile map vẫn có thể gọi mạng. UI test cần cấp quyền vị trí simulator; hộp thoại hệ thống, keyboard, animation và tốc độ CI có thể ảnh hưởng test, cần kiểm chứng và sửa với Xcode trước khi coi là gate đáng tin cậy. Không đưa fixture DEBUG vào bản Release.

Benchmark tùy chọn: đặt `VIETNAV_BENCHMARK=1` trong environment của scheme test để đo insert + query 100.000 điểm và R-Tree; thêm `VIETNAV_ENFORCE_PERF=1` để assert tổng <1s và một query <10ms. Thời gian phụ thuộc simulator/thiết bị, mật độ điểm, filesystem và build; lấy nhiều mẫu, phân bố p50/p95 và cấu hình thực tế trước khi kết luận. Test không chạy mặc định, không có số đo/SLA đã xác nhận. Đo FPS trên iPhone 12+ bằng Instruments/Core Animation, profile Release, bản đồ/khu vực và nhiệt độ xác định; chưa có phép đo hay assertion 60 FPS tự động.

## Tuyến GPX

`Resources/TestRoutes/*.gpx` là waypoint mô phỏng *không* phải route OSRM, không xác nhận bám đường, camera hay biển báo thực tế. Các điểm Hà Nội/TP.HCM chỉ gần các mốc được đặt tên; highway test chỉ có điểm synthetic, không có camera thật. Để dùng Core Location của simulator, thêm launch argument DEBUG `-use-simulator-location` trong Scheme > Run > Arguments; chọn file GPX qua Scheme > Run > Options > Allow Location Simulation / Default Location (hoặc menu Debug > Simulate Location tùy Xcode). Menu Simulator Custom Location chỉ nhập tọa độ đơn, không phải nơi import GPX. Để xác minh cảnh báo camera, cần tạo seed test độc lập có camera synthetic đúng tọa độ/hướng, test engine với dữ liệu đó; GPX không tự tạo camera. Không dùng fixture này điều hướng trên đường thật.

## Pipeline dữ liệu

`./scripts/fetch_osm_data.sh --help` bọc CLI Overpass; cần Swift trên macOS. Để xử lý PBF offline cần `osmium-tool`, Python 3 với `osmium` (pyosmium) và SQLite R-Tree. Chạy `./scripts/update_osm_data.sh osm-data/build-20261029 --input /path/vietnam-latest.osm.pbf`, hoặc bỏ `--input` để tải Geofabrik (file lớn). Script lọc node camera/toll/crossing và way maxspeed, dùng pyosmium lấy geometry rồi builder tạo seed SQLite/manifest, hash, integrity và count. `traffic_signals_vn.json` để rỗng: đèn tín hiệu không tự động là camera đèn đỏ; không suy diễn biển khu dân cư. Trường version là thời điểm build UTC, **không bảo đảm thời điểm dữ liệu nguồn**. Một số tag OSM bị bỏ qua; validate counts, độ phủ, tính đúng và giấy phép trước publish. Script chỉ upload nếu truyền `--upload s3://...` và có AWS CLI/cấp quyền từ môi trường; không lưu credential. Upload DB trước manifest có thể tạm khiến client từ chối checksum cũ; dùng prefix bất biến/triển khai có kiểm soát.

`TrafficDataUpdateService(manifestURL: ...).checkForDataUpdates()` là API tường minh, chưa có UI, scheduler hay endpoint mặc định; nhà vận hành phải cấu hình HTTPS và chỉ gọi khi không dẫn đường. Manifest trỏ cùng host tới `vietnam_traffic.sqlite`; giới hạn 200 MiB, kiểm tra hash, version và integrity trước cài trong transaction. Không chống compromise máy chủ: manifest chưa được ký, và kiểm tra kích thước sau download không chặn hết băng thông/disk exhaustion. Hash không chứng minh tính đúng của dữ liệu. Triggers xây lại R-Tree; giữ `user_reports` và các node source khác OSM, nhưng **thay toàn bộ road_segments** do schema cũ không có nguồn; không gọi khi có đường tự tạo cần giữ. Các phiên bản cũ hơn bị bỏ qua. Nếu mất điện/SQLite lỗi, transaction rollback; cần test crash, kích thước thật, migration, signature và backup trên thiết bị trước khi dùng production.

## Crash và khôi phục

Chưa cài Firebase/Sentry. Không dùng `signal(SIGSEGV/SIGABRT)` để serialize Swift hoặc gọi SDK: handler ở trạng thái tiến trình hỏng, nhiều API không async-signal-safe, có thể làm mất crash report hoặc deadlock; exception handler cũng không khôi phục an toàn. Cần SDK được nhà cung cấp hỗ trợ, cấu hình chính sách dữ liệu nghiêm ngặt, symbol upload/dSYM, test crash bản build phù hợp, và chỉ lưu checkpoint có kiểm soát ở lúc app còn chạy bình thường. Hiện chưa có khôi phục phiên dẫn đường sau crash. Thu crash/analytics cần disclosure, đồng ý khi cần và loại tọa độ/URL khỏi payload; xem `PRODUCTION_SETUP.md`.

## Checklist App Store (chưa hoàn thành)

- [ ] Icon app/marketing 1024 phù hợp asset catalog và yêu cầu hiện hành; launch screen đã có plist tối thiểu, cần kiểm thử.
- [ ] URL công khai cho privacy policy, terms of service và support; app privacy labels chính xác.
- [ ] Screenshot iPhone/iPad thật theo kích thước được App Store Connect yêu cầu; video preview nếu dùng.
- [ ] Description tiếng Việt/English, keywords, age rating qua questionnaire (không giả định 4+), support/review information và demo account nếu thực sự cần.
- [ ] Xác định export compliance theo quy định Apple và thực tế cryptography; HTTPS không tự động trả lời toàn bộ questionnaire.
- [ ] Signing/App ID, version, dSYM, archive, kiểm thử accessibility/background/battery/thiết bị, TestFlight với 100 người nếu có thể; chỉ release sau khi review và xử lý feedback.
- [ ] CarPlay/ads/offline/subscription chưa triển khai; không quảng cáo hoặc bán tính năng chưa được duyệt/kiểm chứng.

### Description English (draft)
VietNav helps you find destinations and preview routes using OpenStreetMap data. Follow step-by-step guidance and review available traffic warnings. Save frequent places and search in Vietnamese by voice. Guidance and warnings may be incomplete or inaccurate; always follow road signs and local laws. Some features require connectivity and location permission.
