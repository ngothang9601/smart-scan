# Smart Scan

Ứng dụng quét tài liệu cho **iPhone và Android**, viết bằng **Flutter** (một mã nguồn chạy cả hai nền tảng).
Toàn bộ mã nguồn là viết mới, không dùng mã hay tài nguyên của bất kỳ ứng dụng thương mại nào.

## Tính năng

| Nhóm | Chi tiết |
|---|---|
| Chụp | Camera toàn màn hình, khung mép giấy hiện **trực tiếp** khi ngắm, **tự chụp** khi giấy đứng yên ~1,5 giây, đèn flash (tắt/tự động/bật/đèn pin), chế độ **một trang / nhiều trang** |
| Nhập ảnh | Chọn nhiều ảnh từ thư viện ảnh |
| Cắt | Tự nhận diện 4 góc giấy, kéo góc hoặc cạnh để chỉnh, **kính lúp** khi kéo, nút "Tự động" và "Toàn ảnh" |
| Nắn phối cảnh | Biến tứ giác nghiêng thành trang chữ nhật thẳng (homography + nội suy song tuyến) |
| Bộ lọc | Gốc, Tăng cường (làm trắng nền giấy, giữ màu mực), Làm sáng, Xám, Đen trắng; có ảnh xem trước từng bộ lọc |
| Chỉnh trang | Xoay trái/phải, cắt lại bất cứ lúc nào (luôn giữ ảnh gốc), xoá trang, vuốt qua lại giữa các trang, phóng to |
| Nhiều trang | Thêm trang vào tài liệu có sẵn, kéo thả để sắp xếp lại |
| OCR | Nhận dạng chữ **ngay trên máy, không cần mạng** (Google ML Kit, bộ chữ Latin, đọc được tiếng Việt), sao chép / chia sẻ văn bản |
| PDF | Xuất PDF khổ A4, Letter hoặc vừa ảnh; nếu đã OCR thì PDF có **lớp chữ ẩn** để tìm kiếm và bôi đen sao chép được (font Noto Sans hỗ trợ tiếng Việt) |
| Chia sẻ | Chia sẻ PDF hoặc ảnh JPG qua Zalo, Messenger, email, Drive, "Lưu vào Tệp"… |
| Thư viện | Danh sách tài liệu, tìm theo tên **và theo nội dung chữ OCR**, đổi tên, nhân bản, xoá |

## Cấu trúc mã

```
lib/
  main.dart                     Khởi động ứng dụng, giao diện Material 3 (sáng/tối)
  models/scan_document.dart     Tài liệu, trang, dòng OCR (lưu JSON)
  services/
    image_processing.dart       Nhận diện mép, nắn phối cảnh, bộ lọc, xoay (Dart thuần, chạy trong isolate)
    document_store.dart         Lưu trữ trên máy: ảnh gốc + ảnh đã xử lý + index.json
    ocr_service.dart            Nhận dạng chữ bằng ML Kit
    pdf_service.dart            Tạo PDF (có lớp chữ ẩn)
  screens/                      Thư viện, camera, cắt ảnh, chỉnh trang, chi tiết tài liệu
  widgets/quad_overlay.dart     Vẽ và kéo tứ giác, kính lúp
test/                           Kiểm thử thuật toán ảnh, lưu trữ và PDF
```

Thuật toán nhận diện mép giấy: thu nhỏ ảnh → làm mờ → biên Sobel với ngưỡng thích ứng → tìm vùng kín lớn nhất không
chạm viền ảnh → bao lồi → chọn 4 đỉnh tạo tứ giác diện tích lớn nhất. Nếu biên không khép kín thì dùng phương án dự phòng
phân ngưỡng Otsu. Viết hoàn toàn bằng Dart nên chạy giống nhau trên iOS và Android, không cần OpenCV.

## Cài đặt và chạy

Yêu cầu: Flutter 3.38 trở lên (đã thử với 3.47), Android Studio (cho Android), Xcode 16+ trên máy Mac (cho iPhone).

```bash
flutter pub get
flutter test                 # chạy kiểm thử
flutter run                  # chạy trên máy thật đang cắm cáp
```

### Android
```bash
flutter build apk --release        # tạo tệp build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # tạo .aab để đưa lên Google Play
```
Yêu cầu Android 7.0 (API 24) trở lên. Để phát hành lên Google Play cần tạo khoá ký riêng
(xem https://docs.flutter.dev/deployment/android).

### iPhone
```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace        # chọn Team ký ứng dụng trong Signing & Capabilities
flutter build ipa --release
```
Yêu cầu iOS 15.5 trở lên (do ML Kit). Cần tài khoản Apple Developer để cài lên máy thật lâu dài hoặc đưa lên App Store.

> Lưu ý: camera không chạy trên trình giả lập iOS; hãy thử trên iPhone thật.

## Quyền truy cập
- Camera: chụp tài liệu.
- Thư viện ảnh: nhập ảnh có sẵn.
- Không cần Internet: mọi xử lý (kể cả OCR) đều chạy trên máy, tài liệu không rời khỏi điện thoại trừ khi người dùng chia sẻ.

## Giấy phép tài nguyên
Font `assets/fonts/NotoSans-Regular.ttf` theo giấy phép SIL Open Font License 1.1 (xem `assets/fonts/OFL.txt`).

## Bản web
`web/smart-scan.html` là bản chạy trên trình duyệt (một tệp HTML): chọn hoặc chụp ảnh, tự nhận diện mép giấy, cắt, nắn thẳng,
bộ lọc, nhiều trang, xuất PDF. Tài liệu được lưu trong trình duyệt (IndexedDB).
