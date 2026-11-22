# Import playlist Spotify - HokTifyy (versi akurat)

Salin 5 file ini ke project (timpa yang lama), path sama persis:

1. lib/services/spotify_import_service.dart                  (BARU)
2. lib/screens/screen/library_views/import_media_view.dart   (DIUBAH: tombol + dialog)
3. lib/plugins/blocs/import/content_import_cubit.dart        (DIUBAH: cocok otomatis hanya jika terpercaya)
4. lib/services/meta_resolver/cross_plugin_resolver.dart     (DIUBAH: penalti versi slowed/sped up/8D/lofi dll)

Tidak ada dependency baru.

Ambang akurasi bisa diatur di atas content_import_cubit.dart:
  _kTrustConfidence, _kTrustArtistSimilarity, _kTrustMaxDurationDiffMs
