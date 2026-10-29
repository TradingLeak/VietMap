# Thiết kế: hiểu yêu cầu và tính tuyến trên thiết bị

**Trạng thái: thiết kế, chưa triển khai hoặc kiểm thử. Không dùng cho dẫn đường thực tế.**

## Nguyên tắc

MapKit và MapLibre/OSM chỉ là hai lớp hiển thị. Cả hai nhận cùng vị trí, đồ thị đường, kết quả tìm kiếm, lựa chọn xe máy, các tuyến và cảnh báo từ một lõi chạy trên iPhone. Không gọi Apple Directions, OSRM hay AI đám mây để thay thế lõi tính tuyến offline. Khi chuyển lớp bản đồ, giữ nguyên lộ trình và hiển thị lại bằng tọa độ địa lý. MapKit không đảm bảo tile offline; thiếu tile không làm thay đổi tính toán, nhưng có thể không có nền bản đồ để hiển thị.

AI hỗ trợ hiểu câu nói, tìm kiếm mờ và xếp hạng có giải thích; thuật toán đồ thị kiểm soát tính hợp lệ. Không để AI tự bịa địa điểm, tọa độ, đường, luật hay cảnh báo. Foundation Models/Apple Intelligence chỉ dùng khi SDK, thiết bị, ngôn ngữ và cài đặt thực tế hỗ trợ; phải kiểm tra lúc chạy, không mặc định tiếng Việt được hỗ trợ. Nhận dạng giọng nói trên thiết bị là khả năng riêng, cần kiểm tra hỗ trợ offline; luôn có phương án nhập chữ. Nếu không có AI hoặc không hiểu, dùng bộ phân tích quy tắc và hỏi lại; không tự chuyển dữ liệu lên mạng.

## Luồng yêu cầu

1. Nhận văn bản hoặc giọng nói (chỉ nhận dạng offline nếu có hỗ trợ và được cấp quyền). Hiển thị bản chép và cho phép sửa.
2. Phân tích thành cấu trúc: điểm đến, điểm dừng, chế độ xe máy, sở thích (nhanh/ngắn, tránh loại đường, tránh phí), yêu cầu khác và phần chưa chắc chắn. Danh mục được phép, giá trị và giới hạn được kiểm tra bằng mã thông thường; không cho AI tự sinh tọa độ hoặc ghi đè các ràng buộc an toàn.
3. Tra cứu chỉ mục SQLite offline, chuẩn hóa Unicode và dấu tiếng Việt, tìm tên/địa chỉ; trả danh sách ứng viên với vị trí và thông tin phân biệt. Nếu địa danh không rõ, đề nghị người dùng chọn; không âm thầm chọn một kết quả mơ hồ.
4. Xác định vị trí hiện tại hoặc điểm xuất phát được chọn. Kiểm tra chất lượng GPS, thời gian đo và khoảng cách tới đồ thị. Snap vào cạnh đường hợp lệ theo loại xe, khoảng cách và hướng; nếu không đủ tin cậy, yêu cầu chọn lại thay vì giả định.
5. Tính tuyến từ đồ thị offline đã phiên bản hóa. Chặn cạnh/hướng không cho xe máy, đường cao tốc cấm xe máy, rào chắn và hạn chế rẽ đã được dữ liệu mã hóa. Không mặc định đường thiếu tag là hoàn toàn an toàn; đánh dấu thông tin chưa biết. Quy tắc theo thời gian và phân loại pháp lý cần xử lý rõ trước khi bật; nếu không thể xác định, thông báo không chắc chắn thay vì khẳng định an toàn.
6. Tìm đường hợp lệ bằng Dijkstra hoặc A* với trạng thái gồm cạnh đến để kiểm tra turn restriction; chi phí không âm. Ước tính thời gian theo chiều dài và tốc độ hợp lệ có nguồn, nếu thiếu dùng giả định được ghi rõ; không suy tốc độ pháp lý từ tốc độ ước tính. Tạo các tuyến thay thế khác biệt bằng thuật toán k-shortest paths hoặc edge penalties; loại tuyến trùng và không hợp lệ, giới hạn số lượng và thời gian tính.
7. Xếp hạng các tuyến hợp lệ bằng trọng số người dùng: thời gian ước tính, khoảng cách, phí, loại đường và độ đầy đủ dữ liệu. AI có thể diễn giải sở thích thành trọng số trong miền cho phép; không được phép vượt ràng buộc pháp lý. Hiển thị các giá trị, giả định, dữ liệu thiếu và lý do đề xuất. Không khẳng định có thông tin ùn tắc trực tiếp.
8. Sinh chỉ dẫn từ hình học và thuộc tính đồ thị, kiểm tra tính nhất quán; phát cảnh báo chỉ khi dữ liệu có loại, vị trí và hướng phù hợp. Nếu lệch tuyến, chỉ tính lại khi đủ bằng chứng GPS và áp dụng ngưỡng chống tính lại liên tục.

## Dữ liệu và quyền riêng tư

Cần tự xây gói tìm kiếm, đồ thị và bản đồ Việt Nam từ các nguồn phù hợp, có schema, phiên bản, checksum và metadata nguồn/ngày. Dữ liệu OSM/Geofabrik có thể thiếu hoặc sai; ODbL và các điều kiện nguồn cần được tuân thủ. Cập nhật qua GitHub phải xác thực nội dung, kiểm tra tính tương thích và cài đặt nguyên tử, giữ bản trước khi lỗi. GitHub riêng tư cần giải pháp xác thực an toàn, không nhúng token trong app. Không lưu lịch sử vị trí hoặc truy vấn mặc định nếu chưa có lựa chọn rõ ràng.

## Kiểm thử bắt buộc trước khi sử dụng

- Unit: phân tích ý định, dấu tiếng Việt, địa danh trùng, graph ngắt kết nối, đường một chiều, cấm xe máy, hạn chế rẽ, ràng buộc theo thời gian, thiếu tag và dữ liệu sai định dạng.
- Tích hợp: cùng yêu cầu và cùng phiên bản dữ liệu tạo cùng kết quả trong MapKit và OSM; chuyển nền không đổi tuyến; mất mạng, tắt AI, GPS cũ/sai, không có tile MapKit, hủy và chạy lại truy vấn, gói cập nhật hỏng.
- Hiệu năng trên iPhone: dung lượng IPA và dữ liệu, thời gian tìm kiếm/tuyến, RAM, pin và điều kiện nóng máy. Thử trên tuyến thực tế có đối chiếu biển báo; đánh giá dữ liệu địa phương trước khi bật cảnh báo. Không thể hứa không có lỗi hoặc độ đầy đủ dữ liệu tuyệt đối.
