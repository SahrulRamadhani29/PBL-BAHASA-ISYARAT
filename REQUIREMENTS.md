# Kebutuhan dan Cara Menjalankan LatihIsyarat

Dokumen ini digunakan oleh seluruh anggota tim untuk menyiapkan komputer,
menghubungkan HP Android, dan menjalankan aplikasi dengan lingkungan yang sama.
Flutter SDK, JDK, dan Android SDK harus dipasang secara global di komputer,
bukan disalin ke dalam folder project.

## 1. Spesifikasi lingkungan yang digunakan

| Komponen | Versi project |
| --- | --- |
| Sistem operasi pengembangan | Windows 11 64-bit |
| Flutter | 3.47.2 stable |
| Dart | 3.13.2, sudah termasuk dalam Flutter |
| JDK | Microsoft OpenJDK 17 LTS |
| Android SDK | API 36 dan Build Tools 36.0.0 |
| Gradle | 9.3.1, diunduh otomatis oleh wrapper |
| Android Gradle Plugin | 9.1.0 |
| Kotlin plugin | 2.4.0 |
| Minimum Android pada HP | Android 7.0 / API 24 |
| Model AI | TensorFlow Lite float16, sekitar 5.27 MiB |

JDK 25 boleh tetap terpasang untuk project lain, tetapi Flutter untuk project
ini harus diarahkan ke JDK 17.

## 2. Software yang harus diinstal

### Git

```powershell
winget install --id Git.Git -e
```

### JDK 17

```powershell
winget install --id Microsoft.OpenJDK.17 -e
```

Setelah instalasi, cari lokasi JDK 17:

```powershell
Get-ChildItem "C:\Program Files\Microsoft" -Directory | Where-Object Name -Like "jdk-17*"
```

Arahkan Flutter ke folder yang ditemukan. Contoh:

```powershell
flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
```

Verifikasi Java yang dipakai Flutter:

```powershell
flutter doctor -v
```

Pada bagian `Android toolchain`, `Java binary` harus menunjuk ke JDK 17.
Perintah `java -version` di terminal boleh saja masih menunjukkan JDK lain;
yang menentukan proses build Flutter adalah hasil `flutter doctor -v`.

### Flutter 3.47.2

Unduh Flutter stable untuk Windows, ekstrak ke folder global seperti:

```text
C:\src\flutter
```

Tambahkan `C:\src\flutter\bin` ke environment variable `Path`, lalu cek:

```powershell
flutter --version
flutter doctor -v
```

Project dibuat dan diuji dengan Flutter 3.47.2. Jika anggota tim sudah memakai
versi stable yang lebih baru dan terjadi masalah build, samakan kembali ke
Flutter 3.47.2.

### Android Studio dan Android SDK

Instal Android Studio, lalu melalui **SDK Manager** instal:

- Android SDK Platform 36
- Android SDK Build-Tools 36.0.0
- Android SDK Platform-Tools
- Android SDK Command-line Tools terbaru

Terima lisensi Android:

```powershell
flutter doctor --android-licenses
```

Jawab `y` sampai selesai. Setelah itu pastikan `flutter doctor -v` tidak
menampilkan error pada Android toolchain.

### VS Code

Instal extension berikut:

- Flutter
- Dart

## 3. Mengambil dan menyiapkan project

Masuk ke folder project, lalu unduh dependency:

```powershell
cd D:\PBL-BAHASA-ISYARAT
flutter pub get
flutter analyze
flutter test
```

Dependency utama didefinisikan di `pubspec.yaml`. Versi dependency hasil
resolusi dikunci di `pubspec.lock`, sehingga file tersebut harus dibagikan dan
disimpan di repository. Jangan menjalankan `flutter pub upgrade` tanpa
koordinasi tim karena perintah itu dapat mengubah versi package.

Package utama yang digunakan:

| Package | Versi terkunci | Kegunaan |
| --- | --- | --- |
| camera | 0.12.1 | Preview kamera, stream frame, dan rekaman video |
| hand_landmarker | 3.1.0 | Memastikan tangan terdeteksi sebelum klasifikasi |
| tflite_flutter | 0.12.1 | Menjalankan model AI secara on-device |
| image_picker | 1.2.3 | Memilih satu atau banyak gambar |
| image | 4.9.2 | Mengolah gambar menjadi input 28x28 grayscale |
| path_provider | 2.1.6 | Menentukan lokasi penyimpanan rekaman |

Tidak perlu menginstal package tersebut satu per satu. `flutter pub get` akan
menginstal semuanya berdasarkan `pubspec.yaml` dan `pubspec.lock`.

## 4. Mengaktifkan USB debugging di HP

1. Buka **Pengaturan > Tentang ponsel**.
2. Ketuk **Nomor bentukan/Build number** tujuh kali sampai mode pengembang aktif.
3. Buka **Opsi pengembang/Developer options**.
4. Aktifkan **USB debugging**.
5. Sambungkan HP menggunakan kabel data, bukan kabel yang hanya bisa mengisi daya.
6. Pilih mode USB **Transfer file/MTP** jika tersedia.
7. Tekan **Izinkan/Allow** saat HP menampilkan dialog sidik jari RSA komputer.

Pada beberapa HP vivo, menu berada di **Pengaturan > Pengelolaan sistem > Opsi
pengembang**. Nama menu dapat berbeda menurut versi sistem.

