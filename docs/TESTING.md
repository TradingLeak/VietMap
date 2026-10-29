# Kiểm thử và nghiệm thu

## Các lớp kiểm tra

### Có thể chạy trên Linux / Mac

```bash
python3 scripts/generate_project.py --check
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests -v
bash -n scripts/build_ipa.sh
```

Kiểm tra bộ sinh project, tài nguyên / plist / privacy manifest, demo flag, schema, CSV nguyên tử, SHA-256, chọn simulator và xác minh IPA. **Đây không phải biên dịch Swift**.

### Swift package trên Mac / CI

```bash
swift test --package-path Packages/VietMapCore --parallel
```

Các case bao gồm hình học, dữ liệu lỗi / trùng ID, vị trí cũ / sai số / timestamp đảo thứ tự, thiếu tốc độ, đường một chiều, đường song song mơ hồ, hai fix xác nhận đường, quá tốc độ / cooldown / khoảng mất GPS, hướng camera / điểm phía sau, không lấy giới hạn từ camera, loại cảnh báo bị tắt, đường nối tiếp, trip jump / GPX chia đoạn, tiến độ / lệch tuyến.

### iOS simulator trên Mac / CI

```bash
SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 scripts/select_simulator.py)"
xcodebuild test -project VietMap.xcodeproj -scheme VietMap \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

- App tests: lưu / khôi phục cài đặt, từ chối nhập lỗi mà giữ tệp cũ, demo bundled bắt buộc true, phục hồi trip và không tạo lại checkpoint đã hoàn tất, kiểm tra đầu vào tải trước khi mạng chạy, khôi phục summary bị thiếu.
- UI smoke tests: khởi động → mô phỏng không GPS → mở / đóng HUD → dừng; mở màn hình dữ liệu chưa có gói thương mại.
- Tham số `-ui-testing` bỏ onboarding và tắt giọng khi test, **không thay đổi cờ demo / engine lái thật**, không cung cấp tính năng trả phí.

### IPA

```bash
bash scripts/build_ipa.sh
python3 scripts/verify_ipa.py artifacts/VietMap-unsigned.ipa \
  --bundle-id vn.tradingleak.vietmap
```

Chỉ nhận một app `Payload/*.app`, plist iPhoneOS, executable đúng quyền thực thi, Mach-O arm64 với platform iOS device (không phải arm64 simulator), min iOS 17 và không còn chữ ký / profile của ứng dụng. Kiểm tra này không xác minh profile ESign của bạn.

## Đọc kết quả GitHub

- Workflow: **iOS · Test & Unsigned IPA**.
- `validate` phải qua trước khi job macOS chạy.
- Job macOS chạy core tests → iOS / UI tests → archive; một bước thất bại sẽ không phát hành artifact IPA mới.
- `VietMap-test-results`: log và `.xcresult`, mở trong Xcode để xem lỗi và screenshot test.
- `VietMap-unsigned-ipa`: IPA, SHA-256, metadata build, dSYM và hướng dẫn ký, chỉ khi các bước trước thành công.
- Dùng trạng thái run thực tế; có file workflow hoặc parser không lỗi **không đồng nghĩa với CI đã qua**.

## Checklist thiết bị thật — để trống cho đến khi thực hiện

Ghi mẫu máy, iOS, Bundle ID, phiên bản / build, loại profile (không ghi mật khẩu), phiên bản bộ dữ liệu và ngày / người kiểm thử. Không ghi nhật ký hoặc UDID vào issue công khai.

### Cài đặt và nâng cấp

- [ ] Ký từ IPA gốc bằng ESign, cài thành công với profile / UDID hợp lệ.
- [ ] Mở ứng dụng, đóng / mở lại không crash.
- [ ] Nâng cấp giữ Bundle ID và dữ liệu; xuất dự phòng trước khi thử gỡ / cài.
- [ ] iPhone cỡ nhỏ / lớn; iPad; xoay dọc / ngang; Dynamic Type và VoiceOver.

### GPS và sự cố quyền

- [ ] Lần đầu chưa cấp quyền: chỉ xin khi bấm bắt đầu lái.
- [ ] Từ chối / hạn chế quyền: dừng phiên, có thông báo và đường mở Settings.
- [ ] Bật vị trí chính xác ngoài trời, tốc độ so sánh thiết bị tham chiếu.
- [ ] Mất GPS > 10 s: không giữ tốc độ / giới hạn cũ như thông tin mới.
- [ ] Đổi quyền khi đang mở app / ra nền, khôi phục hợp lý.
- [ ] Không cấp GPS mà mô phỏng vẫn hoạt động; dừng mô phỏng không làm dữ liệu giả lọt vào lái thật.

### Dữ liệu / cảnh báo (chỉ kiểm thử bởi hành khách)

- [ ] Không có dữ liệu thực: không hiển thị camera hoặc giới hạn từ demo.
- [ ] JSON đúng / hỏng / quá 32 MB / checksum sai / mất mạng: không phá tệp cũ.
- [ ] Bộ dữ liệu đúng vùng, đúng hướng xe, loại xe và quy tắc áp dụng.
- [ ] Camera phía trước / phía sau / ngược chiều / đường gom / giao lộ / đường cong.
- [ ] Giới hạn không biết / đổi đường / đường song song: không giữ nhầm giới hạn.
- [ ] Quá tốc độ liên tục 2 s mới nhắc; không spam khi dao động sát ngưỡng.
- [ ] Từng loại cảnh báo và tắt từng loại; biển hết hạn chế được đọc đúng ngữ cảnh.

### Âm thanh, HUD, nền và tài nguyên

- [ ] Giọng tiếng Việt đã tải khi không có mạng.
- [ ] Loa, tai nghe, Bluetooth ô tô, cuộc gọi / Siri / nhạc và âm lượng.
- [ ] Bật / tắt giọng, kết thúc phiên phải dừng âm thanh đang đọc.
- [ ] HUD dọc / ngang / lật gương; nút đóng không bị lật; không che tầm nhìn.
- [ ] Độ sáng và khóa màn hình phục hồi khi đóng HUD / dừng phiên / ra nền.
- [ ] GPS nền bật / tắt, khóa màn hình 15–30 phút, tiết kiệm pin, không buộc đóng app.
- [ ] Chạy dài, pin / nhiệt / dung lượng thấp, dữ liệu vùng lớn; không treo UI.

### Tuyến và nhật ký

- [ ] Địa điểm / tuyến Apple thực tế tại vùng sử dụng; thông báo rõ khi API không hỗ trợ.
- [ ] Hướng dẫn bước, tuyến vòng / giao cắt, lệch tuyến và mất mạng khi tính lại.
- [ ] Không sửa điểm đến / cài đặt khi đang di chuyển.
- [ ] Lưu hành trình, checkpoint, kill / khởi động lại, khôi phục và xóa.
- [ ] GPX mở trong phần mềm tương thích; CSV UTF-8; không nối đường qua mất GPS.
- [ ] Xóa / chia sẻ / sao lưu phù hợp chính sách quyền riêng tư.

## Ghi nhận lỗi

Ghi bước tái hiện nhỏ nhất, expected / actual, commit và log đã loại thông tin cá nhân. Giữ dSYM khớp chính xác build để phân tích crash. Không gửi chứng chỉ, profile, mật khẩu, dữ liệu GPS cá nhân hoặc gói dữ liệu không được phép chia sẻ.

**Chưa chạy trên iPhone thật không được đánh dấu các checkbox trên là đã đạt.**
