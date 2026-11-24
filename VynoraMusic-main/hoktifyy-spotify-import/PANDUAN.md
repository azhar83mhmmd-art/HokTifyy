# Import playlist Spotify - HokTifyy (versi 500 lagu)

## Cara pasang
Salin file di folder `lib/` ke project (timpa yang lama), path sama persis:

1. lib/services/spotify_import_service.dart                  (tidak berubah)
2. lib/screens/screen/library_views/import_media_view.dart   (DIUBAH: pesan petunjuk + teks dialog)
3. lib/plugins/blocs/import/content_import_cubit.dart        (DIUBAH: timeout, kecepatan, progres)
4. lib/services/meta_resolver/cross_plugin_resolver.dart     (tidak berubah)

Tidak ada dependency baru. Setelah menimpa, jalankan ulang aplikasi (rebuild, bukan hot reload).

## Yang diperbaiki
- Error "Timed out fetching tracks." pada playlist besar: timeout ambil lagu
  dulu 10 detik, sekarang 5 menit + otomatis coba ulang 1x.
- Pencocokan lagu lebih cepat (8 lagu sekaligus) dan layar tidak patah-patah
  (progres diperbarui sekali per 0,3 detik).

## Cara import 500 lagu
- Link Spotify HANYA terbaca ~100 lagu pertama (batas halaman embed Spotify).
- Untuk 500 lagu pakai salah satu:
  1. File CSV dari Exportify (exportify.net) -> tombol "Import dari file CSV Spotify".
  2. Tempel daftar lagu satu per baris, format "Artis - Judul" -> tombol "Import dari Spotify".
- Proses pencocokan 500 lagu bisa makan beberapa menit sampai belasan menit.
  Tombol batal tersedia; lagu yang sudah cocok tetap tersimpan.

## Pengaturan yang bisa diubah (content_import_cubit.dart, bagian atas)
- _kFetchTracksTimeout     batas waktu ambil daftar lagu (default 5 menit)
- _kFetchTracksMaxAttempts jumlah percobaan ambil lagu (default 2)
- _kResolutionConcurrency  jumlah lagu dicocokkan sekaligus (default 8; turunkan ke 5-6 jika banyak gagal/lambat)
- _kEmitInterval           jeda pembaruan layar (default 300 ms)
- _kTrustConfidence, _kTrustArtistSimilarity, _kTrustMaxDurationDiffMs  ambang akurasi
