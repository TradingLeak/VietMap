# Nghiệm thu trước khi dùng thương mại

**Trạng thái: nền tảng ứng dụng có triển khai tính năng; chưa được chứng nhận là sản phẩm thương mại hoàn chỉnh.** Không được quảng cáo “100% chính xác”, “không có lỗi” hoặc “đầy đủ gói VIETMAP cao cấp” dựa trên mã nguồn này.

## Những gì có thể kiểm tra tự động

- Build và test Swift package thuật toán độc lập.
- Kiểm tra schema / tọa độ / ID / hướng / giới hạn và tài nguyên.
- Kiểm tra cài đặt, nhập dữ liệu nguyên tử, phục hồi hành trình, UI mô phỏng / HUD trên simulator.
- Archive Release cho arm64 iPhoneOS, kiểm tra Mach-O platform, layout IPA, chế độ thực thi và trạng thái chưa ký.
- Kiểm tra không commit IPA / vật liệu ký vào Git.

Đây là kiểm tra kỹ thuật, không thay thế kiểm thử thiết bị hoặc xác minh dữ liệu.

## Các cổng bắt buộc trước khi phát hành

| Cổng | Việc chủ dự án cần hoàn tất |
| --- | --- |
| Quyền thương hiệu / mã | Xác minh tên sản phẩm và quyền phân phối; lựa chọn license / điều khoản thương mại phù hợp |
| Dữ liệu | Hợp đồng hoặc giấy phép camera / biển / tốc độ; phạm vi, hướng, loại xe, điều kiện thời gian, đường nhánh; SLA cập nhật |
| Bản đồ / dẫn đường | Kiểm tra Apple Maps hỗ trợ thực tế từng vùng. Nếu cần VIETMAP SDK chính thức / dẫn đường offline / traffic, mua quyền và tích hợp provider phù hợp, không chỉ đổi logo |
| Ký / phân phối | Apple provisioning hợp lệ, UDID / App ID tương ứng; nghiệm thu ESign thực; App Store cần quy trình review riêng |
| Thiết bị | GPS thật, nền / khóa máy, Bluetooth / Car audio, mất mạng, pin / nhiệt, gián đoạn cuộc gọi, quyền bị đổi, iPhone / iPad / phiên bản iOS mục tiêu |
| An toàn | Kiểm chứng false-positive / false-negative tại đường song song, giao lộ, cao tốc / đường gom, hầm, bãi đỗ. Không thao tác bởi tài xế khi di chuyển |
| Bảo mật dữ liệu | Kênh cung cấp dữ liệu đáng tin, phê duyệt phiên bản, chống dữ liệu sai; nếu cần OTA tự động, bổ sung manifest có chữ ký xác thực và quản lý khóa độc lập |
| Quyền riêng tư | Chính sách công khai phù hợp pháp luật và dịch vụ Apple; đánh giá vị trí, chia sẻ GPX/CSV, sao lưu, lưu giữ / xóa và hỗ trợ người dùng |
| Vận hành | Quy trình báo lỗi, crash symbolication qua dSYM, kiểm thử hồi quy, versioning, rollback, hỗ trợ và cập nhật |

## Những tính năng không thể tự cấp quyền

- CarPlay cần entitlement / chương trình Apple tương ứng; không thêm entitlement giả để ký ESign.
- API / dữ liệu quốc gia, traffic trực tiếp, tra cứu hồ sơ phạt nguội và gói thương mại của bên khác không đi kèm.
- Dẫn đường offline thật cần một engine định tuyến và bản đồ được cấp phép; sơ đồ vector ngoại tuyến trong app không thay thế điều này.
- iOS không cho bảo đảm GPS nền hoạt động sau khi người dùng buộc đóng app, thu hồi quyền hoặc hệ thống dừng tiến trình.

## Quyết định phát hành

Dùng checklist `TESTING.md`, ghi thiết bị / phiên bản / bộ dữ liệu / người kiểm thử và bằng chứng. Chỉ đánh dấu nghiệm thu những mục thực sự đã chạy. Các mục chưa kiểm tra phải để **CHƯA XÁC MINH**, không thay bằng lời hứa “đã đảm bảo không lỗi”.
