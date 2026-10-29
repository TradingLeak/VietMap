# Chuẩn bị phát hành — bản nháp, chưa sẵn sàng để công bố

## Quyền riêng tư — nội dung cần nhà phát hành kiểm tra và bổ sung

VietNav dùng vị trí để hiển thị bản đồ, ước tính tốc độ và hướng dẫn chuyến đi, bao gồm khi app ở nền trong phiên dẫn đường. Hệ điều hành cung cấp lựa chọn quyền vị trí; người dùng có thể đổi quyền trong Cài đặt. Tọa độ xuất phát, đích và điểm trung gian được gửi tới máy chủ OSRM khi tính hoặc tính lại tuyến. Từ khóa và tọa độ reverse geocoding gửi tới Nominatim; ứng dụng hiển thị bản đồ OpenStreetMap và có thể tải tile từ máy chủ tile. Truy vấn của bạn và địa chỉ IP có thể được các nhà cung cấp này xử lý theo chính sách riêng của họ. Tìm kiếm bằng giọng nói yêu cầu microphone và Speech; nhận dạng có thể dùng dịch vụ Apple nếu không thể xử lý trên thiết bị. Không tuyên bố rằng dữ liệu vị trí không được chia sẻ.

Lịch sử tìm kiếm, yêu thích, cache, báo cáo giao thông và cài đặt được lưu trên thiết bị; một số có thể được bao gồm trong backup iOS. Xóa lịch sử và yêu thích trong màn tìm kiếm, xóa dữ liệu ứng dụng qua iOS. Live Activity và thông báo có thể hiển thị hướng dẫn/tên đường trên màn hình khóa. Sự kiện chẩn đoán hiện chỉ ghi tên cố định vào unified log trên thiết bị, không chứa tọa độ; chưa có dịch vụ crash reporting. iOS và các nhà cung cấp có thể xử lý log theo chính sách của họ.

Trước phát hành: thay đoạn này bằng chính sách thực tế do nhà phát hành duyệt; bổ sung tên pháp nhân, liên hệ, nơi xử lý/lưu trữ, thời gian lưu, quyền người dùng và liên kết chính sách các nhà cung cấp; công bố tại URL công khai và điền App Privacy chính xác. Cấu hình nhà cung cấp server/attribution phù hợp và xem lại toàn bộ luồng dữ liệu, backup, log, quyền và SDK trước khi đưa ra tuyên bố về quyền riêng tư.

## Mô tả App Store — đề xuất sau khi chức năng được kiểm chứng

VietNav giúp bạn tìm điểm đến và xem tuyến đường trên nền dữ liệu OpenStreetMap. Theo dõi hướng dẫn từng chặng, khoảng cách còn lại và cảnh báo giao thông dựa trên dữ liệu hiện có. Lưu địa điểm thường dùng và tìm bằng giọng nói tiếng Việt.

Cảnh báo và chỉ dẫn mang tính tham khảo, có thể thiếu hoặc không chính xác. Luôn tuân thủ biển báo, luật giao thông và điều kiện thực tế. Một số chức năng yêu cầu mạng và quyền vị trí. Không quảng cáo CarPlay, dữ liệu offline toàn quốc hoặc tính năng chưa xác minh.

## Tài sản và TestFlight

- Dùng simulator/thiết bị và App Store Connect xác định kích thước screenshot hiện hành; tạo ảnh thật 6.7", 6.5", 5.5" và iPad 12.9" khi các kích thước này được yêu cầu. Không thay thế bằng ảnh dựng hoặc tuyên bố đã chụp.
- Quay video thật (tối đa 30 giây theo yêu cầu) sau khi kiểm tra quy định hiện hành về App Preview, không để lộ thông tin cá nhân.
- Tạo App ID, signing, version/build, privacy URL và archive bằng Xcode; upload qua Organizer, hoàn tất beta review nếu cần, mời 100 tester qua TestFlight và ghi nhận phản hồi/thời gian thử nghiệm thực tế. Chưa thực hiện các bước này.
- Kiểm thử background GPS/quyền, âm thanh/gián đoạn, màn hình khóa/Dynamic Island, thông báo bị từ chối, Low Power/thermal, voice, routing, pin, accessibility, và kết thúc/force-quit trên thiết bị vật lý trước khi phát hành. Không khẳng định hệ thống tiếp tục chạy sau force-quit hoặc đảm bảo notification/Live Activity đúng thời gian.
