import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/data/youtube_video_artwork.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:video_player/video_player.dart';

/// Central host managing reference-counted [VideoPlayerController] instances
/// per media source (Doc 20 §5.3, fixes bugs A15-A17).
class MotionArtworkHost {
  static final Map<String, _HostEntry> _active = {};
  // mediaSource (as given to the widget) -> playFrom (the cached file).
  static final Map<String, String> _alias = {};

  /// The already-playing controller for [source], acquired synchronously, or
  /// null when none is live yet. A widget mounted mid-transition (a Hero
  /// landing, a flight shuttle, the Fluid Player's morph) paints the same
  /// texture on its first frame instead of its still art.
  static (VideoPlayerController, String)? acquireLive(String source) {
    final String playFrom = _alias[source] ?? source;
    final _HostEntry? entry = _active[playFrom];
    if (entry == null || !entry.ready) return null;
    entry.cancelDisposeTimer();
    entry.refCount++;
    return (entry.controller, playFrom);
  }

  static Future<VideoPlayerController?> acquire(
    String playFrom, {
    required bool isLocal,
    required bool muted,
    required bool loop,
    required bool autoPlay,
    String? alias,
    Map<String, String> headers = const {},
  }) async {
    if (alias != null) _alias[alias] = playFrom;
    _HostEntry? entry = _active[playFrom];
    if (entry != null) {
      entry.cancelDisposeTimer();
      entry.refCount++;
      try {
        await entry.initFuture;
        if (autoPlay && !entry.controller.value.isPlaying) {
          entry.controller.play();
        }
        return entry.controller;
      } catch (_) {
        return null;
      }
    }

    final VideoPlayerController controller;
    if (isLocal) {
      final file = File(playFrom);
      if (!file.existsSync()) return null;
      controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    } else {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(playFrom),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }

    final completer = Completer<void>();
    entry = _HostEntry(
      controller: controller,
      initFuture: completer.future,
      refCount: 1,
    );
    _active[playFrom] = entry;

    try {
      await controller.initialize();
      if (muted) await controller.setVolume(0.0);
      await controller.setLooping(loop);
      if (autoPlay) await controller.play();
      entry.ready = true;
      completer.complete();
      return controller;
    } catch (e) {
      _active.remove(playFrom);
      completer.completeError(e);
      controller.dispose();
      return null;
    }
  }

  static void release(String playFrom) {
    final entry = _active[playFrom];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      entry.startDisposeTimer(() {
        _active.remove(playFrom);
        _alias.removeWhere((_, v) => v == playFrom);
        entry.controller.dispose();
      });
    }
  }
}

class _HostEntry {
  final VideoPlayerController controller;
  final Future<void> initFuture;
  int refCount;
  bool ready = false;
  Timer? _disposeTimer;

  _HostEntry({
    required this.controller,
    required this.initFuture,
    required this.refCount,
  });

  void cancelDisposeTimer() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  void startDisposeTimer(VoidCallback onDispose) {
    _disposeTimer?.cancel();
    _disposeTimer = Timer(const Duration(seconds: 10), onDispose);
  }
}

class AnimatedArtworkWidget extends ConsumerStatefulWidget {
  final String? mediaSource; // Local file path or network m3u8/mp4 URL
  final Widget staticFallback;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool muted;
  final bool loop;
  final bool autoPlay;

  const AnimatedArtworkWidget({
    super.key,
    required this.mediaSource,
    required this.staticFallback,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.muted = true,
    this.loop = true,
    this.autoPlay = true,
  });

  @override
  ConsumerState<AnimatedArtworkWidget> createState() =>
      _AnimatedArtworkWidgetState();
}

