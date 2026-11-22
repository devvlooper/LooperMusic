import 'dart:io';
import 'package:flutter/services.dart';
import 'package:metadata_god/metadata_god.dart';

import 'lyrics_formats/id3_sylt_reader.dart';

class MetadataService {
  static const MethodChannel _broadcastChannel = MethodChannel(
    'com.looper.music/broadcast',
  );

  static Future<String?> getEmbeddedLyrics(String path) async {
    // Synced lyrics (ID3 SYLT) first: the tag readers below only return the
    // unsynced USLT copy stored next to them.
    if (path.toLowerCase().endsWith('.mp3')) {
      final synced = await Id3SyltReader.readFile(path);
      if (synced != null && synced.isNotEmpty) return synced;
    }
    if (Platform.isAndroid) {
      return await _getLyricsAndroid(path);
    }
    return null;
  }

  static Future<String?> _getLyricsAndroid(String path) async {
    try {
      // See LibraryScanner._fetchNativeEmbeddedPicture's doc comment - same
      // reasoning: this runs inside enrichPendingSongs' batched Future.wait,
      // so one file that hangs the native side here would otherwise stall
      // every song batched after it, not just this one's lyrics.
      final lyrics = await _broadcastChannel
          .invokeMethod<String>('getEmbeddedLyrics', {'path': path})
          .timeout(const Duration(seconds: 6));
      return (lyrics != null && lyrics.isNotEmpty) ? lyrics : null;
    } catch (_) {
      return null;
    }
  }
}
