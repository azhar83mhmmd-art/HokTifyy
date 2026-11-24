import 'dart:async';
import 'dart:developer';

import 'package:streambeats/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:streambeats/core/di/service_locator.dart';
import 'package:streambeats/plugins/blocs/import/content_import_state.dart';
import 'package:streambeats/services/db/dao/playlist_dao.dart';
import 'package:streambeats/services/db/dao/track_dao.dart';
import 'package:streambeats/services/db/db_provider.dart';
import 'package:streambeats/services/plugin/plugin_service.dart';
import 'package:streambeats/src/rust/api/plugin/commands.dart';
import 'package:streambeats/src/rust/api/plugin/types.dart';
import 'package:streambeats/src/rust/api/plugin/models.dart';

const int _kResolutionConcurrency = 8;
// Update layar dibatasi supaya 500+ lagu tidak membuat UI patah-patah.
const Duration _kEmitInterval = Duration(milliseconds: 300);
const Duration _kPluginTimeout = Duration(seconds: 10);
// Mengambil daftar lagu playlist besar (ratusan/ribuan lagu, berhalaman-halaman)
// butuh waktu jauh lebih lama dari sekadar cek URL, jadi timeout-nya dipisah.
const Duration _kFetchTracksTimeout = Duration(minutes: 5);
const int _kFetchTracksMaxAttempts = 2;
const double _kMinConfidence = 0.45;
const int _kMaxCandidatesPerTrack = 5;

// Akurasi: lagu hanya DITERIMA OTOMATIS kalau lolos semua syarat di bawah.
// Sisanya tetap menampilkan kandidat, tapi baru disimpan setelah kamu memilih.
const double _kTrustConfidence = 0.80; // skor minimal (judul+artis+durasi)
const double _kTrustConfidenceNoArtist = 0.93; // bila sumber tanpa nama artis
const double _kTrustArtistSimilarity = 0.60; // kemiripan artis minimal
const int _kTrustMaxDurationDiffMs = 8000; // selisih durasi maksimal (8 dtk)

class ContentImportCubit extends Cubit<ContentImportState> {
  final PluginService _pluginService;
  final CrossPluginResolver _resolver;
  final PlaylistDAO _playlistDao;

  bool _cancelRequested = false;
  DateTime _lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void _emitProgress(List<ImportTrackEntry> tracks) {
    final now = DateTime.now();
    if (now.difference(_lastProgressEmit) < _kEmitInterval) return;
    _lastProgressEmit = now;
    final counts = _recount(tracks);
    emit(state.copyWith(
      tracks: List.unmodifiable(tracks),
      resolvedCount: counts.resolved,
      failedCount: counts.failed,
    ));
  }

  ContentImportCubit({
    PluginService? pluginService,
    CrossPluginResolver? resolver,
    PlaylistDAO? playlistDao,
  })  : _pluginService = pluginService ?? ServiceLocator.pluginService,
        _resolver = resolver ??
            CrossPluginResolver(
              pluginService: pluginService ?? ServiceLocator.pluginService,
            ),
        _playlistDao = playlistDao ?? _defaultPlaylistDao(),
        super(const ContentImportState());

  static PlaylistDAO _defaultPlaylistDao() {
    final trackDao = TrackDAO(DBProvider.db);
    return PlaylistDAO(DBProvider.db, trackDao);
  }

