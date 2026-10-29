# Nguồn gốc mã nguồn và dữ liệu

## Dự án được tham khảo

- URL do người dùng cung cấp: https://github.com/911273/VietHUD
- Ngày khảo sát: **2026-10-29**.
- Mô tả: firmware HUD GPS / cảnh báo offline trên ESP32, không phải dự án iOS.
- Các tài liệu được đọc để hiểu phạm vi tính năng: README, kế hoạch cảnh báo ngoại tuyến, tài liệu nền tảng, cấu hình và mô tả cấu trúc dữ liệu.
- Tại thời điểm khảo sát, thông tin license của repository không công bố giấy phép rõ ràng. Kho công khai **không đồng nghĩa với quyền sao chép hoặc khai thác thương mại**.

## Cách triển khai tại đây

- Viết mới Swift / SwiftUI, thuật toán hình học, engine cảnh báo và công cụ Python trong repository này.
- Không sao chép firmware C++, MP3, icon, binary bản đồ, camera hoặc dữ liệu thương mại từ VietHUD.
- Không tải dữ liệu camera từ các endpoint không chính thức của VIETMAP, Waze, Google hoặc nhà cung cấp khác.
- Không triển khai giả mạo đăng ký, bỏ kiểm tra license hoặc mở khóa thuê bao của ứng dụng khác.
- Không đưa tài khoản, thông tin Wi-Fi, khóa API, chứng chỉ hoặc khóa ký của dự án mẫu vào app.
- `demo-traffic.json` và CSV ví dụ là **dữ liệu hư cấu tự tạo**, đánh dấu `isDemo: true`; chỉ các fixture dữ liệu này được gắn CC0-1.0. Đây không phải tuyên bố cấp phép lại mã nguồn hoặc dữ liệu bên thứ ba.
- App icon là hình vẽ mới, tạo bằng `scripts/generate_icon.py`; UI sử dụng SF Symbols của hệ thống Apple.
- Không có thư viện Swift bên thứ ba trong runtime. Framework hệ thống: SwiftUI, MapKit, CoreLocation, AVFoundation, CryptoKit, UIKit, Foundation.

## Tên và thương hiệu

“VietMap” là tên repository do người dùng chỉ định. Sử dụng tên này trong mã không xác nhận quyền thương hiệu. Dự án không liên kết / được tài trợ bởi VIETMAP, Apple hoặc tác giả VietHUD. Trước phát hành thương mại, chủ dự án cần quyết định tên hợp pháp, quyền phân phối mã và điều khoản sản phẩm.

## Dữ liệu thực và quyền sử dụng

Mỗi bộ dữ liệu cần khai báo nguồn HTTPS, nhà cung cấp, giấy phép và ghi công. Validator chỉ xác minh các trường này tồn tại; **không thể xác minh giấy phép thực sự có hiệu lực**.

Nếu dùng OpenStreetMap, phải tuân thủ ODbL, ghi công và nghĩa vụ với cơ sở dữ liệu dẫn xuất khi áp dụng. OSM có thể thiếu biển tốc độ hoặc camera; không suy đoán dữ liệu thiếu. Nguồn VIETMAP / bên thứ ba thương mại cần hợp đồng / API / SDK chính thức và quyền xuất, lưu ngoại tuyến, phân phối lại tương ứng.

SHA-256 chỉ kiểm tra toàn vẹn. Nó không phải chữ ký số, xác minh quyền tác giả hoặc chứng nhận dữ liệu an toàn.
