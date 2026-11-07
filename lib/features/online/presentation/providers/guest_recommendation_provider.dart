import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/guest_feed_service.dart';
import 'package:looper_player/features/online/data/guest_taste_engine.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/domain/guest_taste_profile.dart';

/// State of the Guest Recommendation Engine.
class GuestRecommendationState {
  final GuestTasteProfile? profile;
  final List<OnlineShelf> shelves;
  final bool loading;
  final Object? error;
  final DateTime? lastUpdated;

  const GuestRecommendationState({
    this.profile,
    this.shelves = const [],
    this.loading = false,
    this.error,
    this.lastUpdated,
  });

  bool get isEmpty => shelves.isEmpty && (profile?.isEmpty ?? true);

  GuestRecommendationState copyWith({
    GuestTasteProfile? profile,
    List<OnlineShelf>? shelves,
    bool? loading,
    Object? error,
    DateTime? lastUpdated,
  }) =>
      GuestRecommendationState(
        profile: profile ?? this.profile,
        shelves: shelves ?? this.shelves,
        loading: loading ?? this.loading,
        error: error,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  Map<String, dynamic> toJson() => {
        if (profile != null) 'profile': profile!.toJson(),
        'shelves': [for (final s in shelves) s.toJson()],
        if (lastUpdated != null)
          'lastUpdated': lastUpdated!.millisecondsSinceEpoch,
      };

  factory GuestRecommendationState.fromJson(Map<String, dynamic> json) =>
      GuestRecommendationState(
        profile: json['profile'] is Map
            ? GuestTasteProfile.fromJson(
                (json['profile'] as Map).cast<String, dynamic>(),
              )
            : null,
        shelves: [
          for (final s in (json['shelves'] as List? ?? const []))
            if (s is Map) ?OnlineShelf.fromJson(s),
        ],
        lastUpdated: json['lastUpdated'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'] as int)
            : null,
      );
}

/// Riverpod notifier managing offline-seeded guest recommendations.
///
/// See docs/online/23-guest-mode-offline-seeded-recommendations.md.
class GuestRecommendationNotifier extends Notifier<GuestRecommendationState> {
  static const _tag = 'GuestRecommendationNotifier';
  static const _cacheKey = 'guest_recommendations_cache_v1';
  static const _freshDuration = Duration(hours: 24);

  final GuestTasteEngine _engine = GuestTasteEngine();
  final GuestFeedService _feedService = GuestFeedService();
  Future<void>? _running;

  @override
  GuestRecommendationState build() {
    unawaited(_boot());
    return const GuestRecommendationState(loading: true);
  }

  Future<void> _boot() async {
    try {
      final raw = await LocalJsonStore.read(_cacheKey);
      if (raw is Map && state.shelves.isEmpty) {
        final cached = GuestRecommendationState.fromJson(
          raw.cast<String, dynamic>(),
        );
        if (cached.shelves.isNotEmpty) {
          state = cached.copyWith(loading: true);
        }
      }
    } catch (e) {
      LoggerHelper.write('$_tag: _boot failed', e);
    }
    await load();
  }

  /// Loads or refetches guest recommendations with 24-hour freshness check.
  Future<void> load({bool force = false}) {
    final last = state.lastUpdated;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _freshDuration &&
        state.shelves.isNotEmpty) {
      return Future.value();
    }
    return _running ??= _fetch(force).whenComplete(() => _running = null);
  }

  Future<void> _fetch(bool force) async {
    state = state.copyWith(loading: true);
    try {
      final profile = await _engine.computeProfile();
      final shelves = await _feedService.buildGuestFeed(
        profile: profile,
        force: force,
      );

      final now = DateTime.now();
      state = GuestRecommendationState(
        profile: profile,
        shelves: shelves,
        loading: false,
        lastUpdated: now,
      );

      unawaited(LocalJsonStore.write(_cacheKey, state.toJson()));
    } catch (e) {
      LoggerHelper.write('$_tag: _fetch failed', e);
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Forces an immediate rebuild of taste profile and feed.
  Future<void> refresh() => load(force: true);
}

final guestRecommendationProvider =
    NotifierProvider<GuestRecommendationNotifier, GuestRecommendationState>(
  GuestRecommendationNotifier.new,
);
