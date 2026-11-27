import 'package:flutter/material.dart';

/// Jangkar untuk transisi shared-element antara piringan di island MorphBar
/// dan sampul besar di halaman Now Playing. Dipakai oleh PlayerOverlayWrapper
/// untuk menerbangkan artwork di antara dua posisi tersebut.
class ArtworkAnchors {
  ArtworkAnchors._();

  static final GlobalKey disc = GlobalKey(debugLabel: 'island-disc');
  static final GlobalKey cover = GlobalKey(debugLabel: 'player-cover');

  /// 0..1: kapan sampul asli / piringan asli terlihat saat artwork "terbang".
  static final ValueNotifier<double> coverOpacity = ValueNotifier<double>(1);
  static final ValueNotifier<double> discOpacity = ValueNotifier<double>(1);

  /// Persegi [key] pada sistem koordinat [ancestor]; null bila belum terpasang.
  static Rect? rectIn(GlobalKey key, RenderBox ancestor) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final tl = ancestor.globalToLocal(ro.localToGlobal(Offset.zero));
    final br = ancestor
        .globalToLocal(ro.localToGlobal(ro.size.bottomRight(Offset.zero)));
    return Rect.fromPoints(tl, br);
  }

  static void reset() {
    coverOpacity.value = 1;
    discOpacity.value = 1;
  }
}
