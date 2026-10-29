# VietMap Traffic JSON v1

Đây là schema nhập độc lập của ứng dụng, **không phải** dữ liệu / định dạng chính thức của VIETMAP. Chỉ nhập nguồn bạn có quyền sử dụng. Tệp UTF-8, tối đa **32 MiB**, không nén, tối đa **100.000 roads và 100.000 hazards**; chia khu vực lớn thành các bản phát hành riêng. Phiên bản hiện tại sử dụng một bộ dữ liệu tại một thời điểm.

## Ví dụ hư cấu tối thiểu

```json
{
  "schemaVersion": 1,
  "id": "synthetic-example",
  "version": "1.0.0",
  "name": "Ví dụ, không dùng lái xe",
  "updatedAt": "2026-10-29T00:00:00Z",
  "source": {
    "name": "Dữ liệu tự tạo",
    "url": "https://github.com/TradingLeak/VietMap",
    "license": "CC0-1.0 (synthetic fixture only)",
    "attribution": "Ví dụ hư cấu, không phải biển báo thực tế"
  },
  "isDemo": true,
  "roads": [{
    "id": "r1",
    "name": "Đường mô phỏng",
    "start": {"latitude": 20.2500, "longitude": 105.9750},
    "end": {"latitude": 20.2580, "longitude": 105.9750},
    "speedLimit": 60,
    "direction": "both"
  }],
  "hazards": [{
    "id": "camera-example",
    "kind": "camera",
    "name": "Camera giả lập",
    "coordinate": {"latitude": 20.2530, "longitude": 105.9750},
    "heading": 0,
    "speedLimit": 60,
    "roadID": "r1",
    "isEnd": false
  }]
}
```

Ví dụ đầy đủ: [`VietMap/Resources/demo-traffic.json`](../VietMap/Resources/demo-traffic.json).

### Metadata

| Trường | Quy định |
| --- | --- |
| schemaVersion | Số nguyên `1` |
| id / version / name | Chuỗi không rỗng, dài tối đa 128 / 64 / 200 ký tự |
| updatedAt | ISO-8601 có múi giờ, không phần giây thập phân; khuyên dùng `YYYY-MM-DDTHH:mm:ssZ` |
| source | `name`, `url` HTTPS không thông tin đăng nhập, `license`, `attribution`; tối đa 2.000 ký tự mỗi trường |
| isDemo | **Bắt buộc boolean**. `true`: không bao giờ được đưa vào engine lái xe thật |
| roads / hazards | Hai mảng bắt buộc; ít nhất một mảng không rỗng |

Khai báo `isDemo: false` chỉ được thực hiện cho **dữ liệu thực đã xác minh và có quyền sử dụng**. Không chuyển cờ của fixture ví dụ để app phát cảnh báo giả.

### Đoạn đường `roads`

- `id`: chuỗi duy nhất, 1–128 ký tự; `name`: chuỗi tối đa 200 ký tự (có thể rỗng).
- `start` / `end`: WGS-84 độ thập phân; vĩ độ -85…85, kinh độ -180…180; mọi số phải hữu hạn.
- Mỗi đoạn thẳng dài 1…5.000 m; đường cong phải chia theo hình học. Không dùng một đoạn thẳng xuyên qua nhiều nút giao. Chênh kinh độ hai đầu <= 1°.
- `direction`: `both`, `forward` (start → end), hoặc `backward` (end → start).
- `speedLimit`: số nguyên 5…160 **km/h**, hoặc `null` khi không biết. **Không dùng 0** như một giới hạn hợp lệ.
- Hai hướng có giới hạn khác nhau: dùng hai bản ghi hướng riêng, không đặt nhầm thành hạn chế một chiều pháp lý.
- Các endpoint cần khớp nhau; bộ dự đoán chỉ nối đầu đường cách nhau <= 3 m, bỏ nhánh rẽ quá lớn / mơ hồ. Chất lượng mạng đầu vào quyết định độ đúng của dự đoán.
- Không làm phẳng quy tắc theo giờ, thời tiết, loại xe hoặc hạn chế có điều kiện thành một con số chung. Schema v1 không mô hình hóa các điều kiện đó; để `null` / loại đoạn khỏi tập phù hợp hoặc chuẩn bị riêng bộ dữ liệu đúng phạm vi sử dụng.

### Điểm cảnh báo `hazards`

| Trường | Ý nghĩa |
| --- | --- |
| id | ID duy nhất trong hazards, 1–128 ký tự |
| kind | `camera`, `speedLimit`, `residential`, `noOvertaking`, `toll`, `trafficLight`, `danger`, `restArea`, `tunnel` |
| name | Tối đa 200 ký tự, có thể rỗng |
| coordinate | WGS-84, giới hạn như roads |
| heading | **Hướng DI CHUYỂN của xe được áp dụng**, độ từ Bắc theo chiều kim đồng hồ 0…<360; `null` nếu chưa biết / hai hướng |
| speedLimit | Số nguyên km/h 5…160 hoặc `null` |
| roadID | ID đoạn liên quan hoặc `null`; nếu khai báo phải có trong roads |
| isEnd | Boolean bắt buộc; `true` cho hết khu vực / hết hạn chế |

