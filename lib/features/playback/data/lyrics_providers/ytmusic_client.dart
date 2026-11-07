import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/online_settings.dart';

import 'lyrics_http.dart';

/// YouTube Music's own lyrics (plain text, licensed from LyricFind and
/// others). Online songs are asked by their video id; local songs are
/// first matched to a YouTube Music song by search. Needs online music on.
abstract final class YtMusicLyricsClient {
  static Future<String?> fetch({
    required String title,
    required String artist,
    required int durationSeconds,
    String? videoId,
  }) async {
    if (!onlineAvailable || !OnlineSettingsNotifier.current.enabled) {
      return null;
    }
    try {
      final id = videoId ?? await _match(title, artist, durationSeconds);
      return id == null ? null : await OnlineApi.lyrics(id);
    } catch (_) {
      LyricsHttp.failed(); // not a "no lyrics" answer: ask again later
      return null;
    }
  }

  /// The first of the top results that is the same recording: duration
  /// within 5 s, or, with no duration known, the title in its title.
  static Future<String?> _match(String title, String artist, int seconds) async {
    final (songs, _) = await OnlineApi.searchSongs(
      '$artist $title',
      automatic: true,
    );
    final want = title.toLowerCase();
    for (final s in songs.take(5)) {
      final ms = s.durationMs;
      final same = seconds > 0 && ms != null
          ? (ms ~/ 1000 - seconds).abs() <= 5
          : s.title.toLowerCase().contains(want);
      if (same) return s.videoId;
    }
    return null;
  }
}
