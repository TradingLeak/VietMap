# VietNav — giao diện iPhone thử nghiệm

Dự án mới xây dựng lại sau yêu cầu xóa dự án cũ. Giao diện SwiftUI tham khảo bố cục ảnh người dùng: thanh chỉ dẫn, đồng hồ tốc độ, danh sách cảnh báo, nút bản đồ và thanh hành trình. Cài đặt → **Xem giao diện mô phỏng** để xem tuyến/biển báo mẫu; đó không phải dữ liệu thực.

## Chạy

Cần macOS, Xcode 15.4+ và XcodeGen. Chạy `xcodegen generate`, mở `VietNav.xcodeproj`, chọn scheme VietNav và chạy trên iPhone iOS 16+. MapLibre được tải qua Swift Package Manager. Để xem vị trí/tốc độ thật, nhấn nút vị trí và cấp quyền. iOS có thể không cung cấp tốc độ khi GPS chưa ổn định.

## Phạm vi hiện tại

Chỉ là giao diện thử nghiệm với nền bản đồ raster OpenStreetMap trực tuyến, zoom, 2D/3D, định vị và tốc độ GPS. Có tìm địa điểm offline từ tên OSM; chưa có tính tuyến, cảnh báo thật, âm thanh, CarPlay, cập nhật dữ liệu GitHub, bản đồ offline hay background navigation. Không dùng để dẫn đường hoặc cảnh báo an toàn. Nút âm thanh hiện chỉ đổi trạng thái giao diện, chưa phát cảnh báo.

Bản đồ dùng `tile.openstreetmap.org`, phải tuân thủ [chính sách tile OSM](https://operations.osmfoundation.org/policies/tiles/), không tải hàng loạt hoặc lưu offline từ máy chủ này. Khi phát hành cần nhà cung cấp hoặc server phù hợp và ghi công OSM. Bản đồ cần mạng; các tuyến/biển trong chế độ mô phỏng là hình vẽ ví dụ không liên quan vị trí GPS.

### Xem trước giao diện trên trình duyệt

Chạy `python3 -m http.server 8000 --directory preview` và mở trang tương ứng. Đây là bản dựng HTML minh họa độc lập, không phải iOS Simulator hay ứng dụng SwiftUI; bản đồ là hình minh họa, không có GPS hoặc chức năng dẫn đường thực.

Định hướng cho bản tiếp theo (bao gồm tìm kiếm và tuyến offline) nằm trong [kế hoạch phát triển](docs/KE-HOACH-PHAT-TRIEN.md); đó là mục tiêu, không phải các tính năng hiện có.

Thiết kế lõi tính tuyến dùng chung hai bản đồ và hỗ trợ AI offline: [thiết kế tuyến AI offline](docs/THIET-KE-TUYEN-AI-OFFLINE.md). Đây là thiết kế, chưa phải tính năng đã triển khai.

## Dữ liệu OSM thử nghiệm trong bản build

GitHub Actions tải bản trích xuất Việt Nam từ Geofabrik và trích các node/way có tag tốc độ, biển báo và một số loại camera/giám sát vào SQLite. Cùng một đối tượng có thể thuộc nhiều nhóm. Dữ liệu là tag OSM thô chưa xác minh, lưu thô relation enforcement nhưng chưa diễn giải relation hoặc hạn chế rẽ, không đầy đủ và **chưa kết nối cảnh báo hoặc dẫn đường**. Không dùng để lái xe. File và thống kê cũng được lưu trong artifact `VietNav-OSM-traffic-data` trong 14 ngày. Nguồn © OpenStreetMap contributors, dữ liệu theo ODbL; cần đáp ứng đầy đủ nghĩa vụ giấy phép khi phân phối. Việc tải cập nhật trong app chưa triển khai.

## Tiến độ bổ sung

Trong Cài đặt có thể chuyển giữa MapLibre/OSM trực tuyến và MapKit; đây mới là hai lớp hiển thị, chưa có tính tuyến. Build trên nhánh phiên làm việc tạo release dữ liệu OSM thô công khai có phiên bản; Cài đặt có nút tải thủ công, kiểm tra kích thước và SHA-256 trước khi thay file. File tải về chưa kết nối với công cụ cảnh báo. SHA-256 lấy từ cùng release chỉ bảo vệ khỏi lỗi truyền tải, không phải chữ ký độc lập; cần bảo vệ quyền ghi GitHub. Bản đồ offline, điều hướng, AI và cảnh báo chưa triển khai; không dùng để lái xe.

Tìm kiếm offline dùng tên OSM của node/way trong SQLite, hỗ trợ bỏ dấu; chưa hỗ trợ địa chỉ đầy đủ, phân giải mơ hồ hoặc chỉ đường. Dữ liệu có thể thiếu và lỗi; tọa độ của way là điểm đại diện.

Bộ trích xuất hiện lưu thêm dữ liệu đường và quan hệ cấm rẽ dưới dạng thô để chuẩn bị cho tính tuyến. Định dạng `road_ways.nodes` gồm các bản ghi 16 byte little-endian: ID nút int64, kinh độ int32 và vĩ độ int32 theo đơn vị 1e-7 độ. Hiện **chưa có công cụ tính tuyến hoặc diễn giải hạn chế rẽ**; dữ liệu đường không đồng nghĩa bản đồ offline.

Bộ lõi đồ thị tham chiếu `scripts/routing/motorcycle.py` và các kiểm thử là bước nghiên cứu độc lập, chưa chạy trên iPhone, chưa xử lý tất cả quy tắc OSM hoặc dữ liệu toàn quốc, và tuyệt đối không được dùng để dẫn đường thực tế. Một số hạn chế rẽ phức tạp được từ chối thay vì diễn giải tùy tiện.

Mục “Điểm OSM gần đây” trong app cho phép tra thủ công các node có tag biển báo hoặc camera tốc độ trong bán kính 2 km từ vị trí GPS gần đây. Khoảng cách tính đường chim bay, không xác định hướng hoặc đường áp dụng; danh sách có giới hạn và dữ liệu chưa xác minh, không phải cảnh báo dẫn đường hay bằng chứng không có camera/biển báo. Không xem hoặc thao tác khi đang lái xe.