**Quan trọng:** nhiều nguồn ghi hướng camera “nhìn về”, khác 180° với hướng xe. Công cụ không tự đảo vì mỗi nguồn có quy ước riêng. Phải chuẩn hóa từ tài liệu nhà cung cấp. Không gắn sai đoạn cho đường song song.

Không lấy `hazard.speedLimit` làm giới hạn của đoạn hiện tại. Các biển tốc độ chỉ được báo là biển phía trước; giới hạn hiện tại lấy từ road đủ tin cậy sau ít nhất hai fix liên tiếp.

## Chuyển CSV bạn được phép sử dụng

Cột roads:

```csv
id,name,start_lat,start_lon,end_lat,end_lon,speed_limit,direction
r1,Đường mô phỏng,20.25,105.975,20.258,105.975,60,both
```

Cột hazards:

```csv
id,kind,name,lat,lon,heading,speed_limit,road_id,is_end
c1,camera,Camera giả lập,20.253,105.975,0,60,r1,false
```

Bỏ trống `speed_limit`, `heading`, `road_id` nếu không biết. `is_end` nhận `true/false` hoặc `1/0`. Dấu phẩy trong tên phải được quote theo CSV chuẩn. Có thể chỉ cung cấp `--roads` hoặc chỉ `--hazards`.

Chạy thử với fixture hư cấu đi kèm:

```bash
python3 scripts/convert_csv.py \
  --roads docs/examples/roads.demo.csv \
  --hazards docs/examples/hazards.demo.csv \
  --output private-data/demo-example.json \
  --id synthetic-example --version 1.0.0 --name 'Ví dụ mô phỏng' \
  --source-name 'Dữ liệu tự tạo' \
  --source-url https://github.com/TradingLeak/VietMap \
  --license 'CC0-1.0 (synthetic fixture only)' \
  --attribution 'Hư cấu, không sử dụng khi lái xe thật' \
  --demo
```

Đối với dữ liệu thực của bạn, đổi các đường dẫn / metadata đúng hợp đồng và sử dụng `--real-data` để xác nhận. **Không dùng `--real-data` với file ví dụ.** Công cụ kiểm tra toàn bộ trước khi ghi tệp, thay thế nguyên tử, in SHA-256. Dữ liệu riêng nằm trong `private-data/` được gitignore.

## Cập nhật qua HTTPS + SHA-256

1. Xuất JSON đã kiểm tra; nhà cung cấp lưu công khai qua HTTPS theo giấy phép.
2. Lấy checksum từ kênh tin cậy độc lập với tệp tải.
3. Trong app nhập URL + SHA-256 rồi xác nhận tải khi **đã kết thúc phiên lái xe**.
4. App kiểm tra HTTPS cả khi redirect, HTTP 200, giới hạn dung lượng, checksum, schema và quan hệ ID. Tệp cũ chỉ bị thay sau khi kiểm tra thành công.
5. Khi lỗi tải / checksum / schema, tệp cũ được giữ. Khi app bị dừng lúc ghi, cơ chế ghi nguyên tử tránh một tệp JSON ghi dở thay cho tệp cũ.

SHA-256 **không phải chữ ký xác thực nhà cung cấp**, không chống được nguồn cập nhật bị chiếm nếu checksum cũng lấy từ đó. Không có OTA tự động hoặc khóa xác thực chính thức nào được giả định. Trước thương mại hóa nên xây dựng manifest ký số và quy trình phê duyệt dữ liệu nếu cần tự động hóa.

## Hành vi an toàn và giới hạn thuật toán

- Chỉ mục ô địa lý 0,01° giúp giới hạn tìm kiếm lân cận, không scan toàn quốc mỗi fix.
- Ghép đoạn theo khoảng cách / hướng; nếu hai ứng viên gần nhau và khác thông tin, trả về không xác định thay vì chọn bừa.
- Chỉ báo phía trước cùng hướng và gần hành lang dự đoán. Ở ngã rẽ mơ hồ có thể bỏ cảnh báo; khi không ghép được đường chỉ cảnh báo điểm gần trục di chuyển, không tạo giới hạn đường.
- Có thể bỏ sót ở cua gắt, giao lộ phức tạp, đường song song, hầm và mất GPS. Không có thuật toán này nào chứng nhận vị trí làn xe hoặc bảo đảm không báo sai.
- `isEnd` là mô tả cảnh báo, không duy trì một trạng thái pháp lý qua nhiều con đường.
- Đường trong sơ đồ ngoại tuyến được giới hạn số lượng để giữ UI nhẹ; đây không phải nền bản đồ đầy đủ.
