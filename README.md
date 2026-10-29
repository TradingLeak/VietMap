# VietNav

Khung ứng dụng iOS dẫn đường và cảnh báo giao thông cho Việt Nam, sử dụng dữ liệu OpenStreetMap (OSM). Dự án theo hướng SwiftUI, MVVM và Clean Architecture; hiện là **bản khởi tạo**, chưa phải ứng dụng dẫn đường hoàn chỉnh.

## Công nghệ

- Swift 5.9+, SwiftUI, iOS 16+.
- MapLibre Native iOS qua Swift Package Manager; bản đồ raster OSM mẫu.
- OSRM Route API qua `URLSession` và async/await; endpoint theo phương tiện được tiêm vào service.
- GRDB.swift cho SQLite, migrations và R-Tree.
- XcodeGen tạo dự án Xcode; `Package.swift` khai báo thư viện core, dependencies và tests.

## Chạy dự án

Cần macOS, Xcode 15 trở lên và [XcodeGen](https://github.com/yonaskolb/XcodeGen). Tại thư mục gốc:

```sh
xcodegen generate
open VietNav.xcodeproj
```

Chọn scheme **VietNav**, thiết bị iOS 16+ hoặc simulator và chạy. Xcode sẽ tải các Swift packages. Đổi bundle identifier và chọn Signing Team trong Xcode nếu chạy trên thiết bị thật. Chạy unit tests trên iOS simulator qua Xcode (VietNavCore phụ thuộc UIKit). Không thể tạo ứng dụng iOS cài đặt được chỉ bằng `swift run`: package cung cấp thư viện, còn application target được định nghĩa trong `project.yml`.

## Cấu trúc

- `VietNav/App`: điểm vào SwiftUI và coordinator.
- `VietNav/Core`: dịch vụ vị trí, database và audio alert manager; extensions dành cho phát triển tiếp.
- `VietNav/Features`: màn hình bản đồ với MapLibre, điều khiển zoom/vị trí/2D–3D và tự đổi style sáng/tối; navigation turn-by-turn, speed warning, tìm kiếm, báo cáo và cài đặt đều là bản thử nghiệm.
- `VietNav/Data`: model route và dữ liệu OSM; routing service và renderer nằm trong `Features/Navigation`.
- `VietNav/Resources`: asset catalog, style raster và vị trí dành cho dữ liệu ban đầu.
- `VietNav/Tests`: unit test cho core.

Luồng dự kiến: View → ViewModel/use case → repository protocol → adapter (OSRM/SQLite). Màn hình bản đồ dùng MapViewModel (ObservableObject cho iOS 16), chưa triển khai đầy đủ các use case. `OSRMRoutingService` dùng endpoint OSRM demo cho ô tô; điểm đến có thể tìm bằng Nominatim hoặc nhập tọa độ. Demo OSRM có giới hạn sử dụng, không có SLA và có thể không phù hợp cho sản xuất; cần server HTTPS tự host hoặc nhà cung cấp phù hợp, với dữ liệu Việt Nam và profile cập nhật. Tọa độ gửi tới server định tuyến, cần thông báo cho người dùng và có chính sách riêng tư.

## Quyền và vận hành

`Info.plist` khai báo mô tả quyền vị trí foreground/always và background modes location/audio. Màn hình chỉ yêu cầu **When In Use** khi người dùng nhấn nút vị trí; khi quyền đã được cấp, module vị trí theo dõi trong lúc màn hình hiển thị. Giao diện thử nghiệm có nút bắt đầu/kết thúc; `NavigationEngine` quản lý phiên vị trí và đọc chỉ dẫn bằng AVSpeechSynthesizer. Module xin When In Use trước rồi yêu cầu nâng cấp Always khi có thể; iOS quyết định có hiện prompt và có cấp Always hay không. Quyền When In Use có thể hỗ trợ một phiên vị trí nền được bắt đầu ở foreground, nhưng không bảo đảm ứng dụng được khởi chạy lại hoặc hoạt động như quyền Always. Không bắt đầu phiên trong nền. Cần kiểm thử audio session, quyền và vị trí nền trên thiết bị thật. Khai báo background mode không tự kích hoạt tính năng. Cần giải thích việc dùng vị trí và tuân thủ quy định App Store.

Style mẫu sáng và tối dùng `tile.openstreetmap.org`; style tối giảm độ sáng raster, không phải bản đồ đêm thiết kế riêng. Ghi công OSM được hiển thị trực tiếp cùng nút attribution MapLibre. Camera theo hướng di chuyển khi tốc độ đủ lớn, nếu không dùng la bàn; thao tác kéo, xoay hoặc chụm dừng chế độ bám theo cho tới khi nhấn nút vị trí. Mặc định bản đồ hiển thị Hà Nội ở zoom 17, pitch 60°. Đây là dịch vụ cộng đồng có tài nguyên hạn chế, **không phải CDN miễn phí không giới hạn**: tuân thủ [chính sách sử dụng tile OSM](https://operations.osmfoundation.org/policies/tiles/), không prefetch/offline bulk, đảm bảo attribution luôn hiển thị; trước khi phát hành hãy dùng nhà cung cấp tile phù hợp hoặc tự vận hành. Kiểm tra chính sách, hạn mức và giấy phép của mọi nguồn dữ liệu. Tính tuyến, tìm kiếm, dẫn đường turn-by-turn và cảnh báo tốc độ/giao thông đều là bản thử nghiệm; dữ liệu bản đồ offline chưa được triển khai; không dùng bản khởi tạo này để điều hướng thực tế.

## Location tracking

`LocationManager.shared` là `ObservableObject`/Combine cho iOS 16, công bố vị trí, heading, tốc độ km/h (moving average 3 mẫu), hướng kết hợp, trạng thái quyền, dẫn đường và lỗi. Gọi `startTracking()`/`stopTracking()` cho màn hình; không cần gọi stop khi chỉ chuyển ứng dụng xuống nền. Khi không dẫn đường, độ chính xác mục tiêu là 100 m ở foreground và 1 km ở background; trong phiên dẫn đường giữ `bestForNavigation` và bật cập nhật nền. Chế độ này cần entitlement/cấu hình plist tương ứng và sẽ tiêu thụ pin. Khi quyền bị từ chối hoặc hạn chế, màn hình hiển thị thông báo; người dùng có thể mở Cài đặt nếu bị từ chối.

Trên simulator, sau khi cấp quyền và bắt đầu tracking, module tự phát các điểm từ `Resources/simulated_route_hanoi.gpx` mỗi 2 giây, với tốc độ/hướng ước tính giữa các điểm. Đây là dữ liệu giả lập do module phát, không phải cấu hình nguồn vị trí toàn hệ thống của simulator; thời gian chạy nền của timer vẫn bị iOS giới hạn. Truyền `simulateOnSimulator: false` khi khởi tạo `LocationManager` riêng để dùng vị trí simulator/Xcode. Trên thiết bị thật luôn dùng Core Location. Khi không có course hoặc true heading hợp lệ, giữ hướng hợp lệ cuối cùng; simulator GPX không tạo `CLHeading` giả.

## Thu thập dữ liệu OSM bằng Overpass (offline)

`OSMData` là Swift package target độc lập, chia sẻ giữa iOS và công cụ macOS `OSMDataFetcher`; app **không tự tải** dữ liệu giao thông. Cần macOS 13+, Xcode 15+. Ví dụ từ thư mục gốc:

```sh
swift run OSMDataFetcher --help
# Thử nghiệm một vùng, một loại trước khi tải nhiều dữ liệu:
swift run OSMDataFetcher --dataset cameras --region 'Ha Noi city' --output osm-export
# Toàn bộ các vùng và loại, chỉ khi endpoint cho phép tải lớn:
swift run OSMDataFetcher --dataset all --output osm-export --endpoint https://YOUR-OVERPASS-SERVER/api/interpreter
```

Các test của `OSMDataTests` có thể chạy từ scheme package `OSMData` trong Xcode; không dùng `swift test` cho toàn package trên macOS vì `VietNavCore` phụ thuộc UIKit.

Các lựa chọn `--dataset`: `cameras`, `signals`, `speed`, `residential`, `tolls`, `railway`, `all`; `--regions` chọn file danh mục khác, `--region` lọc chính xác tên trong JSON (không phân biệt hoa thường), `--endpoint` chọn Overpass server khác. Đầu ra lần lượt là `camera_data_vn.json`, `traffic_signals_vn.json`, `speed_limits_vn.json`, `residential_zones_vn.json`, `toll_booths_vn.json`, `railway_crossings_vn.json`. Mỗi file được ghi atomically **sau khi tất cả vùng của loại đó thành công**; khi chạy `all`, các file của loại đã hoàn thành vẫn tồn tại nếu loại sau thất bại. Khi dùng `--region`, file chỉ chứa vùng đã chọn dù tên có `_vn`. Kiểm tra dữ liệu rồi mới tự sao chép vào tài nguyên app; không có dữ liệu giả hay file đầu ra tạo sẵn. Mặc định `osm-export/` bị Git bỏ qua.

Trong app, import `OSMData`, đọc `vietnam_regions.json` từ app bundle bằng `JSONDecoder` thành `VietnamRegions`, sau đó truyền `.regions` vào `OverpassAPIClient(regions:)`. `fetchSpeedLimits(bbox:)` tải một bbox; các hàm toàn quốc lần lượt truy vấn tất cả bbox và loại trùng theo **type + OSM ID**. CLI cũng loại trùng way theo ID cho maxspeed. Way có đầy đủ tag gốc và geometry từ Overpass, không tự diễn giải maxspeed thành km/h. Các tag camera/biển báo được chọn theo yêu cầu chỉ là tập con dữ liệu do cộng đồng nhập, không xác định được tất cả camera, đèn tín hiệu hay giới hạn tốc độ thực tế.

Danh mục `vietnam_regions.json` là bbox tính từ dữ liệu 63 tỉnh/thành **trước 2025**, bao gồm các geometry đảo trong nguồn; đây là phân vùng truy vấn lịch sử, không phải danh sách hay ranh giới hành chính hiện hành. Nguồn: Nguyễn Duy Liêm (2025), *Dữ liệu GIS Việt Nam*, https://github.com/nguyenduy1133/Free-GIS-Data; file được làm tròn bbox ra ngoài đến 4 chữ số thập phân. Các bbox có thể chồng lấn hoặc rất lớn (nhất là khi bao gồm đảo); chúng không phải polygon tỉnh. Kết quả lọc thêm theo area quốc gia của Overpass, không phân loại theo tỉnh và có thể chứa way vượt qua biên hoặc bỏ sót phần không có trong area OSM. Kiểm tra nguồn, chủ quyền và ranh giới trước sử dụng; nếu cần độ bao phủ tin cậy hãy chia bbox nhỏ hơn và đối chiếu dữ liệu.

Giới hạn tối đa hai request đồng thời, cách nhau ít nhất hai giây **trong cùng một tiến trình**; các lần retry cũng qua cùng gate. Cache response hợp lệ 7 ngày trong thư mục Caches của người dùng; lỗi, Overpass remark và response hỏng không được cache. Retry mạng tạm thời, HTTP 429/500/502/503/504 và remark với exponential backoff, tôn trọng `Retry-After` dạng số giây. Giới hạn/delay này không đảm bảo đáp ứng quota của Overpass, không phối hợp giữa nhiều tiến trình hay người dùng, và không phải hạn mức 10.000 cố định: hãy tuân thủ chính sách endpoint. Tải `all` ít nhất 378 request, có thể mất lâu hoặc timeout; ưu tiên self-host hoặc tải OSM extract và xử lý offline cho dataset toàn quốc. Dữ liệu OSM © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright); khi phân phối dữ liệu xuất ra cần tuân thủ attribution và các nghĩa vụ giấy phép. Không dựa vào dữ liệu này làm cảnh báo an toàn duy nhất.

## Database giao thông

`TrafficDatabase.shared` dùng `DatabaseQueue` và `DatabaseMigrator`. App mở database trên background khi khởi chạy: nếu `vietnam_traffic.sqlite` được bundle và chưa có DB trong Documents thì copy một lần; nếu không có seed thì tạo DB **rỗng**. Không ghi đè database người dùng khi cập nhật app; API OTA tùy chọn cập nhật các bảng OSM bằng transaction và giữ báo cáo người dùng, nhưng thay toàn bộ road_segments. Schema v1 nằm trong `Resources/InitialData/schema_v1.sql`, gồm traffic nodes, road segments, user reports và trigger đồng bộ R-Tree khi insert/update/delete. Các bbox của đường là cột riêng để trigger cập nhật index; hãy ghi đường qua `insertRoadSegment`, không sửa geometry trực tiếp mà bỏ qua bbox. Bản seed phải có schema và migration `v1_traffic` tương thích, không kèm WAL chưa checkpoint.

Không có sẵn file OSM toàn quốc 20–50 MB trong repo. Sau khi đã tải và kiểm chứng **đủ sáu** JSON bằng `OSMDataFetcher`, tạo seed trên máy có Python 3 + SQLite hỗ trợ R-Tree:

```sh
python3 Tools/TrafficDatabaseBuilder/build_seed.py --input osm-export --output VietNav/Resources/InitialData/vietnam_traffic.sqlite
xcodegen generate
```

Seed bị Git bỏ qua vì có thể lớn; dùng cơ chế phân phối riêng nếu cần. Builder không kiểm chứng được dữ liệu là toàn quốc: export từ `--region` chỉ tạo seed một vùng. Builder chỉ nhập camera, camera đèn đỏ, trạm thu phí, giao cắt và way có `maxspeed` là số nguyên (hoặc `km/h`); bỏ qua giới hạn phức tạp và khu dân cư chưa phân loại được chiều vào/ra. `osm_id` UNIQUE nên nếu một node có nhiều loại chỉ giữ loại gặp đầu tiên; số lượng bị bỏ qua được in ra. Không tự suy ra tốc độ hay hướng từ dữ liệu thiếu. Hãy đánh giá dữ liệu, license ODbL/attribution và quyền phân phối trước khi đóng gói; dữ liệu OSM có thể thiếu, sai hoặc cũ.

`findNodesInBoundingBox` dùng R-Tree để lấy ứng viên và so sánh tọa độ gốc để tránh sai số làm tròn float32 của SQLite. `findNearestNodes` tính khoảng cách Haversine, lọc bán kính và sắp xếp sau khi tìm bbox (kể cả qua kinh tuyến 180°). `findSpeedLimitAt` chỉ ước lượng đoạn gần nhất trong 30 m, kiểm tra hướng lệch tối đa 60° và coi đường hai chiều; không xét tầng cầu, một chiều, điều kiện hay giới hạn theo hướng. Không dùng kết quả này làm căn cứ duy nhất cho dẫn đường/cảnh báo an toàn. Không có bảo đảm <10 ms: hiệu năng phụ thuộc mật độ, thiết bị và số kết quả. `TrafficDatabaseTests` bao gồm kiểm thử logic và benchmark 100.000 điểm tùy chọn (`VIETNAV_BENCHMARK=1`) trên simulator/thiết bị.

## Routing OSRM

Trên bản đồ, cấp quyền vị trí, tìm địa điểm hoặc nhấn nút tuyến đường và nhập vĩ độ/kinh độ đích rồi chọn một tuyến. Màn hình dùng vị trí hiện tại làm điểm đi; hiển thị khoảng cách, thời gian và bước chỉ dẫn, cùng tuyến màu xanh, viền và mũi tên trong MapLibre. Khi đổi sáng/tối, source và layers được tạo lại. Đây chưa phải tìm kiếm địa điểm hay dẫn đường liên tục.

`OSRMRoutingService` triển khai `RoutingServiceProtocol`: `calculateRoute` trả tuyến đầu, `calculateRoutes(..., alternatives: true)` trả tất cả tuyến do server cung cấp; server có thể trả ít hơn 2–3 tuyến. Đầu vào gồm các waypoint theo thứ tự; GeoJSON dùng cặp longitude, latitude, khoảng cách tính bằng mét, thời gian bằng giây. Các leg được nối theo thứ tự, và hướng dẫn tiếng Việt là bản đơn giản dựa trên maneuver/modifier; maneuver lạ dùng "Tiếp tục". Không diễn giải làn đường, lối ra vòng xuyến hoặc toàn bộ ngữ nghĩa điều hướng. `bbox` là min/max tọa độ đơn giản; có thể suy biến cho tuyến thẳng hoặc rộng khi qua kinh tuyến 180°.

Cache trong bộ nhớ mỗi service giữ tối đa 64 kết quả trong 5 phút, khóa gồm endpoint, profile, tọa độ và tùy chọn; cache không tồn tại sau khi app đóng và không đảm bảo đồng bộ giao thông thời gian thực. Mặc định chỉ `.car` trỏ tới `https://router.project-osrm.org`, một server demo cộng đồng không có SLA. `.motorcycle`, `.truck`, `.bicycle` báo `unsupportedProfile` trừ khi được cấu hình bằng `OSRMEndpoint` tới **deployment có dữ liệu/profile phù hợp**. OSRM dùng profile được chuẩn bị khi xử lý dữ liệu, đổi tên path không biến một server driving thành server xe tải/xe đạp. Kiểm tra chất lượng dữ liệu Việt Nam, giới hạn tải, giấy phép, chính sách và HTTPS của nhà cung cấp trước sản xuất. Tọa độ, bao gồm vị trí hiện tại, được gửi tới server; cần đánh giá quyền riêng tư và sự đồng ý phù hợp. Không dùng demo này làm hệ thống điều hướng an toàn thực tế.

`RouteTests` dùng mock `URLProtocol` kiểm tra request, thứ tự waypoint, parse, phương án thay thế, cache và lỗi; chạy trên iOS simulator bằng Xcode.

## Navigation Engine (thử nghiệm)

Chọn tuyến trong màn hình tính đường rồi nhấn **Bắt đầu dẫn đường**; bảng trạng thái hiển thị chỉ dẫn, khoảng cách, ETA, làn (nếu có), trạng thái tính lại và nút dừng. `NavigationEngine` dùng `ObservableObject`/Combine cho iOS 16 và đăng ký `LocationManager.$currentLocation`. `startNavigation` kích hoạt phiên vị trí, `stopNavigation` hủy tác vụ, dừng phiên và giọng nói; có thể tiêm routing service, location manager và announcer trong test. Đến nơi dừng phiên vị trí và giữ bảng trạng thái cho đến khi đóng.

Engine chiếu vuông góc từng điểm lên polyline bằng xấp xỉ tọa độ cục bộ, chọn đoạn gần nhất và ưu tiên tính liên tục khi nhiều đoạn có khoảng cách tương đương. Tỷ lệ quãng đường polyline được quy đổi sang distance/duration OSRM; ETA là ước tính tỷ lệ theo duration ban đầu, **không phải** dự báo giao thông hay ước tính tốc độ hiện tại. Tiến độ không tự giảm khi xe đi lùi, và bước chuyển theo khoảng cách dọc tuyến 20 m. Mẫu GPS cũ hơn 30 giây, sai số âm hoặc quá 50 m không cập nhật tiến độ. Các mốc 1000/500/200/50 m được thông báo một lần mỗi bước; khi GPS nhảy qua nhiều mốc chỉ đọc mốc gần nhất.

Lệch tuyến được hiển thị khi khoảng cách đến polyline >50 m. Ba mẫu đủ chính xác, liên tiếp, cách nhau ít nhất một giây (khoảng cách giữa các mẫu không quá 5 giây) kích hoạt một request tính lại; thất bại giữ tuyến cũ và chờ tối thiểu 15 giây trước khi thử lại. Bộ lọc khoảng cách của GPS có thể khiến ba mẫu không đến đúng mỗi giây. Khi quay lại tuyến cũ hoặc dừng, kết quả request cũ bị hủy/bỏ qua. Các waypoint đã đi qua được ước lượng từ tiến độ polyline; các waypoint còn lại và profile được gửi lại cho server. GPS hiện tại và các điểm đến được gửi đến server khi reroute.

OSRM `intersections.lanes` được giải mã, chỉ đánh dấu khuyến nghị khi server cung cấp `valid=true`. `LaneGuidance.parseOSMTurnLanes` cũng phân tích tag thô `turn:lanes`, nhưng không tự suy diễn làn hợp lệ; dữ liệu tag thô chưa được nối từ database vào engine. Làn và chỉ dẫn có thể thiếu hoặc sai. Phát giọng nói dùng voice `vi-VN` nếu có thông qua audio manager dùng chung; hành vi chạy nền, gián đoạn và các tuyến âm thanh cần kiểm thử thiết bị thực trước khi phát hành.

Đây **không phải map-matching theo mạng đường**: tại cầu vượt, đường song song, đường lặp/giao cắt và khi quay đầu, snap, bước, waypoint và reroute có thể sai; không tự động phân biệt hướng hay tầng đường. Không sử dụng làm hệ thống điều hướng an toàn thực tế. `NavigationEngineTests` kiểm tra snap, tiến độ, thông báo, lệch tuyến, hủy reroute và waypoint với mock; chạy trên iOS simulator bằng Xcode.

## Speed Warning Engine (thử nghiệm)

`SpeedWarningEngine` là `ObservableObject`/Combine tương thích iOS 16. Nó hoạt động khi màn hình bản đồ ở foreground hoặc trong phiên `NavigationEngine`; có thể dùng độc lập bằng `start()`, `process(location:heading:)`, `stop()` và tự quản lý quyền GPS. UI hiển thị tốc độ, giới hạn **ước tính**, trạng thái vượt tốc độ và cảnh báo gần nhất. SQLite R-Tree tìm các điểm trong bán kính 2 km, sau đó lọc ngoài main thread theo khoảng cách thực, góc phía trước <60° và, nếu có, bearing hiệu lực <45°. Danh sách mặc định gồm các điểm trong 1,5 km; `warningDistance` mặc định 500 m làm nổi bật cảnh báo, `alertDistance` mặc định 300 m kích hoạt tiếng nói. Hai ngưỡng được giới hạn 0–2000 m khi sử dụng. Điểm ở đúng vị trí xe (<1 m) bị bỏ qua vì hướng tới điểm không xác định.

Chỉ dùng course GPS hợp lệ khi tốc độ >5 km/h; nếu chậm hơn dùng true heading la bàn hợp lệ, nếu không có hướng đáng tin thì không suy đoán phương hướng hay giới hạn tốc độ. Mẫu sai số >50 m bị bỏ qua, dữ liệu GPS không mới quá 10 giây không còn hiển thị, và tốc độ GPS âm/không hợp lệ hiển thị không xác định. Nếu có tốc độ hợp lệ, `isOverSpeeding` so sánh với giới hạn + `overspeedTolerance` (mặc định 5 km/h). Thời gian vượt tốc lấy từ timestamp các mẫu, reset khi GPS bị gián đoạn >5 giây, tốc độ giảm hoặc giới hạn thay đổi; cảnh báo giọng nói được thử lại sau ít nhất 3 giây.

Chỉ dùng `findSpeedLimitAt` để lấy **giới hạn đoạn đường ước tính**; không tự gán giá trị mặc định theo khu dân cư/loại đường và chưa theo dõi biển đã đi qua, vì dữ liệu hiện có không đủ để xác định giới hạn pháp lý đúng. Không có dữ liệu/không rõ hướng/lỗi database trả `nil`, không kết luận là không vượt tốc độ. Không có sẵn seed OSM nên database mặc định rỗng; cần tạo seed như hướng dẫn ở trên. `findSpeedLimitAt` chưa thực hiện map matching, không phân biệt đường một chiều, đường song song, cầu vượt, biển theo chiều hay điều kiện. Giá trị OSM có thể cũ, sai hoặc thiếu; không dùng engine này làm nguồn cảnh báo an toàn duy nhất.

Mỗi điểm có ID chỉ thông báo một lần trong 5 phút; nếu đã thông báo, còn <100 m và đang vượt ngưỡng của biển hoặc đoạn đường đã biết, có thể đọc một lần cuối. Debounce được giữ trong bộ nhớ trong phiên app, được làm sạch khi có mẫu mới sau 5 phút; không có timer riêng cho từng điểm. Ưu tiên một cảnh báo điểm mỗi mẫu, rồi đến cảnh báo vượt tốc độ. Engine và chỉ dẫn tuyến dùng chung audio manager; cảnh báo tốc độ chỉ được gửi khi audio rảnh và sẽ thử lại khi bận. Query bị trễ được coalesce về GPS mới nhất; dừng engine bỏ kết quả cũ. `SpeedWarningEngineTests` dùng mock SQLite datasource/giọng nói và đồng hồ để kiểm thử lọc hướng, tốc độ, debounce, GPS cũ và lifecycle.

## Âm thanh và giọng Việt

Vào Cài đặt → Giọng nói & âm thanh để mở cài đặt audio: bật/tắt, chọn giọng tiếng Việt đã cài, tốc độ/âm lượng và bật tắt từng nhóm chỉ dẫn, vượt tốc độ, camera, biển báo, trạm thu phí, đường sắt và thông báo khác. Cài đặt lưu trong UserDefaults. Mặc định thử `com.apple.ttsbundle.Linh-compact`, sau đó fallback voice `vi-VN`; tên/giọng nam/nữ tùy thiết bị và các voice đã tải trong iOS, không đảm bảo luôn có đủ.

`AudioAlertManager.shared` dùng một `AVSpeechSynthesizer` và `AVAudioPlayer`; bốn file CAF PCM ngắn được tạo cho dự án nằm trong `Resources/Audio`. `submit(AlertRequest)` trả `accepted`, `suppressed` hoặc `busy`: accepted chỉ có nghĩa đã được tiếp nhận, không bảo đảm âm thanh đã được nghe (ví dụ bị ngắt sau khi đã bắt đầu). Priority critical ngắt âm thanh hiện tại; high xếp trước normal theo FIFO; low chỉ nhận khi rảnh. `interruptsCurrent` chỉ ngắt request có ưu tiên không cao hơn. Hàng đợi giới hạn 16 và request có thời hạn; tắt âm thanh/xóa loại sẽ hủy tương ứng. Âm báo lỗi hoặc thiếu sẽ fallback đọc text. Các template trong `AlertTemplate` chỉ là mẫu câu, không xác minh tính chính xác của dữ liệu.

Audio session `.playback`/`.voicePrompt` với `duckOthers` và `mixWithOthers` chỉ kích hoạt khi có cảnh báo và giải phóng khi hàng đợi rỗng để hệ thống bỏ duck. Không ép output ra loa: iOS chọn route Bluetooth/CarPlay đang hoạt động. Khi interruption bắt đầu hoặc output cũ bị ngắt, request đang phát và hàng đợi bị bỏ để tránh đọc hướng dẫn cũ; sau interruption có thể nhận request mới. Duck không bảo đảm tạm dừng/tiếp tục mọi ứng dụng nhạc, và API này không tạo giao diện hay entitlement CarPlay. Cần kiểm thử trên thiết bị thật với nhạc, cuộc gọi, Bluetooth, CarPlay, khóa màn hình và nền; không khẳng định hoạt động trong mọi xe hoặc khi app bị hệ thống kết thúc. `AudioAlertManagerTests` dùng backend giả lập để kiểm thử queue, ưu tiên, hủy, fallback, persistence và interruption.

## Giao diện và tìm kiếm địa điểm

Màn hình bản đồ có banner bước rẽ, tốc độ/giới hạn ước tính, thẻ cảnh báo, thanh tiến trình, điều khiển bản đồ và nút dừng. Chọn nút tìm kiếm để nhập địa điểm; chọn kết quả mở màn hình xem trước, sau đó nhấn **Tính tuyến đường** và chọn phương án trước khi dẫn đường. Nút nhập tọa độ trên thẻ dưới cùng cho phép bỏ qua tìm kiếm. Cấp quyền vị trí bằng nút định vị trước khi tính tuyến. Các tùy chọn sáng/tối/theo hệ thống, đơn vị km/mi, âm thanh và rung nằm trong Cài đặt. Rung chỉ kích hoạt khi app đang foreground: một lần khi bắt đầu vượt tốc và một lần khi cách bước rẽ tối đa 100 m; có thể tắt trong Cài đặt.

Search sử dụng Nominatim public, gửi từ khóa khi nhấn Tìm (không autocomplete hay prefetch), tối đa một request đồng thời, cách nhau ít nhất 1,1 giây trong một tiến trình và cache SQLite trong 7 ngày. Từ khóa được gửi tới Nominatim, tọa độ reverse geocoding gửi tới Nominatim, vị trí và đích được gửi tới OSRM; cần đánh giá quyền riêng tư, attribution và [chính sách Nominatim](https://operations.osmfoundation.org/policies/nominatim/) trước phát hành. Các giới hạn trong app không bảo đảm tuân thủ tổng lưu lượng của tất cả người dùng; public Nominatim và OSRM demo không phù hợp làm backend sản xuất quy mô lớn. Nút báo cáo lưu camera/sự cố trong SQLite trên thiết bị, **chưa upload, chưa xác minh và không tự tạo cảnh báo**.

Màu giao diện mới có biến thể sáng/tối trong asset catalog; các icon dùng SF Symbols. SwiftUI previews và test mock Nominatim/định dạng được đặt trong source. Chưa có ảnh mẫu kèm yêu cầu, nên bố cục được xây dựng theo mô tả chứ không khẳng định giống ảnh. Cần kiểm thử layout, VoiceOver, Dynamic Type, rung, bản đồ, GPS, âm thanh và route trên simulator/thiết bị thật trước phát hành.

## Search, địa điểm lưu và nhập giọng nói

`NominatimSearchService` cung cấp search, reverse geocoding và autocomplete **chỉ từ lịch sử/yêu thích cục bộ**. Public Nominatim cấm autocomplete phía client, nên không có request theo từng ký tự. Category grid thực hiện tìm kiếm khi nhấn nút, không giới hạn theo vị trí hiện tại; kết quả được giới hạn Việt Nam. Rate limiter chia sẻ cho search và reverse trong cùng tiến trình, một request đồng thời và cách nhau 1,1 giây. Thao tác thủ công có cache 7 ngày và User-Agent định danh; giới hạn này không đại diện tổng lưu lượng nhiều người dùng. Kiểm tra và tuân thủ chính sách nhà cung cấp, cấu hình endpoint và contact thực trước phát hành, ưu tiên self-host/nhà cung cấp khi mở rộng. Không sử dụng public server cho bulk/systematic queries.

`SearchPersistence` dùng GRDB/SQLite riêng tại Application Support, version migration riêng: `search_cache`, `recent_places` (20 kết quả gần nhất) và `favorite_places`. Dữ liệu địa chỉ và lịch sử nằm trên thiết bị và có thể thuộc backup của hệ thống; xóa lịch sử bằng nút trong màn hình, xóa từng yêu thích bằng swipe. Nút ba chấm của kết quả cho phép lưu yêu thích hoặc gán Nhà/Công ty. Chưa có đồng bộ iCloud. Cache tồn tại tối đa 7 ngày về mặt sử dụng (entry cũ bị loại dần theo giới hạn 256, không tự xóa ngay sau khi hết hạn). Không dùng dữ liệu này làm căn cứ điều hướng an toàn duy nhất.

Microphone và quyền Speech chỉ được yêu cầu khi nhấn nút mic. Nhận dạng `vi-VN` ưu tiên on-device nếu thiết bị hỗ trợ; nếu không, iOS/Apple có thể xử lý dữ liệu giọng nói bên ngoài thiết bị. Kết quả chỉ điền ô tìm kiếm, người dùng phải chủ động nhấn Tìm mới gửi tới Nominatim. Khi ghi âm, hàng đợi cảnh báo audio bị tạm dừng/hủy để tránh tranh chấp audio session; dừng ghi hoặc đóng màn hình sẽ khôi phục khả năng phát. Cần kiểm thử quyền, âm thanh, gián đoạn, Bluetooth và giọng thực trên thiết bị trước phát hành. `SearchAndUITests` dùng mock URLProtocol và SQLite để kiểm tra parse, reverse, cache, lịch sử/yêu thích và gợi ý cục bộ.

## Background và chuẩn bị phát hành

Xem [hướng dẫn cấu hình và giới hạn](docs/PRODUCTION_SETUP.md) và [bản nháp App Store/quyền riêng tư](docs/APP_STORE.md). Đã thêm Live Activity/Widget (iOS 16.1+), thông báo nền và GPS thích ứng; các tính năng này chưa được build hoặc kiểm thử trên Xcode/thiết bị. CarPlay chỉ có khung chưa bật, chưa có hỗ trợ điều hướng; chưa tích hợp SDK crash reporting hoặc thực hiện TestFlight/tạo screenshot/video.

## Kiểm thử và cập nhật dữ liệu

Xem [kiến trúc](ARCHITECTURE.md) và [hướng dẫn test/release](docs/TESTING_RELEASE.md). Dự án được tạo bằng XcodeGen, không có sẵn `.xcodeproj` được commit. Unit/UI test targets và CI được cấu hình nhưng chưa chạy trong sandbox này. Các file GPX là tuyến giả lập, không chứng minh có camera thật. `scripts/update_osm_data.sh` tạo seed/manifest từ PBF; API OTA là lời gọi chủ động chưa nối UI/scheduler và yêu cầu backend tin cậy, kiểm thử kỹ trước phát hành.

## Đóng góp

Tạo issue mô tả lỗi/tái hiện, đề xuất thay đổi nhỏ kèm test và cập nhật tài liệu; không commit dữ liệu OSM lớn, credentials hay dữ liệu vị trí cá nhân. Trước PR chạy Xcode build/tests, lint/kiểm tra script và nêu rõ phạm vi chưa kiểm chứng. Không gửi dữ liệu giao thông chưa xác minh như dữ liệu an toàn thực tế.

## IPA thử nghiệm chưa ký

Workflow **Build unsigned IPA** build cấu hình Release cho thiết bị iOS và tải lên artifact `VietNav-unsigned-IPA` (gồm file `.ipa` và checksum SHA-256). Đây là IPA **chưa ký**, không thể cài trực tiếp: cần ký lại app, frameworks và widget extension bằng công cụ ký tương thích cùng chứng chỉ/provisioning profile hợp lệ cho thiết bị. ESign và profile phải hỗ trợ signing extension với bundle ID tương thích; Live Activity có thể không hoạt động nếu extension không được ký/cài đúng. Không đưa certificate, private key hay profile vào repo. iPhone cần iOS 16+. Build này chưa có dữ liệu traffic seed thực và chưa được kiểm thử thực tế; không sử dụng làm chỉ dẫn an toàn khi lái xe.
