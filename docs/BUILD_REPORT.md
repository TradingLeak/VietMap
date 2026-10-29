# Kết quả build đã xác minh · 2026-10-29

- **Workflow:** [iOS · Test & Unsigned IPA · run 40819971850](https://github.com/TradingLeak/VietMap/actions/runs/40819971850).
- **Kết quả:** `success` cho cả job validation và job macOS.
- **Commit mã ứng dụng:** `6fe176d57d1f2edb5ec5b84034d51ff10501f4f7`.
- **Nhánh:** `arena/aae273d6-vietmap`.
- **Phiên bản:** `1.0.0`, build `5`, minimum iOS `17.0`, kiến trúc thiết bị `arm64`.
- Chỉ tài liệu được bổ sung sau commit đã build; không sửa mã ứng dụng sau bằng chứng này.

## Kiểm thử thực sự đã chạy

| Nhóm | Kết quả |
| --- | --- |
| Công cụ Python, schema, CSV, kiểm tra IPA / diagnostics | 18 test · đạt |
| Swift core: hình học, hướng, cảnh báo, GPS, tuyến, nhật ký | 26 test · đạt |
| iOS: cài đặt, nhập dữ liệu nguyên tử, khôi phục / xóa và bản xuất tạm | 8 test · đạt |
| UI smoke: mô phỏng → HUD → dừng, màn hình quản lý dữ liệu | 2 test · đạt |
| **Tổng** | **54 test · đạt** |
| Build simulator + Release archive iPhoneOS | Đạt |
| Kiểm tra Mach-O arm64 platform iOS device, min iOS và trạng thái chưa ký | Đạt |
| Upload IPA, metadata / checksum / dSYM, test results | Đạt |

UI smoke dùng sơ đồ ngoại tuyến để không phụ thuộc tile server Apple. Không coi đây là kiểm thử mạng MapKit, GPS hoặc Bluetooth thực tế. Một lần chạy trước đã phát hiện thao tác cuộn không đưa được nút HUD vào vùng chạm; đã sửa cách cuộn kiểm thử và tắt pan cho bản đồ preview dashboard, sau đó chạy lại thành công trên commit nêu trên.

## Tải kết quả

- [**VietMap-unsigned-ipa**](https://github.com/TradingLeak/VietMap/actions/runs/40819971850/artifacts/12874253722) — ZIP artifact chứa `VietMap-unsigned.ipa`, `SHA256SUMS.txt`, `build-info.json`, `VietMap-dSYMs.zip`, `ESIGN.md`.
- [**VietMap-test-results**](https://github.com/TradingLeak/VietMap/actions/runs/40819971850/artifacts/12874607514) — log và các `.xcresult`.
- Artifact IPA hết hạn theo GitHub: `2026-11-12T05:02:23Z`. Tải về trước khi hết hạn; có thể dùng **Re-run all jobs** trên run để build lại cùng mã nguồn.
- Mã SHA-256 của chính IPA nằm trong `SHA256SUMS.txt` bên trong artifact. Không nhầm với digest ZIP artifact của GitHub.

Cần đăng nhập GitHub khi tải. **Giải nén ZIP ngoài, không đổi đuôi ZIP thành IPA.** Ký bản IPA gốc bằng chứng chỉ và profile hợp lệ của bạn theo [ESIGN.md](ESIGN.md). Không đưa vật liệu ký lên repo.

## Chưa xác minh / chưa đi kèm

- **Chưa cài trên iPhone thật hoặc ký ESign thực tế bằng profile của bạn.**
- Chưa nghiệm thu GPS đường thực, nền / khóa máy, loa Bluetooth, pin / nhiệt và toàn bộ thiết bị / iOS mục tiêu.
- Không kèm dữ liệu camera / tốc độ thương mại hoặc API / SDK VIETMAP chính thức. Fixture được đánh dấu mô phỏng, không dùng cho lái xe thật.
- Không có chứng nhận sản phẩm thương mại / an toàn hoặc cam kết không có lỗi.

Dùng [TESTING.md](TESTING.md) và [COMMERCIAL_READINESS.md](COMMERCIAL_READINESS.md) cho phần nghiệm thu còn lại.
