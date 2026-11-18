import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/settings/domain/app_defaults.dart';

enum OnlineQuality { high, normal, low }

/// Online-mode settings. Kept in LocalJsonStore, not the Isar AppSettings
/// schema, so adding them needs no migration.
class OnlineSettings {
  const OnlineSettings({
    this.enabled = AppDefaults.onlineEnabled,
    this.disclaimerAccepted = AppDefaults.onlineDisclaimerAccepted,
    this.qualityWifi = OnlineQuality.high,
    this.qualityMobile = OnlineQuality.normal,
    this.cachePlayed = AppDefaults.onlineCachePlayed,
    this.cachePlayedOnMobile = AppDefaults.onlineCachePlayedOnMobile,
    this.preload = AppDefaults.onlinePreload,
    this.preloadOnMobile = AppDefaults.onlinePreloadOnMobile,
    this.cacheLimitMB = AppDefaults.onlineCacheLimitMB,
    this.preferLocal = AppDefaults.onlinePreferLocal,
    this.downloadDir,
    this.downloadQuality = OnlineQuality.high,
    this.contentRegion,
    this.contentLanguage,
  });

  /// Master switch: off hides every online surface ("local only").
  final bool enabled;

  /// Whether the user has seen and accepted the first-run disclaimer.
  final bool disclaimerAccepted;
  final OnlineQuality qualityWifi;
  final OnlineQuality qualityMobile;

  /// Save every streamed song to disk so a replay uses no network.
  final bool cachePlayed;
  final bool cachePlayedOnMobile;

  /// Download upcoming songs ahead of time.
  final bool preload;
  final bool preloadOnMobile;
  final int cacheLimitMB;

  /// Play the matching local file instead of streaming when one exists.
  final bool preferLocal;

  /// Folder where downloaded online songs are saved.
  final String? downloadDir;

  /// Quality picked when downloading online songs.
  final OnlineQuality downloadQuality;

  /// ISO 3166-1 alpha-2 content country code (null = Auto from device).
  final String? contentRegion;

  /// Content language code (null = Auto from app).
  final String? contentLanguage;

  OnlineSettings copyWith({
    bool? enabled,
    bool? disclaimerAccepted,
    OnlineQuality? qualityWifi,
    OnlineQuality? qualityMobile,
    bool? cachePlayed,
    bool? cachePlayedOnMobile,
    bool? preload,
    bool? preloadOnMobile,
    int? cacheLimitMB,
    bool? preferLocal,
    String? downloadDir,
    OnlineQuality? downloadQuality,
    String? Function()? contentRegion,
    String? Function()? contentLanguage,
  }) => OnlineSettings(
    enabled: enabled ?? this.enabled,
    disclaimerAccepted: disclaimerAccepted ?? this.disclaimerAccepted,
    qualityWifi: qualityWifi ?? this.qualityWifi,
    qualityMobile: qualityMobile ?? this.qualityMobile,
    cachePlayed: cachePlayed ?? this.cachePlayed,
    cachePlayedOnMobile: cachePlayedOnMobile ?? this.cachePlayedOnMobile,
    preload: preload ?? this.preload,
    preloadOnMobile: preloadOnMobile ?? this.preloadOnMobile,
    cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
    preferLocal: preferLocal ?? this.preferLocal,
    downloadDir: downloadDir ?? this.downloadDir,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    contentRegion: contentRegion != null ? contentRegion() : this.contentRegion,
    contentLanguage: contentLanguage != null
        ? contentLanguage()
        : this.contentLanguage,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'disclaimerAccepted': disclaimerAccepted,
    'qualityWifi': qualityWifi.name,
    'qualityMobile': qualityMobile.name,
    'cachePlayed': cachePlayed,
    'cachePlayedOnMobile': cachePlayedOnMobile,
    'preload': preload,
    'preloadOnMobile': preloadOnMobile,
    'cacheLimitMB': cacheLimitMB,
    'preferLocal': preferLocal,
    'downloadDir': downloadDir,
    'downloadQuality': downloadQuality.name,
    if (contentRegion != null) 'contentRegion': contentRegion,
    if (contentLanguage != null) 'contentLanguage': contentLanguage,
  };

