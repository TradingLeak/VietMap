# Ký VietMap IPA bằng ESign

## Bạn cần chuẩn bị

- iPhone / iPad **iOS 17 trở lên**.
- `VietMap-unsigned.ipa` lấy từ artifact của workflow thành công.
- Một bản ESign đã được cài đặt bằng phương thức hợp lệ của bạn.
- Chứng chỉ **`.p12`**, mật khẩu của chứng chỉ và **`.mobileprovision` tương thích**, còn hạn, được bạn phép sử dụng.
- Với chứng chỉ development / ad-hoc: UDID thiết bị phải có trong provisioning profile.

Dự án **không cung cấp chứng chỉ**, dịch vụ UDID hoặc phương pháp vượt thu hồi chứng chỉ. Không dùng chứng chỉ rò rỉ / không rõ nguồn. Không gửi file hoặc mật khẩu ký cho người khác trong chat, GitHub issue hay CI.

## Bước 1 · Lấy đúng file

1. Mở GitHub → repo → **Actions** → run thành công **iOS · Test & Unsigned IPA**.
2. Tải **`VietMap-unsigned-ipa`** trong phần Artifacts. GitHub yêu cầu đăng nhập để tải artifact.
3. Giải nén ZIP bên ngoài. Bên trong phải có **`VietMap-unsigned.ipa`**; không đổi tên ZIP artifact thành IPA.
4. Đối chiếu mã trong `SHA256SUMS.txt` nếu có công cụ SHA-256. `build-info.json` ghi commit, Xcode, phiên bản và mã kiểm tra.

IPA có bố cục:

```text
Payload/
  VietMap.app/
    Info.plist
    VietMap                 # Mach-O arm64 cho iPhoneOS, không phải simulator
    Assets.car
    PrivacyInfo.xcprivacy
    demo-traffic.json
    ...
```

Không có provisioning profile và chữ ký ứng dụng đi kèm. **Chưa ký = chưa thể cài.**

## Bước 2 · Nhập vật liệu ký vào ESign

1. Nhập `.p12` vào mục quản lý chứng chỉ, nhập mật khẩu trên thiết bị của bạn.
2. Nhập `.mobileprovision` tương ứng.
3. Kiểm tra loại phân phối, ngày hết hạn, App ID được phép và UDID.
4. Không nhập chứng chỉ vào repo hoặc workflow: CI được thiết kế không cần bí mật Apple.

Tên menu thay đổi giữa các phiên bản ESign; dùng thao tác tương đương với **Import / Certificates / Signature** của bản bạn đang sử dụng.

## Bước 3 · Ký và cài

1. Nhập `VietMap-unsigned.ipa` trong ESign, chọn ứng dụng, chọn **Ký / Signature**.
2. Chọn đúng chứng chỉ + profile.
3. Bundle ID mặc định là **`vn.tradingleak.vietmap`**. Nếu profile có App ID explicit khác, dùng Bundle ID được profile cấp phép. Có thể build lại với input `bundle_id` để giữ định danh nhất quán.
4. Không bật thêm entitlement không có trong profile. App không yêu cầu CarPlay, push, iCloud container, Keychain group hoặc Associated Domains.
5. Ký rồi cài bản đã ký. Nếu iOS yêu cầu, bật Developer Mode / xác nhận nhà phát triển phù hợp với loại chứng chỉ.
6. Mở app → chạy mô phỏng trước → kiểm tra giọng nói và HUD → sau đó mới cấp quyền GPS khi bắt đầu phiên thật.

Giữ nguyên Bundle ID khi cập nhật nếu muốn giữ vùng dữ liệu cũ. Đổi Bundle ID thường tạo một ứng dụng độc lập; gỡ ứng dụng cũ sẽ xóa dữ liệu cục bộ. **Xuất hành trình quan trọng trước khi đổi phương án ký.**

## Khi gặp lỗi

| Biểu hiện | Kiểm tra |
| --- | --- |
| Không thấy IPA | Run phải thành công, tải đúng artifact, giải nén ZIP bên ngoài |
| Không cài được | iOS >= 17, đủ dung lượng, đúng arm64 iPhoneOS, Bundle ID / profile / UDID phù hợp |
| Không xác minh được tính toàn vẹn | Chứng chỉ và profile còn hạn, không bị thu hồi, loại phân phối được Apple chấp nhận |
| Mở rồi thoát | Ký lại từ IPA gốc; kiểm tra log crash iOS và chữ ký; không tự thêm entitlement lạ |
| GPS không cập nhật | Bật quyền Vị trí chính xác; bắt đầu phiên lái xe; thử ngoài trời; kiểm tra quyền sau khi ký đổi Bundle ID |
| Nền / khóa máy không có GPS | Bật lựa chọn GPS nền trước phiên, kiểm tra quyền và tiết kiệm pin; không buộc đóng app |
| Không có camera / giới hạn | App không kèm dữ liệu thực. Nhập bộ dữ liệu có giấy phép, đúng vùng và đúng hướng |
| Không tính được tuyến | Cần Internet và vùng hỗ trợ ô tô của Apple Maps. Không liên quan tới việc ký IPA |
| Không có tiếng Việt | Tải giọng trong Trợ năng → Nội dung được đọc, bật cảnh báo và âm lượng / thiết bị phát đúng |

Nếu crash: ghi phiên bản iOS, mẫu máy, phiên bản / build VietMap, commit trong `build-info.json`, thao tác tái hiện và log đã loại vị trí / thông tin riêng. `VietMap-dSYMs.zip` dùng để symbolicate; không đăng công khai hành trình hoặc dữ liệu cá nhân.

**Giới hạn:** workflow kiểm tra cấu trúc IPA và build arm64, không thể xác nhận chứng chỉ của bạn, tình trạng thu hồi hoặc từng bản ESign. Cần nghiệm thu cài đặt thật theo `TESTING.md`.
