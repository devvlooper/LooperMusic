part of 'playback_notifier.dart';

/// Online streaming hooks (docs/online/05-loading-and-errors.md).
extension _OnlineHooks on Playback {
  /// Resolve what mpv should open for [song]: its own path for local files.
  Future<PlayableSource> _sourceFor(Song song) async {
    if (!song.isOnline) {
      _onlineStreamed = false;
      return PlayableSource(song.path);
    }
    final src = await OnlinePlayback.sourceFor(
      song,
      allowNetwork: _internetAllowed,
    );
    _onlineStreamed = src.streamed;
    if (_onlineRecoveryPath != song.path) {
      _onlineRecoveryPath = song.path;
      _onlineRecoveries = 0;
    }
    return src;
  }

  /// An online song could not start: say so once and move on. A run of
  /// failures (offline, YouTube refusing the device) stops instead of
  /// spinning through the whole queue.
  Future<void> _onOnlineFailure(Song song, Object error) async {
    LoggerHelper.write('Online playback failed for ${song.path}', error);
    _onlineFailStreak++;
    final reason = switch (error) {
      UnplayableException(:final reason) => reason,
      StreamUnavailableException(:final message) => message,
      TimeoutException() => 'took too long to load',
      SocketException() => 'no connection',
      _ => 'could not load',
    };
    if (_onlineFailStreak >= 4) {
      _onlineFailStreak = 0;
      _showErrorSnackBar(
        'Online playback stopped: $reason',
        (l10n) => l10n.onlinePlaybackStopped(reason),
      );
      await _pauseAtPlaybackEnd();
      return;
    }
    _showErrorSnackBar(
      'Skipped ${song.title}: $reason',
      (l10n) => l10n.onlineSongSkipped(song.title, reason),
    );
    await skipNext(isManual: false);
  }

  /// A streamed song that "ended" well before its length was cut off (an
  /// expired URL or a refused identity mid-file). Re-resolve and continue
  /// from the same position, at most twice per song.
  bool _tryRecoverOnline(Song? song) {
    if (song == null || !song.isOnline || !_onlineStreamed) return false;
    final pos = _pendingSeek ?? playbackState.position;
    final dur = song.duration != null
        ? Duration(milliseconds: song.duration!)
        : player.state.duration;
    if (dur <= Duration.zero || dur - pos < const Duration(seconds: 5)) {
      return false;
    }
    if (_onlineRecoveries >= 2) return false;
    _onlineRecoveries++;
    LoggerHelper.write(
      'Online stream ended early at $pos (mpv: ${player.state.position}, state: ${playbackState.position}, pending: $_pendingSeek) of $dur, recovering ${song.path}',
    );
    StreamResolver.instance.invalidate(song.videoId!);
    unawaited(play(song, initialPosition: pos));
    return true;
  }

  /// Queue running low on an online song: append YouTube's radio for it.
  void _extendOnlineQueue(Song current) {
    if (_extendingOnline || !_onlineNetworkAllowed) return;
    _extendingOnline = true;
    final exclude = {for (final s in _playlist) s.path};
    RecommendationEngine.queueContinuation(current, exclude, limit: 20)
        .then((fetched) {
          // Anchored to the queue that asked: a queue replaced meanwhile
          // never gets the old song's radio.
          final more = continuationToAppend(
            requestedFor: current.path,
            queueThen: exclude,
            currentNow: playbackState.currentSong?.path,
            queueNow: [for (final s in _playlist) s.path],
            fetched: fetched,
          );
          if (more.isEmpty) return;
          // Appended at the end, never mixed into a shuffled user queue.
          _playlist.addAll(more);
          _originalPlaylist.addAll(more);
          _publishQueue();
          unawaited(_saveQueueState());
          _prefetchOnline();
        })
        .catchError((Object e) {
          LoggerHelper.write('Could not extend the online queue', e);
        })
        .whenComplete(() => _extendingOnline = false);
  }

  bool get _onlineNetworkAllowed =>
      onlineAvailable &&
      OnlineSettingsNotifier.current.enabled &&
      _internetAllowed;

  void _prefetchOnline() {
    if (_currentIndex < 0 || !_onlineNetworkAllowed) return;
    unawaited(
      OnlineCache.instance.prefetch(_playlist.skip(_currentIndex + 1)),
    );
  }
}