  static OnlineQuality _q(Object? v, OnlineQuality d) =>
      OnlineQuality.values.where((q) => q.name == v).firstOrNull ?? d;

  static String? _validateRegion(Object? v) {
    if (v is! String) return null;
    final clean = v.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(clean) ? clean : null;
  }

  factory OnlineSettings.fromJson(Map j) => OnlineSettings(
    enabled: j['enabled'] as bool? ?? AppDefaults.onlineEnabled,
    disclaimerAccepted: j['disclaimerAccepted'] as bool? ?? false,
    qualityWifi: _q(j['qualityWifi'], OnlineQuality.high),
    qualityMobile: _q(j['qualityMobile'], OnlineQuality.normal),
    cachePlayed: j['cachePlayed'] as bool? ?? true,
    cachePlayedOnMobile: j['cachePlayedOnMobile'] as bool? ?? true,
    preload: j['preload'] as bool? ?? true,
    preloadOnMobile: j['preloadOnMobile'] as bool? ?? true,
    cacheLimitMB: j['cacheLimitMB'] as int? ?? 5120,
    preferLocal: j['preferLocal'] as bool? ?? true,
    downloadDir: j['downloadDir'] as String?,
    downloadQuality: _q(j['downloadQuality'], OnlineQuality.high),
    contentRegion: _validateRegion(j['contentRegion']),
    contentLanguage: j['contentLanguage'] as String?,
  );
}

class OnlineSettingsNotifier extends Notifier<OnlineSettings> {
  static const _key = 'online_settings';

  /// Latest value for code without a Ref (resolver, cache).
  static OnlineSettings current = const OnlineSettings();

  /// SIM/network country (Android), used by Auto region before the locale.
  static String? deviceCountry;

  @override
  OnlineSettings build() {
    _load();
    return current;
  }

  Future<void> _load() async {
    if (Platform.isAndroid) {
      try {
        deviceCountry = await _networkChannel.invokeMethod<String>(
          'deviceCountry',
        );
      } catch (_) {}
    }
    final raw = await LocalJsonStore.read(_key);
    if (raw is Map) state = current = OnlineSettings.fromJson(raw);
  }

  Future<void> update(OnlineSettings Function(OnlineSettings) change) async {
    state = current = change(state);
    await LocalJsonStore.write(_key, state.toJson());
  }

  /// Sets content region with validation, clearing home cache and resetting visitor (Doc 21 §3.2).
  Future<void> setContentRegion(String? region) async {
    final clean =
        region != null &&
            RegExp(r'^[A-Z]{2}$').hasMatch(region.trim().toUpperCase())
        ? region.trim().toUpperCase()
        : null;
    await update((s) => s.copyWith(contentRegion: () => clean));
    await LocalJsonStore.delete('online_home_v1');
    try {
      await StreamResolver.instance.reset();
    } catch (_) {}
  }
}

final onlineSettingsProvider =
    NotifierProvider<OnlineSettingsNotifier, OnlineSettings>(
      OnlineSettingsNotifier.new,
    );

const _networkChannel = MethodChannel('com.looper.player/audio_info');

/// Whether the active network is metered (mobile data). Desktop: never.
Future<bool> isNetworkMetered() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _networkChannel.invokeMethod<bool>('isNetworkMetered') ??
        false;
  } catch (_) {
    return false;
  }
}

/// The quality to stream at right now, read at decision time.
Future<OnlineQuality> currentQuality() async {
  final s = OnlineSettingsNotifier.current;
  return await isNetworkMetered() ? s.qualityMobile : s.qualityWifi;
}