class _AnimatedArtworkWidgetState extends ConsumerState<AnimatedArtworkWidget>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasFirstFrame = false;
  String? _activeSource;
  Timer? _firstFrameTimer;
  bool _built = false;

  /// A YouTube video that follows the song's position.
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant AnimatedArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaSource != widget.mediaSource) {
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.autoPlay && mounted) {
        _controller?.play();
      }
    }
  }

  Future<void> _initPlayer() async {
    final source = widget.mediaSource;
    if (source == null || source.isEmpty) {
      _disposeCurrentController();
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasFirstFrame = false;
          _activeSource = null;
        });
      }
      return;
    }

    if (source == _activeSource && _controller != null) {
      return;
    }

    // Check settings and network permission
    final settings = ref.read(animatedArtworkSettingsProvider);
    if (settings.mode == AnimatedArtworkMode.never) {
      _disposeCurrentController();
      return;
    }

    // Already playing elsewhere (the real artwork, a shuttle): show that
    // texture from this widget's first frame, no still art and no fade.
    final live = MotionArtworkHost.acquireLive(source);
    if (live != null) {
      _disposeCurrentController();
      _controller = live.$1;
      _activeSource = live.$2;
      _controller!.addListener(_videoListener);
      _isInitialized = true;
      _hasFirstFrame = true;
      // From initState the first build is still ahead; no setState needed.
      if (_built) setState(() {});
      return;
    }

    var playFrom = source;
    final youtube = YoutubeVideoArtwork.infoFor(source);
    if (youtube != null) {
      // Streamed, never cached whole: a music video is tens of MB.
      if (!await AnimatedArtworkService.instance.isNetworkPermitted() ||
          !mounted ||
          widget.mediaSource != source) {
        _disposeCurrentController();
        return;
      }
    } else if (source.startsWith('http')) {
      final permitted = await AnimatedArtworkService.instance
          .isNetworkPermitted();
      if (!permitted && mounted) {
        _disposeCurrentController();
        return;
      }
      // Play from the cached file so the loop never stalls on the network;
      // the still art shows meanwhile. Streams only if the download fails.
      _disposeCurrentController();
      _activeSource = source;
      playFrom =
          await AnimatedArtworkService.instance.localFileFor(source) ?? source;
      if (!mounted || widget.mediaSource != source) return;
    }
    final isLocal = !playFrom.startsWith('http');
    if (isLocal) {
      await AnimatedArtworkService.instance.ensureTimeline(playFrom);
      if (!mounted || widget.mediaSource != source) return;
    }

    _disposeCurrentController();
    _activeSource = playFrom;

    try {
      final controller = await MotionArtworkHost.acquire(
        playFrom,
        isLocal: isLocal,
        muted: widget.muted,
        loop: youtube != null ? !youtube.synced : widget.loop,
        autoPlay: widget.autoPlay,
        alias: source,
        headers: youtube == null ? const {} : {'User-Agent': youtube.userAgent},
      );

      if (!mounted || _activeSource != playFrom || controller == null) {
        if (controller != null) MotionArtworkHost.release(playFrom);
        return;
      }

      _controller = controller;
      controller.addListener(_videoListener);
      if (youtube?.synced ?? false) _startSync();

      final val = controller.value;
      final alreadyPresented =
          val.isInitialized && (val.position > Duration.zero || val.isPlaying);

      if (mounted) {
        setState(() {
          _isInitialized = val.isInitialized;
          _hasFirstFrame = alreadyPresented;
        });
      }

      if (!_hasFirstFrame) {
        _firstFrameTimer?.cancel();
        _firstFrameTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted &&
              _controller != null &&
              !_hasFirstFrame &&
              _controller!.value.isInitialized) {
            setState(() {
              _hasFirstFrame = true;
            });
          }
        });
      }
    } catch (_) {
      _disposeCurrentController();
    }
  }

  void _videoListener() {
    final c = _controller;
    if (c == null || !mounted || _hasFirstFrame) return;
    final value = c.value;
    // Only present once decoder has produced and painted the first frame (Bug A14)
    if (value.isInitialized &&
        (value.position > Duration.zero || value.isPlaying)) {
      _firstFrameTimer?.cancel();
      setState(() {
        _hasFirstFrame = true;
      });
    }
  }

  /// Keeps a synced YouTube video within 400 ms of the song: it starts at
  /// the song's position and is nudged back after seeks and stalls. Several
  /// widgets sharing the video all check, but once one has re-seeked the
  /// rest find it in step.
  void _startSync() {
    _syncTimer?.cancel();
    void check() {
      final c = _controller;
      if (c == null || !mounted || !c.value.isInitialized) return;
      final song = ref.read(playbackProvider).position;
      final drift = (c.value.position - song).abs();
      if (drift > const Duration(milliseconds: 400) &&
          song < c.value.duration) {
        // The seek itself takes a moment; land slightly ahead.
        c.seekTo(song + const Duration(milliseconds: 150));
      }
    }

    check();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => check());
  }

  void _disposeCurrentController() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _controller?.removeListener(_videoListener);
    if (_activeSource != null) {
      MotionArtworkHost.release(_activeSource!);
    }
    _controller = null;
    _activeSource = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCurrentController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    // Follow the music playback state (Doc 20 §5.3 Bug A15)
    ref.listen(playbackProvider.select((s) => s.isPlaying), (prev, isPlaying) {
      if (_controller == null || !_isInitialized) return;
      if (isPlaying) {
        if (widget.autoPlay && !_controller!.value.isPlaying) {
          _controller?.play();
        }
      } else {
        if (_controller!.value.isPlaying) {
          _controller?.pause();
        }
      }
    });

    final child = Stack(
      fit: StackFit.expand,
      children: [
        // Static fallback always present underneath for instantaneous rendering
        widget.staticFallback,

        // Video texture fading in smoothly upon first rendered frame
        if (_isInitialized && _controller != null)
          AnimatedOpacity(
            opacity: _hasFirstFrame ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width > 0
                      ? _controller!.value.size.width
                      : 100,
                  height: _controller!.value.size.height > 0
                      ? _controller!.value.size.height
                      : 100,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return child;
  }
}
