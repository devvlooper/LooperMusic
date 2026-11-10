import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:video_player/video_player.dart';

/// Central host managing reference-counted [VideoPlayerController] instances
/// per media source (Doc 20 §5.3, fixes bugs A15-A17).
class MotionArtworkHost {
  static final Map<String, _HostEntry> _active = {};

  static Future<VideoPlayerController?> acquire(
    String playFrom, {
    required bool isLocal,
    required bool muted,
    required bool loop,
    required bool autoPlay,
  }) async {
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
        entry.controller.dispose();
      });
    }
  }
}

class _HostEntry {
  final VideoPlayerController controller;
  final Future<void> initFuture;
  int refCount;
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

    var playFrom = source;
    if (source.startsWith('http')) {
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
        loop: widget.loop,
        autoPlay: widget.autoPlay,
      );

      if (!mounted || _activeSource != playFrom || controller == null) {
        if (controller != null) MotionArtworkHost.release(playFrom);
        return;
      }

      _controller = controller;
      controller.addListener(_videoListener);

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

  void _disposeCurrentController() {
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