  Future<void> checkUrl(String pluginId, String url) async {
    _cancelRequested = false;
    emit(state.copyWith(
      phase: ImportPhase.checkingUrl,
      pluginId: pluginId,
      url: url,
      clearError: true,
    ));

    try {
      final response = await _pluginService
          .execute(
            pluginId: pluginId,
            request: PluginRequest.contentImporter(
              ContentImporterCommand.canHandleUrl(url: url),
            ),
          )
          .timeout(_kPluginTimeout);

      if (response is PluginResponse_CanHandle && response.field0) {
        await _fetchCollectionInfo(pluginId, url);
      } else {
        emit(state.copyWith(
          phase: ImportPhase.error,
          error: 'This plugin cannot handle the provided URL.',
        ));
      }
    } on TimeoutException {
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Plugin timed out while checking URL.',
      ));
    } catch (e) {
      log('checkUrl failed: $e', name: 'ContentImportCubit');
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Failed to check URL: $e',
      ));
    }
  }

  Future<void> _fetchCollectionInfo(String pluginId, String url) async {
    emit(state.copyWith(phase: ImportPhase.fetchingInfo));

    try {
      final response = await _pluginService
          .execute(
            pluginId: pluginId,
            request: PluginRequest.contentImporter(
              ContentImporterCommand.getCollectionInfo(url: url),
            ),
          )
          .timeout(_kPluginTimeout);

      if (response is PluginResponse_CollectionInfo) {
        emit(state.copyWith(
          collectionInfo: response.field0,
          phase: ImportPhase.fetchingTracks,
        ));
        await _fetchTracks(pluginId, url);
      } else {
        emit(state.copyWith(
          phase: ImportPhase.error,
          error: 'Unexpected response when fetching collection info.',
        ));
      }
    } on TimeoutException {
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Timed out fetching collection info.',
      ));
    } catch (e) {
      log('_fetchCollectionInfo failed: $e', name: 'ContentImportCubit');
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Failed to fetch collection info: $e',
      ));
    }
  }

  Future<void> _fetchTracks(String pluginId, String url) async {
    try {
      PluginResponse? response;
      for (var attempt = 1; attempt <= _kFetchTracksMaxAttempts; attempt++) {
        try {
          response = await _pluginService
              .execute(
                pluginId: pluginId,
                request: PluginRequest.contentImporter(
                  ContentImporterCommand.getTracks(url: url),
                ),
              )
              .timeout(_kFetchTracksTimeout);
          break;
        } on TimeoutException {
          if (attempt >= _kFetchTracksMaxAttempts) rethrow;
          log('getTracks timeout (percobaan $attempt), mengulang...',
              name: 'ContentImportCubit');
        }
      }

      if (isClosed || _cancelRequested) return;

      if (response is PluginResponse_ImportTracks) {
        final entries = response.field0
            .map((t) => ImportTrackEntry(sourceTrack: t))
            .toList();
        emit(state.copyWith(
          tracks: List.unmodifiable(entries),
          phase: ImportPhase.resolving,
        ));
        await _resolveTracks();
      } else {
        emit(state.copyWith(
          phase: ImportPhase.error,
          error: 'Unexpected response when fetching tracks.',
        ));
      }
    } on TimeoutException {
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Timed out fetching tracks.',
      ));
    } catch (e) {
      log('_fetchTracks failed: $e', name: 'ContentImportCubit');
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Failed to fetch tracks: $e',
      ));
    }
  }

  Future<void> _resolveTracks() async {
    final resolverPluginIds = await _getContentResolverPluginIds();
    if (resolverPluginIds.isEmpty) {
      log('No content-resolver plugins loaded; skipping resolution.',
          name: 'ContentImportCubit');
      emit(state.copyWith(phase: ImportPhase.review));
      return;
    }

    final tracks = List<ImportTrackEntry>.from(state.tracks);
    final semaphore = Semaphore(_kResolutionConcurrency);
    final futures = <Future<void>>[];

    for (var i = 0; i < tracks.length; i++) {
      final index = i;
      futures.add(
        semaphore.run(() => _resolveOneEntry(
              tracks: tracks,
              index: index,
              pluginIds: resolverPluginIds,
            )),
      );
    }

    await Future.wait(futures);

    if (!isClosed && !_cancelRequested) {
      final counts = _recount(tracks);
      log(
        'Resolution complete: ${counts.resolved} resolved, '
        '${counts.failed} failed out of ${tracks.length}',
        name: 'ContentImportCubit',
      );
      emit(state.copyWith(
        tracks: List.unmodifiable(tracks),
        resolvedCount: counts.resolved,
        failedCount: counts.failed,
        phase: ImportPhase.review,
      ));
    }
  }

  Future<void> _resolveOneEntry({
    required List<ImportTrackEntry> tracks,
    required int index,
    required List<String> pluginIds,
  }) async {
    if (isClosed || _cancelRequested) return;

    final entry = tracks[index];

    tracks[index] = entry.copyWith(status: TrackResolutionStatus.resolving);
    if (!isClosed) _emitProgress(tracks);

    try {
      final target = TrackMatchTarget.fromImport(
        title: entry.sourceTrack.title,
        artists: entry.sourceTrack.artists,
        durationMs: entry.sourceTrack.durationMs?.toInt(),
      );

      final candidates = await _resolver.resolveTrack(
        target: target,
        pluginIds: pluginIds,
        sequential: false,
        minConfidence: _kMinConfidence,
        earlyAcceptThreshold: 0.93,
        limit: _kMaxCandidatesPerTrack,
      );

      if (isClosed || _cancelRequested) return;

      if (candidates.isNotEmpty) {
        final best = candidates.first;
        final trusted = _isTrusted(target, best);
        tracks[index] = entry.copyWith(
          // Tidak terpercaya -> jangan simpan otomatis, minta dicek manual.
          status: trusted
              ? TrackResolutionStatus.resolved
              : TrackResolutionStatus.failed,
          resolvedTrack: trusted ? best.track : null,
          candidates: candidates.map((c) => c.track).toList(growable: false),
        );
      } else {
        tracks[index] = entry.copyWith(
          status: TrackResolutionStatus.failed,
          candidates: const [],
        );
      }
    } catch (e) {
      log(
        'Failed to resolve "${entry.sourceTrack.title}": $e',
        name: 'ContentImportCubit',
      );
      if (!isClosed && !_cancelRequested) {
        tracks[index] = entry.copyWith(
          status: TrackResolutionStatus.failed,
          candidates: const [],
        );
      }
    }

    if (!isClosed && !_cancelRequested) _emitProgress(tracks);
  }

  /// Cocok otomatis hanya jika judul, artis, dan durasi sama-sama meyakinkan.
  bool _isTrusted(TrackMatchTarget target, ScoredTrackCandidate best) {
    final cand = best.track;

    // 1. Durasi: kalau keduanya diketahui, selisihnya harus kecil.
    final td = target.durationMs;
    final cd = cand.durationMs;
    if (td != null && cd != null && td > BigInt.zero && cd > BigInt.zero) {
      final diff = (td - cd).abs().toInt();
      if (diff > _kTrustMaxDurationDiffMs) return false;
    }

    // 2. Tanpa nama artis di sumber -> tidak bisa diverifikasi, butuh skor
    //    sangat tinggi (praktis selalu masuk daftar cek manual).
    if (target.artistNames.isEmpty) {
      return best.confidence >= _kTrustConfidenceNoArtist;
    }

    // 3. Artis harus mirip.
    final candNames = cand.artists
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    final artistScore =
        _resolver.artistNamesSimilarity(target.artistNames, candNames);
    if (artistScore < _kTrustArtistSimilarity) return false;

    // 4. Judul sama persis (setelah dirapikan) + skor cukup, atau skor sangat tinggi.
    if (_resolver.isStrongMatch(target, cand) &&
        best.confidence >= _kTrustConfidence) {
      return true;
    }
    return best.confidence >= 0.93;
  }

  void cancelResolution() {
    if (state.phase != ImportPhase.resolving) return;
    _cancelRequested = true;
    log('Resolution cancelled by user.', name: 'ContentImportCubit');

    final counts = _recount(state.tracks);
    emit(state.copyWith(
      phase: ImportPhase.review,
      resolvedCount: counts.resolved,
      failedCount: counts.failed,
    ));
  }

  void pickCandidate(int trackIndex, int? candidateIdx) {
    final tracks = List<ImportTrackEntry>.from(state.tracks);
    if (trackIndex < 0 || trackIndex >= tracks.length) return;

    tracks[trackIndex] = tracks[trackIndex].copyWith(
      selectedCandidateIndex: candidateIdx,
    );

    final counts = _recount(tracks);
    emit(state.copyWith(
      tracks: List.unmodifiable(tracks),
      resolvedCount: counts.resolved,
      failedCount: counts.failed,
    ));
  }

  Future<void> saveToLibrary({String? customName}) async {
    final info = state.collectionInfo;
    if (info == null) return;

    emit(state.copyWith(phase: ImportPhase.saving));

    try {
      final rawName = customName?.trim().isNotEmpty == true
          ? customName!.trim()
          : info.title.trim();
      final playlistName = rawName.isNotEmpty ? rawName : 'Imported Playlist';

      final playlistId = await _playlistDao.ensurePlaylist(playlistName);

      final thumbUrl = info.thumbnailUrl;
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        await _playlistDao.updatePlaylistThumbnail(playlistId, thumbUrl);
      }

      var savedCount = 0;
      for (final entry in state.tracks) {
        final track = entry.effectiveTrack;
        if (track != null) {
          await _playlistDao.addTrackToPlaylist(playlistId, track);
          savedCount++;
        }
      }

      log('Saved $savedCount tracks to "$playlistName".',
          name: 'ContentImportCubit');

      emit(state.copyWith(
        phase: ImportPhase.done,
        resolvedCount: savedCount,
      ));
    } catch (e) {
      log('saveToLibrary failed: $e', name: 'ContentImportCubit');
      emit(state.copyWith(
        phase: ImportPhase.error,
        error: 'Failed to save playlist: $e',
      ));
    }
  }

  void reset() {
    _cancelRequested = false;
    emit(const ContentImportState());
  }

  Future<void> loadFromM3U(
    List<ImportTrackItem> tracks,
    ImportCollectionSummary summary,
  ) async {
    _cancelRequested = false;
    emit(state.copyWith(
      phase: ImportPhase.resolving,
      collectionInfo: summary,
      tracks: List.unmodifiable(
        tracks.map((t) => ImportTrackEntry(sourceTrack: t)).toList(),
      ),
      clearError: true,
    ));
    await _resolveTracks();
  }

  Future<List<String>> _getContentResolverPluginIds() async {
    final available = await _pluginService.getAvailablePlugins();
    final loadedIds = _pluginService.getLoadedPlugins().toSet();
    return available
        .where((p) =>
            p.pluginType == PluginType.contentResolver &&
            loadedIds.contains(p.manifest.id))
        .map((p) => p.manifest.id)
        .toList(growable: false);
  }

  ({int resolved, int failed}) _recount(List<ImportTrackEntry> tracks) {
    var resolved = 0;
    var failed = 0;
    for (final t in tracks) {
      if (t.isSkipped) {
        failed++;
      } else if (t.effectiveTrack != null) {
        resolved++;
      } else if (t.status != TrackResolutionStatus.pending &&
          t.status != TrackResolutionStatus.resolving) {
        failed++;
      }
    }
    return (resolved: resolved, failed: failed);
  }
}