# VietMap · Trợ lý hành trình iOS

Ứng dụng **SwiftUI native cho iPhone / iPad, iOS 17+**, với pipeline GitHub Actions kiểm thử và xuất **`VietMap-unsigned.ipa` để bạn tự ký bằng ESign**. Không cần Mac hay chứng chỉ Apple trên GitHub để tạo bản **chưa ký**.

> **Phạm vi trung thực:** Đây là dự án độc lập, không phải ứng dụng chính thức của VIETMAP và không mở khóa tính năng trả phí của bên thứ ba. [VietHUD](https://github.com/911273/VietHUD) là firmware ESP32 được tham khảo về nhóm tính năng; không phải mã nguồn iOS. Không sao chép mã nguồn, âm thanh hoặc cơ sở dữ liệu chưa có giấy phép rõ ràng từ kho mẫu.
>
> Bản cài chỉ kèm **dữ liệu mô phỏng được đánh dấu riêng**. Muốn có cảnh báo camera / giới hạn tốc độ thực tế, bạn phải nhập dữ liệu hợp pháp, chính xác và được cập nhật. Không thể đảm bảo “không có lỗi” hoặc chứng nhận chất lượng thương mại khi chưa nghiệm thu trên thiết bị thật.

## Tính năng đã triển khai

| Nhóm | Khả năng |
| --- | --- |
| Lái xe | Tốc độ GPS, sai số / trạng thái vị trí, lọc hiển thị, đường hiện tại, cảnh báo quá tốc độ có dung sai và hysteresis |
| Cảnh báo ngoại tuyến | Camera, biển tốc độ, khu dân cư, cấm vượt, thu phí, đèn giao thông, nguy hiểm, trạm nghỉ, hầm — **theo dữ liệu người dùng nhập** |
| Động cơ cảnh báo | Chỉ mục không gian, ghép đường theo hướng, loại đường song song mơ hồ, dự đoán hành lang đường nối tiếp, khoảng báo theo tốc độ, chống lặp âm thanh |
| HUD | Chữ lớn tương phản cao, ngang / dọc, lật gương nội dung, phục hồi độ sáng khi thoát / ra nền |
| Giọng nói | Giọng tiếng Việt của iOS, chọn giọng, nghe thử, giảm âm nhạc khi đọc, loa / Bluetooth theo định tuyến iOS |
| Bản đồ | Apple MapKit thường / vệ tinh; sơ đồ vector ngoại tuyến từ đoạn đường đã nhập, không phải gói bản đồ quốc gia |
| Dẫn đường | Tìm điểm đến, tuyến ô tô và tuyến thay thế, hướng dẫn theo bước, tiến độ, phát hiện lệch tuyến và yêu cầu tính lại có giới hạn tần suất |
| Nhật ký | Lưu riêng trên thiết bị, checkpoint 15 giây, khôi phục phiên bị gián đoạn, xem tuyến, xuất GPX / CSV, xóa dữ liệu |
| Dữ liệu | Nhập JSON từ Tệp hoặc HTTPS + SHA-256, giới hạn 32 MB, kiểm tra schema / ID / tọa độ / giấy phép, thay thế tệp nguyên tử |
| Cài đặt | Ngày / đêm / tự động, loại cảnh báo, khoảng báo trước, dung sai, rung, GPS nền tùy chọn, giữ màn hình sáng |
| Mô phỏng | Không cần quyền GPS, dữ liệu giả lập tách biệt với lái xe thật, nhật ký gắn nhãn rõ ràng |
| CI | Kiểm tra cấu trúc + công cụ Python, XCTest cho lõi, XCTest lưu trữ / cài đặt iOS, UI smoke tests, archive arm64, kiểm tra cấu trúc và Mach-O của IPA |

### Các giới hạn không được che giấu

- **Apple Maps cần Internet** cho tìm kiếm, tính tuyến và tính lại; dẫn đường ô tô phụ thuộc vùng được Apple hỗ trợ. Không tạo tuyến giả khi API không cung cấp tuyến. Không có cache tải trước bản đồ Apple do ứng dụng quản lý.
- **MapKit không cung cấp giới hạn tốc độ đường cho API này.** Giới hạn chỉ lấy từ đoạn đường đủ tin cậy trong bộ dữ liệu đã nhập. Biển phía trước hoặc camera không được dùng để suy đoán giới hạn hiện tại.
- GPS cũ hơn 10 giây, sai số trên 50 m, thiếu tốc độ / hướng hoặc ghép đường mơ hồ sẽ không tạo giới hạn giả. Không có cảnh báo **không có nghĩa là** không có rủi ro.
- Không có dữ liệu VIETMAP thương mại, traffic thời gian thực quốc gia, radar, nhận dạng biển báo bằng camera, tra cứu hồ sơ phạt nguội, CarPlay hoặc cam kết làn đường chính xác đi kèm.
- GPS nền có thể bị iOS giới hạn khi tiết kiệm pin, mất quyền hoặc buộc đóng app. Chỉ kiểm thử simulator không thể xác nhận GPS / Bluetooth / nền thực tế.

## 1. Lấy IPA trực tiếp trên GitHub

Workflow: [**iOS · Test & Unsigned IPA**](https://github.com/TradingLeak/VietMap/actions).

1. Mở tab **Actions** và cho phép chạy Actions nếu GitHub yêu cầu.
2. Push mã nguồn lên `main` hoặc nhánh `arena/**` sẽ tự chạy pipeline. Với bản triển khai ban đầu, chọn run của nhánh `arena/aae273d6-vietmap`.
3. Khi workflow đã có trên **nhánh mặc định**, cũng có thể chọn **Run workflow**, chọn nhánh và nhập:
   - `bundle_id`: mặc định `vn.tradingleak.vietmap`;
   - `version`: ví dụ `1.0.0`.
   - Trước khi file workflow được merge vào nhánh mặc định, có thể chưa có nút Run workflow; run tự động theo push vẫn là cách sử dụng ban đầu.
4. Chỉ khi kiểm thử và archive thành công mới có artifact **`VietMap-unsigned-ipa`**.
5. Tải artifact `.zip`, **giải nén**, lấy **`VietMap-unsigned.ipa`**. Không đổi đuôi ZIP artifact thành IPA.
6. Cùng artifact có `SHA256SUMS.txt`, `build-info.json`, `VietMap-dSYMs.zip` và `ESIGN.md`.
7. Artifact test / log riêng: **`VietMap-test-results`**. IPA giữ 14 ngày, log giữ 7 ngày; hãy tải về trước khi hết hạn.

**Không đưa `.p12`, mật khẩu, profile hoặc API key vào repo / issue / log.** CI không cần chúng. Chứng chỉ chỉ sử dụng trên thiết bị ký của bạn.

## 2. Ký bằng ESign và cài lên iPhone

Xem [hướng dẫn ESign đầy đủ](docs/ESIGN.md).

Tóm tắt: nhập IPA vào ESign → nhập **chứng chỉ `.p12` và provisioning profile `.mobileprovision` hợp lệ của bạn** → chọn ký → dùng Bundle ID được profile cho phép → cài bản đã ký. Profile development / ad-hoc phải chứa UDID thiết bị; chứng chỉ và profile phải còn hạn, không bị thu hồi.

**IPA chưa ký không thể cài trực tiếp.** Repo không cấp chứng chỉ, không tự đăng ký UDID và không vượt cơ chế ký / cấp phép của Apple. Tên “ESign-ready” nghĩa là có cấu trúc IPA thiết bị hợp lệ, không phải đã nghiệm thu mọi phiên bản ESign / profile.

## 3. Dùng ứng dụng

1. Đọc lưu ý an toàn trên màn hình đầu tiên.
2. Bấm **Trải nghiệm mô phỏng** để kiểm tra dashboard, quá tốc độ, cảnh báo và HUD mà không xin quyền vị trí.
3. Kết thúc mô phỏng. Vào **Cài đặt → Dữ liệu giao thông** để nhập dữ liệu thực có giấy phép, nếu có.
4. Bấm **Bắt đầu lái xe**, cấp quyền vị trí chính xác. Chờ GPS ở nơi thoáng.
5. Dừng xe trước khi tìm điểm đến / sửa cài đặt. Dẫn đường chỉ sử dụng vị trí GPS thật, không sử dụng vị trí mô phỏng.
6. Kết thúc hành trình để lưu nhật ký. Xuất GPX / CSV trong tab **Hành trình**.

Không nên bật giữ sáng / HUD trong nhiều giờ trên màn hình OLED cố định. HUD tăng độ sáng khi mở; độ sáng trước đó được phục hồi khi đóng hoặc ra nền. Chỉ sử dụng điện thoại cố định an toàn, không che tầm nhìn.

## 4. Nhập dữ liệu hợp pháp

- [Schema, ví dụ và quy ước hướng](docs/DATA_FORMAT.md).
- Công cụ `scripts/convert_csv.py` chỉ dùng thư viện Python tiêu chuẩn; nhận CSV bạn có quyền sử dụng, xuất JSON đã kiểm tra và SHA-256.
- Không tải / phân phối lại các `.bin` hoặc MP3 của VietHUD chỉ vì chúng công khai trên GitHub.
- Tệp `VietMap/Resources/demo-traffic.json` luôn phải có **`isDemo: true`**. Không sửa cờ này để biến ví dụ thành dữ liệu “thực”.

## 5. Build / phát triển trên Mac

Yêu cầu Xcode 16+ và Python 3.10+; project không phụ thuộc CocoaPods hoặc package bên ngoài.

```bash
open VietMap.xcodeproj
# Chọn scheme VietMap, iPhone simulator rồi Run.

# Kiểm thử lõi độc lập với UI
swift test --package-path Packages/VietMapCore

# Tạo IPA chưa ký (macOS + iOS SDK)
BUNDLE_ID=vn.tradingleak.vietmap APP_VERSION=1.0.0 BUILD_NUMBER=1 \
  bash scripts/build_ipa.sh
# Kết quả trong artifacts/ (đã gitignore)
```

Sau khi thêm / xóa file Swift hoặc tài nguyên trong project, chạy:

```bash
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests -v
```

Project và scheme được commit sẵn; **không cần cài XcodeGen**. Bộ sinh project có tính xác định, chạy trên Linux và Mac.

## Kiến trúc

```text
VietMap/                   SwiftUI app, MapKit, CoreLocation, AVFoundation, lưu trữ
Packages/VietMapCore/       Swift package thuần Foundation: dữ liệu, hình học, cảnh báo, tuyến, GPX/CSV
VietMapTests/              XCTest: cài đặt, nhập nguyên tử, khôi phục hành trình
VietMapUITests/            UI smoke tests: mô phỏng → HUD → dừng, màn hình dữ liệu
scripts/                   Sinh project / icon, chuyển CSV, kiểm tra, đóng gói IPA
tests/                     Unit tests Python cho công cụ và kiểm tra IPA
.github/workflows/ios.yml   Validate → native tests → archive → unsigned IPA artifacts
docs/                      ESign, schema, kiểm thử, nguồn gốc, nghiệm thu thương mại
```

## Chất lượng, quyền riêng tư và phát hành

- [Quy trình kiểm thử và checklist iPhone thật](docs/TESTING.md)
- [Những việc bắt buộc trước khi thương mại hóa](docs/COMMERCIAL_READINESS.md)
- [Nguồn gốc và quyền dữ liệu](docs/PROVENANCE.md)

Không đánh đồng “CI xanh” với chứng nhận an toàn hoặc sản phẩm thương mại hoàn chỉnh. Cần kiểm thử lái xe bởi người ngồi ghế phụ / thiết bị test, xác minh dữ liệu, quyền thương hiệu và điều kiện phân phối trước khi phát hành cho khách hàng.
