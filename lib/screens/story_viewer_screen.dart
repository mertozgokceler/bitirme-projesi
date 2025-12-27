import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class StoryViewerScreen extends StatefulWidget {
  final String ownerUid;
  final String ownerName;
  final String ownerPhotoUrl;
  final List<Map<String, dynamic>> items;

  const StoryViewerScreen({
    super.key,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerPhotoUrl,
    required this.items,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _index = 0;
  VideoPlayerController? _v;

  Map<String, dynamic> get _cur => widget.items[_index];
  bool get _isVideo => (_cur['type'] ?? '').toString() == 'video';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    _disposeVideo();
    if (!mounted) return;

    if (_isVideo) {
      final url = (_cur['url'] ?? '').toString();
      if (url.isEmpty) return;

      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      _v = c;
      await c.initialize();
      await c.setLooping(false);
      await c.play();

      if (mounted) setState(() {});
      c.addListener(() {
        if (!mounted) return;
        final v = _v;
        if (v == null) return;
        if (v.value.isInitialized && v.value.position >= v.value.duration) {
          _next();
        }
      });
    } else {
      // image: auto advance 6s
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) _next();
      });
    }
  }

  void _next() {
    if (_index >= widget.items.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index++);
    _prepare();
  }

  void _prev() {
    if (_index <= 0) return;
    setState(() => _index--);
    _prepare();
  }

  void _disposeVideo() {
    final v = _v;
    _v = null;
    v?.dispose();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final url = (_cur['url'] ?? '').toString();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTapUp: (d) {
                  final w = MediaQuery.of(context).size.width;
                  if (d.localPosition.dx < w * 0.35) {
                    _prev();
                  } else {
                    _next();
                  }
                },
                child: Center(
                  child: _isVideo
                      ? (_v != null && _v!.value.isInitialized)
                      ? AspectRatio(
                    aspectRatio: _v!.value.aspectRatio,
                    child: VideoPlayer(_v!),
                  )
                      : const CircularProgressIndicator()
                      : (url.isNotEmpty)
                      ? Image.network(url, fit: BoxFit.contain)
                      : const SizedBox.shrink(),
                ),
              ),
            ),

            // top bar (owner)
            Positioned(
              left: 12,
              right: 12,
              top: 10,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: widget.ownerPhotoUrl.trim().isNotEmpty
                        ? NetworkImage(widget.ownerPhotoUrl)
                        : null,
                    child: widget.ownerPhotoUrl.trim().isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.ownerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // progress (basit)
            Positioned(
              left: 12,
              right: 12,
              top: 6,
              child: LinearProgressIndicator(
                value: (widget.items.isEmpty) ? 0 : (_index + 1) / widget.items.length,
                backgroundColor: Colors.white.withOpacity(0.18),
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
