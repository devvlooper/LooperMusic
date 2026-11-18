import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';

import 'lyrics_http.dart';

/// Fetches official captions from YouTube player response as line-synced LRC.
/// Skips auto-generated (`kind=asr`) caption tracks.
class YtCaptionsClient {
  static const Duration _timeout = Duration(seconds: 8);

  static Future<String?> fetch({
    required String? videoId,
    Map<String, dynamic>? playerResponse,
    http.Client? client,
  }) async {
    if (videoId == null || videoId.trim().isEmpty) return null;
    if (!OnlineSettingsNotifier.current.enabled) return null;

    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      Map<String, dynamic>? response = playerResponse;
      if (response == null) {
        final vd = await InnerTube.instance.visitorData();
        final (_, fetched) = await InnerTube.instance.player(
          videoId.trim(),
          InnerTubeClients.ios,
          vd,
        );
        response = fetched;
      }

      if (response == null) return null;

      final captions = response['captions'] as Map?;
      final tracklist = captions?['playerCaptionsTracklistRenderer'] as Map?;
      final tracks = tracklist?['captionTracks'] as List?;
      if (tracks == null || tracks.isEmpty) return null;

      // Filter out auto-generated captions (kind=asr)
      final candidates = tracks.whereType<Map>().where((t) {
        final kind = t['kind']?.toString();
        return kind != 'asr';
      }).toList();

      if (candidates.isEmpty) return null;

      // Prioritize English or default if available, otherwise first non-ASR
      Map chosen = candidates.firstWhere(
        (t) =>
            t['languageCode']?.toString().startsWith('en') == true ||
            t['isDefault'] == true,
        orElse: () => candidates.first,
      );

      final baseUrl = chosen['baseUrl']?.toString();
      if (baseUrl == null || baseUrl.isEmpty) return null;

      final captionUri = Uri.parse(baseUrl).replace(
        queryParameters: {
          ...Uri.parse(baseUrl).queryParameters,
          'fmt': 'json3',
        },
      );

      final capRes = await httpClient
          .get(captionUri, headers: LyricsHttp.headers)
          .timeout(_timeout);

      if (!LyricsHttp.ok(capRes.statusCode)) return null;

      final capJson = jsonDecode(utf8.decode(capRes.bodyBytes));
      final events = capJson['events'] as List?;
      if (events == null || events.isEmpty) return null;

      final buffer = StringBuffer();
      for (final event in events.whereType<Map>()) {
        final tStartMs = (event['tStartMs'] as num?)?.toInt() ?? 0;
        final segs = event['segs'] as List?;
        if (segs == null) continue;

        final text = segs
            .map((s) => s is Map ? s['utf8']?.toString() ?? '' : '')
            .join('')
            .trim();
        if (text.isEmpty) continue;

        final mm = (tStartMs ~/ 60000).toString().padLeft(2, '0');
        final ss = ((tStartMs % 60000) / 1000)
            .toStringAsFixed(2)
            .padLeft(5, '0');
        buffer.writeln('[$mm:$ss]$text');
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } catch (e) {
      LyricsHttp.failed();
      LoggerHelper.write('YtCaptionsClient: caption fetch error ($e)');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
    return null;
  }
}
