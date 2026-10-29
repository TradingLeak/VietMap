# Định hướng VietNav cá nhân

Tài liệu mục tiêu, không mô tả chức năng đã hoàn thành. Không dùng bản thử nghiệm để lái xe.

## Trải nghiệm
- Thiết kế SwiftUI hiện đại, lấy ảnh tham khảo làm bố cục, không sao chép tài nguyên hay dữ liệu độc quyền. Hỗ trợ Dynamic Type, tương phản, VoiceOver, giao diện sáng/tối. Kiểm thử trên phiên bản iOS và thiết bị thực tế của chủ app; không mặc định có API hay hiệu ứng đặc thù của một phiên bản iOS khi chưa kiểm chứng SDK.
- Cho chọn Apple MapKit hoặc MapLibre/OSM; giữ chung trạng thái vị trí, tuyến và cảnh báo khi chuyển bản đồ. Bản đồ OSM offline dùng dữ liệu vector được cấp phép phù hợp, không tải hàng loạt từ máy chủ tile công cộng của OSM. MapKit không bảo đảm bản đồ offline do app đóng gói.
- Ưu tiên tính năng riêng: so sánh tuyến theo thời gian ước tính, quãng đường và loại đường; hiển thị lý do lựa chọn và các dữ liệu chưa biết. Không tuyên bố tránh được camera hoặc vi phạm.

## Tìm kiếm và tính tuyến offline
- Nhập bản trích xuất OSM Việt Nam, xây chỉ mục địa danh/địa chỉ SQLite và đồ thị đường có hướng. Bảo toàn hạn chế rẽ, chiều đường, khả năng tiếp cận, loại xe, đơn vị và nguồn; xử lý quan hệ và các điều kiện theo thời gian khi hỗ trợ. Tìm tuyến bằng thuật toán đồ thị đã kiểm thử, không dựa vào mô hình ngôn ngữ để quyết định tính hợp lệ của tuyến.
- Xếp hạng nhiều phương án bằng tiêu chí rõ ràng; thời gian dựa trên dữ liệu hợp lệ và giả định minh bạch, không giả vờ có giao thông thời gian thực. Khi thiếu dữ liệu hoặc không tìm được tuyến, báo rõ; không đưa đường đi có vẻ hợp lệ nhưng chưa xác minh.
- AI trên thiết bị có thể hỗ trợ hiểu câu tìm kiếm và cá nhân hóa sau khi kiểm tra khả năng thiết bị. Đây không phải điều kiện bắt buộc để tìm đường; không gửi vị trí lên dịch vụ AI khi chưa có thiết kế và sự đồng ý phù hợp.

## Dữ liệu và cập nhật
- Quy trình dự kiến: Geofabrik PBF → xử lý, xác thực, tạo các gói dữ liệu có phiên bản → phát hành qua GitHub → app kiểm tra và tải gói tương thích → xác minh kích thước và hash → đổi phiên bản nguyên tử, giữ bản cũ nếu lỗi. Chưa triển khai.
- Cảnh báo chỉ dựa trên dữ liệu có loại và vị trí phù hợp; OSM có thể thiếu, sai hoặc cũ. Không suy mọi camera là camera xử phạt, không suy tốc độ từ dữ liệu không rõ. Ghi nguồn và tuân thủ ODbL cũng như điều khoản từng nguồn.
- Kho riêng tư cần cơ chế phân phối an toàn; không nhúng GitHub token vào app. Bản đồ, chỉ mục, đồ thị và dữ liệu cảnh báo là các gói khác nhau; bản đồ offline không tự tạo ra tính năng tìm kiếm hay dẫn đường offline.
- Mục tiêu IPA >100 MB phải đạt bằng dữ liệu cần thiết, không thêm dữ liệu đệm; kích thước và thời gian cài sẽ được đo sau khi tạo gói. Giới hạn kích thước, ký và phân phối tùy phương thức phát hành.

## Thứ tự triển khai và kiểm thử
1. Chốt giao diện, thiết kế trạng thái và điều khiển hai nguồn bản đồ.
2. Xây pipeline dữ liệu Việt Nam và định dạng gói offline; đo độ phủ, dung lượng, tính hợp lệ và hiệu năng.
3. Tìm kiếm offline, đồ thị và tính tuyến cơ bản, kiểm thử giới hạn rẽ, chiều đường, điểm không kết nối và trường hợp thiếu dữ liệu.
4. Tính nhiều phương án, xếp hạng cá nhân hóa và chỉ dẫn; tích hợp cảnh báo có mức độ tin cậy.
5. Kiểm thử tự động, mô phỏng GPS, cài đặt và chạy thực tế trên iPhone; kiểm tra lỗi mạng, nâng cấp dữ liệu, thiếu dung lượng và quyền vị trí. Không thể cam kết phần mềm không có lỗi; lỗi được ghi nhận và sửa theo kết quả kiểm thử.

## Yêu cầu vận hành dữ liệu của chủ app

Khi chủ app yêu cầu cập nhật, người phát triển/agent chạy và kiểm tra quy trình lấy, xử lý, kiểm định dữ liệu mới từ Geofabrik/OSM rồi phát hành phiên bản dữ liệu qua dự án GitHub này. App iPhone kiểm tra phiên bản và tải gói phù hợp khi mở app hoặc khi người dùng yêu cầu cập nhật; không cần cài lại IPA. Không hứa lịch cập nhật nền vì iOS không bảo đảm thời điểm thực thi. Gói phải được xác thực và cập nhật nguyên tử, giữ dữ liệu cũ nếu tải hoặc kiểm tra thất bại; hiển thị phiên bản, ngày nguồn và kết quả cập nhật. Geofabrik không bảo đảm dữ liệu biển báo, tốc độ và camera đầy đủ hoặc đúng. Quy trình này hiện chưa được triển khai.

## Bố cục và khả năng thao tác

Các nhóm thông tin và điều khiển phải có vùng bố cục riêng, không che nút khác. Đặt ưu tiên cho chỉ dẫn, tốc độ và cảnh báo; thông tin thứ cấp thu gọn hoặc cuộn khi thiếu chỗ. Bản đồ vẫn có vùng thao tác, các nút có nhãn VoiceOver và vùng chạm ít nhất 44 × 44 pt. Kiểm thử màn hình dọc/ngang, kích thước chữ lớn, nội dung dài, thông báo lỗi và số lượng cảnh báo lớn trên thiết bị thật trước khi khẳng định mọi trường hợp đều hoạt động.
