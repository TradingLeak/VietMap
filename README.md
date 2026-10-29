# VietNav — giao diện iPhone thử nghiệm

Dự án mới xây dựng lại sau yêu cầu xóa dự án cũ. Giao diện SwiftUI tham khảo bố cục ảnh người dùng: thanh chỉ dẫn, đồng hồ tốc độ, danh sách cảnh báo, nút bản đồ và thanh hành trình. Cài đặt → **Xem giao diện mô phỏng** để xem tuyến/biển báo mẫu; đó không phải dữ liệu thực.

## Chạy

Cần macOS, Xcode 15.4+ và XcodeGen. Chạy `xcodegen generate`, mở `VietNav.xcodeproj`, chọn scheme VietNav và chạy trên iPhone iOS 16+. MapLibre được tải qua Swift Package Manager. Để xem vị trí/tốc độ thật, nhấn nút vị trí và cấp quyền. iOS có thể không cung cấp tốc độ khi GPS chưa ổn định.

## Phạm vi hiện tại

Chỉ là giao diện thử nghiệm với nền bản đồ raster OpenStreetMap trực tuyến, zoom, 2D/3D, định vị và tốc độ GPS. Chưa có tìm kiếm, tính tuyến, cảnh báo thật, âm thanh, CarPlay, cập nhật dữ liệu GitHub, bản đồ offline hay background navigation. Không dùng để dẫn đường hoặc cảnh báo an toàn. Nút âm thanh hiện chỉ đổi trạng thái giao diện, chưa phát cảnh báo.

Bản đồ dùng `tile.openstreetmap.org`, phải tuân thủ [chính sách tile OSM](https://operations.osmfoundation.org/policies/tiles/), không tải hàng loạt hoặc lưu offline từ máy chủ này. Khi phát hành cần nhà cung cấp hoặc server phù hợp và ghi công OSM. Bản đồ cần mạng; các tuyến/biển trong chế độ mô phỏng là hình vẽ ví dụ không liên quan vị trí GPS.