Periksa koneksi dari terminal:

```powershell
flutter devices
```

Status yang benar menampilkan nama HP dan platform `android-arm64`. Jika muncul
`unauthorized`, buka kunci layar HP dan izinkan dialog USB debugging.

## 5. Menjalankan aplikasi di HP

Pastikan terminal berada di folder project:

```powershell
cd D:\PBL-BAHASA-ISYARAT
flutter pub get
flutter devices
flutter run
```

Jika ada lebih dari satu perangkat, gunakan ID yang muncul dari
`flutter devices`:

```powershell
flutter run -d ID_PERANGKAT
```

Contoh HP pengembangan saat ini:

```powershell
flutter run -d 33a40574
```

Build pertama dapat memerlukan beberapa menit karena Gradle dan library native
MediaPipe harus dikompilasi. Build berikutnya biasanya lebih cepat. Jangan cabut
kabel sampai instalasi selesai dan aplikasi terbuka.

Perintah saat `flutter run` aktif:

- `r`: hot reload setelah perubahan kecil pada kode.
- `R`: hot restart aplikasi.
- `q`: hentikan proses run.

Saat pertama dibuka, izinkan akses kamera. Model berjalan secara offline dan
tidak mengunggah gambar ke server.

## 6. Cara menggunakan aplikasi

### Kamera - latihan bebas

1. Buka menu **Kamera**.
2. Pastikan seluruh telapak dan jari terlihat di dalam frame serta pencahayaan cukup. Tangan tidak harus berada di tengah.
3. Tekan **Mulai**.
4. Peragakan huruf statis satu per satu dan beri jeda/perubahan pose antarhuruf.
5. Tekan **Akhiri**.
6. Urutan huruf stabil ditampilkan setelah sesi selesai.

Selama sesi, aplikasi merekam video sekaligus menganalisis frame. Rekaman disimpan
di direktori dokumen internal aplikasi pada HP; rekaman tidak masuk ke folder
source project. Model hanya mengenali 24 huruf statis. J dan Z tidak dikenali
karena membutuhkan gerakan.

### Kamera - uji satu huruf

1. Pilih `MODE UJI: HURUF ...` dari pemilih mode.
2. Deteksi berjalan otomatis tanpa menekan tombol Mulai.
3. Tampilkan bentuk tangan; prediksi, status benar/salah, dan keyakinan model
   muncul langsung pada layar.
4. Tekan **Reset hasil** untuk mengulang hitungan huruf yang sama, atau pilih
   huruf lain untuk memulai pengujian baru.

Mode ini hanya menganalisis stream kamera dan tidak merekam video. Pilih kembali
`MODE: LATIHAN BEBAS` untuk menghentikan deteksi otomatis.

### Upload gambar

Pilih satu atau beberapa gambar dari galeri. Hasil setiap gambar dan urutan
gabungannya akan ditampilkan. Mode gambar tidak menambahkan spasi otomatis.

### Rumus ASL

Menu ini berisi foto referensi bentuk tangan A-Z. Foto tersedia untuk 24 huruf
statis, sedangkan J dan Z ditampilkan sebagai huruf berbasis gerakan.

## 7. Membuat APK

APK debug untuk pengujian:

```powershell
flutter build apk --debug
```

APK release yang lebih kecil:

```powershell
flutter build apk --release --split-per-abi
```

Hasil split APK untuk sebagian besar HP modern adalah:

```text
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Konfigurasi release saat ini masih menggunakan debug key. Sebelum aplikasi
didistribusikan resmi atau diunggah ke Play Store, buat release keystore dan
ubah signing configuration.

## 8. Troubleshooting

### Semua kode merah di VS Code

```powershell
flutter pub get
```

Lalu tekan `Ctrl+Shift+P` dan jalankan **Dart: Restart Analysis Server** atau
**Developer: Reload Window**.

### HP tidak terdeteksi

```powershell
adb kill-server
adb start-server
flutter devices
```

Jika masih tidak terdeteksi, ganti kabel/port USB, instal driver USB produsen HP,
cabut dan sambungkan ulang kabel, lalu setujui kembali dialog RSA di HP.

### Ada lebih dari satu ADB

Gunakan ADB dari Android SDK dan letakkan `platform-tools` lebih awal di `Path`:

```text
%LOCALAPPDATA%\Android\Sdk\platform-tools
```

Beberapa aplikasi seperti scrcpy membawa ADB sendiri dan dapat menimbulkan
konflik bila versinya berbeda.

### Error versi Java/JVM

```powershell
flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
flutter doctor -v
flutter clean
flutter pub get
```

Pastikan `Java binary` pada `flutter doctor -v` menggunakan JDK 17.

### Ruang penyimpanan membesar

Folder `build` dan `.dart_tool` adalah cache hasil kompilasi, bukan bagian utama
project. Bersihkan jika diperlukan:

```powershell
flutter clean
flutter pub get
```

Jangan menjalankan `flutter clean` ketika proses build atau `flutter run` masih
aktif. Setelah clean, `flutter pub get` diperlukan agar editor kembali mengenali
semua package.

## 9. Checklist sebelum mengirim perubahan

```powershell
flutter pub get
flutter analyze
flutter test
```

Pastikan ketiganya selesai tanpa error. Jangan mengirim folder `build`,
`.dart_tool`, Android SDK, Flutter SDK, atau JDK ke repository.
