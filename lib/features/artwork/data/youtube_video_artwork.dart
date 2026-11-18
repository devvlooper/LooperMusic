import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';

/// A YouTube video shown as moving artwork, by its stream URL.
class YoutubeArtworkVideo {
  const YoutubeArtworkVideo({
    required this.videoId,
    required this.userAgent,
    required this.synced,
  });

  final String videoId;
  final String userAgent;

  /// The video runs as long as the song (within 2.5 s): it follows the
  /// song's position. Otherwise it loops on its own as a backdrop.
  final bool synced;
}

/// The song's own YouTube Music video as moving artwork (online songs).
///
/// A song row is an audio track whose "video" is its still cover, so its
/// music video is found through the Song / Video toggle; official videos
/// play as they are; fan uploads (lyric videos, edits) are skipped.
abstract final class YoutubeVideoArtwork {
  static const _tag = 'YoutubeVideoArtwork';
  static const _counterpartKey = 'yt_video_counterpart_v1';

  static final _byUrl = <String, YoutubeArtworkVideo>{};
  static final _resolved = <String, (AnimatedArtwork, DateTime)>{};
  static final _none = <String>{};
  static final _inFlight = <String, Future<AnimatedArtwork?>>{};
  static Map<String, dynamic>? _counterparts;

  /// How to play [url] when it is one of these videos, else null.
  static YoutubeArtworkVideo? infoFor(String url) => _byUrl[url];

  /// The video for [song] as an [AnimatedArtwork] (its URL in every slot),
  /// or null: not online, no video, or YouTube is holding us back.
  static Future<AnimatedArtwork?> resolve(Song song) {
    final id = song.videoId;
    if (id == null || _none.contains(id)) return Future.value();
    final hit = _resolved[id];
    if (hit != null && DateTime.now().isBefore(hit.$2)) {
      return Future.value(hit.$1);
    }
    return _inFlight[id] ??=
        _resolve(
          id,
          song.duration,
          // A block, not `=> remove(id)`: remove returns this very future and
          // whenComplete would wait on it forever.
        ).whenComplete(() {
          _inFlight.remove(id);
        });
  }

  static Future<AnimatedArtwork?> _resolve(String id, int? songMs) async {
    try {
      final maxHeight = await isNetworkMetered() ? 480 : 720;
      final resolver = StreamResolver.instance;
      var pick = await resolver.resolveVideo(id, maxHeight: maxHeight);
      if (pick == null) return null; // Held back or failed: try again later.
      if (pick.musicVideoType == 'MUSIC_VIDEO_TYPE_UGC') {
        _none.add(id);
        return null;
      }
      if (pick.isStillCover) {
        final videoId = await _counterpart(id);
        if (videoId == null) {
          _none.add(id);
          return null;
        }
        pick = await resolver.resolveVideo(videoId, maxHeight: maxHeight);
        if (pick == null || pick.isStillCover) return null;
      }

      final video = pick.durationMs;
      _byUrl[pick.url] = YoutubeArtworkVideo(
        videoId: id,
        userAgent: pick.userAgent,
        synced:
            video != null &&
            songMs != null &&
            songMs > 0 &&
            (video - songMs).abs() <= 2500,
      );
      final art = AnimatedArtwork(
        key: 'ytv:$id',
        urlSquare: pick.url,
        urlTall: pick.url,
        urlWide: pick.url,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        hasMotion: true,
      );
      _resolved[id] = (art, pick.expires);
      while (_resolved.length > 32) {
        _byUrl.remove(_resolved.remove(_resolved.keys.first)?.$1.urlSquare);
      }
      return art;
    } catch (e) {
      LoggerHelper.write('$_tag: $id failed', e);
      return null;
    }
  }

  /// The music video of song [id], remembered on disk: a song's video
  /// rarely changes, and each lookup is a request YouTube counts.
  static Future<String?> _counterpart(String id) async {
    final map = _counterparts ??= Map<String, dynamic>.from(
      (await LocalJsonStore.read(_counterpartKey)) as Map? ?? const {},
    );
    final known = map[id];
    if (known is Map && known['at'] is int) {
      final at = DateTime.fromMillisecondsSinceEpoch(known['at'] as int);
      if (DateTime.now().difference(at) < const Duration(days: 30)) {
        final v = known['v'] as String?;
        return v == null || v.isEmpty ? null : v;
      }
    }
    final found = await OnlineApi.videoCounterpart(id);
    map.remove(id);
    map[id] = {'v': found ?? '', 'at': DateTime.now().millisecondsSinceEpoch};
    while (map.length > 500) {
      map.remove(map.keys.first);
    }
    await LocalJsonStore.write(_counterpartKey, map);
    return found;
  }
}
