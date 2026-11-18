import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:looper_player/core/utils/logger_helper.dart';

import '../lyrics_formats/richsync_lyrics_parser.dart';
import '../lyrics_formats/timed_lyrics.dart';
import '../lyrics_formats/ttml_lyrics_parser.dart';
import 'lyrics_http.dart';

/// SimpMusic lyrics client: fetches lyrics by YouTube video ID.
/// Supports richSync (word-level), synced (line-level), and plain text.
class SimpMusicClient {
  static const String _baseUrl = 'https://api-lyrics.simpmusic.org/v1';
  static const Duration _timeout = Duration(seconds: 8);

  static Future<String?> fetch({
    required String? videoId,
    int durationSeconds = 0,
  }) async {
    if (videoId == null || videoId.trim().isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/${videoId.trim()}');
      final response = await http
          .get(uri, headers: LyricsHttp.headers)
          .timeout(_timeout);

      if (!LyricsHttp.ok(response.statusCode)) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || body['data'] is! List) return null;

      final List items = body['data'];
      final candidates = items.whereType<Map>().toList();
      if (candidates.isEmpty) return null;

      Map? bestMatch;
      if (durationSeconds > 0) {
        num minDiff = 999999;
        for (final item in candidates) {
          final d = item['duration'];
          if (d is num) {
            final diff = (d - durationSeconds).abs();
            if (diff <= 10 && diff < minDiff) {
              minDiff = diff;
              bestMatch = item;
            }
          }
        }
      }

      // If no candidate matched duration within 10s when duration is specified, reject
      if (bestMatch == null) {
        if (durationSeconds > 0) return null;
        bestMatch = candidates.first;
      }

      // 1. Try richSyncLyrics (word-synced)
      final rich = bestMatch['richSyncLyrics']?.toString();
      if (rich != null && rich.trim().isNotEmpty) {
        // Try richsync parser
        final richLines = RichsyncLyricsParser.parse(rich);
        if (richLines != null && richLines.isNotEmpty) {
          final written = TimedLrcWriter.write(richLines);
          if (written != null) return written;
        }
        // Try TTML parser fallback
        final ttmlLines = TtmlLyricsParser.parse(rich);
        if (ttmlLines != null && ttmlLines.isNotEmpty) {
          final written = TimedLrcWriter.write(ttmlLines);
          if (written != null) return written;
        }
        if (rich.contains('[00:')) return rich;
      }

      // 2. Try syncedLyrics (line-synced LRC)
      final synced = bestMatch['syncedLyrics']?.toString();
      if (synced != null && synced.trim().isNotEmpty) {
        return synced.trim();
      }

      // 3. Try plainLyrics
      final plain = bestMatch['plainLyrics']?.toString();
      if (plain != null && plain.trim().isNotEmpty) {
        return plain.trim();
      }
    } catch (e) {
      LyricsHttp.failed();
      LoggerHelper.write('SimpMusicClient: fetch error ($e)');
    }
    return null;
  }
}
