import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streambeats/blocs/library/cubit/library_items_cubit.dart';
import 'package:streambeats/core/events/global_event_bus.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:streambeats/plugins/utils/media_id.dart';
import 'package:streambeats/screens/screen/common_views/album_view.dart';
import 'package:streambeats/screens/widgets/album_filmstrip.dart';

/// Album Filmstrip untuk album yang disimpan di Library (data asli dari DB).
/// [storageKeys] = storageKey item bertipe album di Library.
class SavedAlbumsFilmstrip extends StatefulWidget {
  const SavedAlbumsFilmstrip({super.key, required this.storageKeys});
  final List<String> storageKeys;

  @override
  State<SavedAlbumsFilmstrip> createState() => _SavedAlbumsFilmstripState();
}

class _SavedAlbumsFilmstripState extends State<SavedAlbumsFilmstrip> {
  final Map<String, AlbumSummary> _resolved = {};
  List<String> _loadedFor = const [];

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SavedAlbumsFilmstrip old) {
    super.didUpdateWidget(old);
    if (!_sameKeys(old.storageKeys, widget.storageKeys)) _resolve();
  }

  bool _sameKeys(List<String> a, List<String> b) =>
      a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);

  Future<void> _resolve() async {
    final keys = List<String>.of(widget.storageKeys);
    final cubit = context.read<LibraryItemsCubit>();
    for (final k in keys) {
      if (_resolved.containsKey(k)) continue;
      try {
        final p = await cubit.resolveLibraryItem(k);
        final a = p?.album;
        if (a != null) _resolved[k] = a;
      } catch (_) {}
      if (!mounted) return;
    }
    if (mounted) setState(() => _loadedFor = keys);
  }

  @override
  Widget build(BuildContext context) {
    final albums = [
      for (final k in widget.storageKeys)
        if (_resolved[k] != null) _resolved[k]!
    ];
    if (albums.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AlbumFilmstrip(
        key: ValueKey(_loadedFor.join('|')),
        albums: albums,
        onOpen: (album, heroTag) {
          final pluginId = pluginIdOf(album.id);
          if (pluginId == null || pluginId.isEmpty) return;
          if (!requirePlugin(
              pluginId, context.read<PluginBloc>().state.loadedPluginIds)) {
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AlbumView(album: album, pluginId: pluginId, heroTag: heroTag),
            ),
          );
        },
      ),
    );
  }
}
