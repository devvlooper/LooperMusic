import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';

/// Lightweight query descriptor for finding related tracks for a specific song.
class RelatedSongQuery {
  final String path;
  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? videoId;
  final bool isOnline;

  const RelatedSongQuery({
    required this.path,
    required this.title,
    this.artist,
    this.album,
    this.genre,
    this.videoId,
    this.isOnline = false,
  });

  factory RelatedSongQuery.fromSong(Song song) {
    var vid = song.videoId;
    if (vid == null && song.isOnline && song.path.startsWith('yt:')) {
      vid = song.path.substring(3);
    }
    return RelatedSongQuery(
      path: song.path,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      videoId: vid,
      isOnline: song.isOnline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelatedSongQuery &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Discovers related / similar songs matching the currently playing song.
///
/// If online streaming is active, queries YouTube Music's radio/continuation
/// endpoint for the seed track. If offline, online is unavailable, or returns empty,
/// seamlessly falls back to matching local tracks by artist, album, and genre.
final relatedSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, RelatedSongQuery>((ref, query) async {
      final seenPaths = <String>{query.path};
      final results = <Song>[];

      // 1. Online discovery via YouTube Music radio
      final isOnlineActive = ref.watch(onlineActiveProvider);
      if (isOnlineActive) {
        try {
          var seedId = query.videoId;
          if (seedId == null && query.title.trim().isNotEmpty) {
            // Local song: search online for title + artist to find matching YouTube videoId
            final searchQuery = '${query.title} ${query.artist ?? ''}'.trim();
            final (found, _) = await OnlineApi.searchSongs(
              searchQuery,
              automatic: true,
            );
            seedId = found.firstOrNull?.videoId;
          }

          if (seedId != null && seedId.isNotEmpty) {
            final radioSongs = await OnlineApi.radio(seedId, automatic: true);
            final filtered = radioSongs
                .where((s) => s.videoType != videoTypeFanUpload)
                .map((s) => s.toSong())
                .where((s) => seenPaths.add(s.path));
            results.addAll(filtered);
          }
        } catch (e) {
          LoggerHelper.write('relatedSongsProvider: online radio failed', e);
        }
      }

      // If online gave us enough related songs, return them
      if (results.length >= 5) {
        return results;
      }

      // 2. Local database matching fallback
      try {
        // A) Match same artist
        final artist = query.artist?.trim();
        if (artist != null &&
            artist.isNotEmpty &&
            artist.toLowerCase() != 'unknown artist') {
          final byArtist = await DbService.isar.songs
              .filter()
              .artistEqualTo(artist, caseSensitive: false)
              .findAll();
          for (final s in byArtist) {
            if (seenPaths.add(s.path)) {
              results.add(s);
            }
          }
        }

        // B) Match same album
        final album = query.album?.trim();
        if (album != null &&
            album.isNotEmpty &&
            album.toLowerCase() != 'unknown album') {
          final byAlbum = await DbService.isar.songs
              .filter()
              .albumEqualTo(album, caseSensitive: false)
              .findAll();
          for (final s in byAlbum) {
            if (seenPaths.add(s.path)) {
              results.add(s);
            }
          }
        }

        // C) Match same genre
        final genre = query.genre?.trim();
        if (genre != null && genre.isNotEmpty) {
          final byGenre = await DbService.isar.songs
              .filter()
              .genreEqualTo(genre, caseSensitive: false)
              .findAll();
          for (final s in byGenre) {
            if (seenPaths.add(s.path)) {
              results.add(s);
            }
          }
        }

        // D) If still few matches, pull other tracks from the local library
        if (results.length < 5) {
          final all = await DbService.isar.songs.where().limit(40).findAll();
          final pool = List<Song>.from(all)..shuffle();
          for (final s in pool) {
            if (seenPaths.add(s.path)) {
              results.add(s);
              if (results.length >= 20) break;
            }
          }
        }
      } catch (e) {
        LoggerHelper.write('relatedSongsProvider: local match failed', e);
      }

      return results;
    });
