import 'dart:math' as math;
import 'package:looper_player/features/library/domain/models/models.dart';

/// Volume normalization rules and gain parsing (docs/online/25-audio-lab.md §3.2).
///
/// Mochy Music principles:
/// 1. Local files: ReplayGain (track or album mode, preamp, clip prevention, 0 dB fallback).
/// 2. Online songs: apply -(loudness above -14 LKFS) from StreamPick as a volume gain,
///    ONLY when it is positive (turning loud songs down, never boosting quiet ones).
/// 3. No tags and no value means 0 dB. Never carry the last song's gain over.
/// 4. ReplayGain and live loudnorm are mutually exclusive.
abstract final class AudioNormalization {
  /// Parses a gain tag string (Vorbis comment / ID3 / MP4).
  /// Handles formats like:
  /// - "-8.89 dB" -> -8.89
  /// - "+2.1 dB"  -> 2.1
  /// - "1.000000" -> 1.0
  /// - empty, null, or garbage -> null
  static double? parseGain(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(
      r'^([+-]?\d+(?:\.\d+)?)(?:\s*dB)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Calculates the volume normalization gain to apply for an online track.
  ///
  /// [loudnessDb] represents track loudness in dB above YouTube's -14 LKFS target.
  /// When [loudnessDb] is positive (track is louder than target), it returns a negative
  /// gain to bring it down (-loudnessDb). When negative or zero (or null), it returns 0.0 dB
  /// (never boosting quiet tracks).
  static double computeOnlineLoudnessGain(double? loudnessDb) {
    if (loudnessDb == null || loudnessDb <= 0.0) return 0.0;
    return -loudnessDb;
  }

  /// Determines whether the current track is part of an album being played in order.
  /// When true, album-mode ReplayGain should be selected; otherwise track mode.
  static bool isAlbumInOrder({
    required Song song,
    required List<Song> playlist,
    required int currentIndex,
    bool isShuffle = false,
  }) {
    if (isShuffle) return false;
    final album = song.album?.trim();
    if (album == null || album.isEmpty) return false;
    if (playlist.length < 2 ||
        currentIndex < 0 ||
        currentIndex >= playlist.length) {
      return false;
    }

    // Check adjacent tracks in the playlist
    bool hasAdjacentSameAlbum = false;
    bool trackOrderPreserved = true;

    if (currentIndex > 0) {
      final prev = playlist[currentIndex - 1];
      if (prev.album?.trim() == album) {
        hasAdjacentSameAlbum = true;
        if (song.trackNumber != null && prev.trackNumber != null) {
          if (song.trackNumber! < prev.trackNumber!) {
            trackOrderPreserved = false;
          }
        }
      }
    }

    if (currentIndex < playlist.length - 1) {
      final next = playlist[currentIndex + 1];
      if (next.album?.trim() == album) {
        hasAdjacentSameAlbum = true;
        if (song.trackNumber != null && next.trackNumber != null) {
          if (song.trackNumber! > next.trackNumber!) {
            trackOrderPreserved = false;
          }
        }
      }
    }

    return hasAdjacentSameAlbum && trackOrderPreserved;
  }
}
