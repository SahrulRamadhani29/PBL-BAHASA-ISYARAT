# LatihIsyarat Flutter

Aplikasi Android sederhana untuk menguji model klasifikasi 24 huruf statis
alfabet ASL secara lokal (on-device).

## Fitur

- Latihan bebas memakai tombol **Mulai** dan **Akhiri**, merekam video, lalu
  menampilkan rangkaian huruf di akhir sesi.
- Tampilan kamera penuh dengan kamera depan sebagai pilihan awal.
- MediaPipe menemukan tangan di seluruh frame dan crop model mengikuti posisinya.
- Ringkasan urutan huruf yang stabil setelah sesi berakhir.
- Rekaman video sesi disimpan di direktori dokumen internal aplikasi.
- MediaPipe Hand Landmarker menyaring frame tanpa tangan sebelum klasifikasi.
- Mode uji satu huruf aktif otomatis saat target dipilih, menampilkan hasil
  benar/salah secara langsung, dan tidak merekam video.
- Upload satu gambar atau banyak gambar dari galeri.
- Menu **Rumus Sign Language** berisi foto tangan nyata dan petunjuk bentuk A-Z.
- J dan Z ditandai sebagai huruf bergerak yang belum didukung model statis.
- Model TFLite float16 5,27 MiB berjalan offline.

## Menjalankan

```powershell
cd D:\PBL-BAHASA-ISYARAT
flutter pub get
flutter devices
flutter run
```

Gunakan HP Android nyata untuk menguji kamera. Izinkan akses kamera saat
diminta. Kamera depan dipilih secara default dan dapat diganti dari tombol
di kanan atas.

Panduan lengkap instalasi Flutter 3.47.2, JDK 17, Android SDK, USB debugging,
build APK, dan troubleshooting tersedia di [`REQUIREMENTS.md`](REQUIREMENTS.md).

## Kontrak model

- Input: `[1, 28, 28, 1]`, `float32`, grayscale `0-255`.
- Normalisasi `1/255` berada di dalam model.
- Output: 24 probabilitas dengan urutan label di `assets/models/labels.json`.
- J dan Z tidak tersedia pada dataset/model.

Foto referensi 24 huruf statis dipotong dari `amer_sign2.png` yang disertakan
oleh dataset Sign Language MNIST (Datamunge, Kaggle). Dataset dicantumkan
berlisensi CC0 pada halaman Kaggle. J dan Z hanya diberi petunjuk gerakan karena
tidak tersedia sebagai kelas gambar statis.

Hasil dataset 99,30% bukan jaminan akurasi kamera. Ikuti protokol pada
`CAMERA_VALIDATION.md` untuk mengukur hasil kamera pada HP, peserta, latar, dan
pencahayaan nyata.

## Pemeriksaan

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Project menggunakan JDK 17 LTS untuk kompatibilitas plugin Android. JDK 25 boleh
tetap terpasang untuk project lain.
