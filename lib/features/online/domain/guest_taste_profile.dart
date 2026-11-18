/// Immutable models for the on-device Guest Taste Profile.
///
/// See docs/online/23-guest-mode-offline-seeded-recommendations.md.
class TasteSeed {
  final String title;
  final String artist;
  final double score;
  final String? videoId;
  final String? artistBrowseId;
  final String? radioPlaylistId;

  const TasteSeed({
    required this.title,
    required this.artist,
    required this.score,
    this.videoId,
    this.artistBrowseId,
    String? radioPlaylistId,
  }) : radioPlaylistId =
           radioPlaylistId ?? (videoId != null ? 'RDAMVM$videoId' : null);

  TasteSeed copyWith({
    String? title,
    String? artist,
    double? score,
    String? videoId,
    String? artistBrowseId,
    String? radioPlaylistId,
  }) => TasteSeed(
    title: title ?? this.title,
    artist: artist ?? this.artist,
    score: score ?? this.score,
    videoId: videoId ?? this.videoId,
    artistBrowseId: artistBrowseId ?? this.artistBrowseId,
    radioPlaylistId: radioPlaylistId ?? this.radioPlaylistId,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'score': score,
    if (videoId != null) 'videoId': videoId,
    if (artistBrowseId != null) 'artistBrowseId': artistBrowseId,
    if (radioPlaylistId != null) 'radioPlaylistId': radioPlaylistId,
  };

  factory TasteSeed.fromJson(Map<String, dynamic> json) => TasteSeed(
    title: json['title'] as String? ?? json['t'] as String? ?? '',
    artist: json['artist'] as String? ?? json['a'] as String? ?? '',
    score: (json['score'] as num? ?? json['s'] as num? ?? 0.0).toDouble(),
    videoId: json['videoId'] as String? ?? json['v'] as String?,
    artistBrowseId: json['artistBrowseId'] as String? ?? json['b'] as String?,
    radioPlaylistId: json['radioPlaylistId'] as String? ?? json['r'] as String?,
  );

  @override
  String toString() =>
      'TasteSeed(title: $title, artist: $artist, score: ${score.toStringAsFixed(2)}, videoId: $videoId)';
}

/// On-device taste profile derived from local library metadata and playback history.
class GuestTasteProfile {
  final List<TasteSeed> topArtists;
  final List<TasteSeed> topSongs;
  final List<String> dominantGenres;
  final String primaryLanguageScript;
  final DateTime generatedAt;
  final int coldStartLevel;

  const GuestTasteProfile({
    required this.topArtists,
    required this.topSongs,
    required this.dominantGenres,
    required this.primaryLanguageScript,
    required this.generatedAt,
    this.coldStartLevel = 0,
  });

  bool get isEmpty => topArtists.isEmpty && topSongs.isEmpty;

  Map<String, dynamic> toJson() => {
    'topArtists': [for (final a in topArtists) a.toJson()],
    'topSongs': [for (final s in topSongs) s.toJson()],
    'dominantGenres': dominantGenres,
    'primaryLanguageScript': primaryLanguageScript,
    'generatedAt': generatedAt.millisecondsSinceEpoch,
    'coldStartLevel': coldStartLevel,
  };

  factory GuestTasteProfile.fromJson(Map<String, dynamic> json) =>
      GuestTasteProfile(
        topArtists: [
          for (final a in (json['topArtists'] as List? ?? const []))
            if (a is Map) TasteSeed.fromJson(a.cast<String, dynamic>()),
        ],
        topSongs: [
          for (final s in (json['topSongs'] as List? ?? const []))
            if (s is Map) TasteSeed.fromJson(s.cast<String, dynamic>()),
        ],
        dominantGenres: [
          for (final g in (json['dominantGenres'] as List? ?? const []))
            g.toString(),
        ],
        primaryLanguageScript:
            json['primaryLanguageScript'] as String? ?? 'Latin',
        generatedAt: DateTime.fromMillisecondsSinceEpoch(
          json['generatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
        coldStartLevel: json['coldStartLevel'] as int? ?? 0,
      );

  @override
  String toString() =>
      'GuestTasteProfile(artists: ${topArtists.length}, songs: ${topSongs.length}, level: $coldStartLevel)';
}
