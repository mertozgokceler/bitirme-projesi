import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AudioMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int duration;
  final bool isMe;
  final Timestamp? timestamp;
  final bool isRead;

  final AudioPlayer audioPlayer;

  final Color meBubble;
  final Color otherBubble;
  final Color meText;
  final Color otherText;
  final Color metaText;
  final Color readTick;
  final double shadowOpacity;
  final Color bubbleBorder;

  const AudioMessageBubble({
    super.key,
    required this.audioUrl,
    required this.duration,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    required this.audioPlayer,
    required this.meBubble,
    required this.otherBubble,
    required this.meText,
    required this.otherText,
    required this.metaText,
    required this.readTick,
    required this.shadowOpacity,
    required this.bubbleBorder,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  PlayerState? _playerState;
  StreamSubscription? _sub;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();

    _sub = widget.audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (_playingUrl == widget.audioUrl) {
        setState(() => _playerState = state);
      } else if (_playerState == PlayerState.playing) {
        setState(() => _playerState = PlayerState.stopped);
      }
    });

    widget.audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_playingUrl == widget.audioUrl) {
        setState(() {
          _playerState = PlayerState.completed;
          _playingUrl = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_playingUrl == widget.audioUrl) {
      widget.audioPlayer.stop();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      final isPlaying =
          (_playerState == PlayerState.playing) && (_playingUrl == widget.audioUrl);

      if (isPlaying) {
        await widget.audioPlayer.pause();
        if (mounted) setState(() => _playingUrl = null);
        return;
      }

      if (widget.audioPlayer.state == PlayerState.playing) {
        await widget.audioPlayer.stop();
      }

      await widget.audioPlayer.play(UrlSource(widget.audioUrl));
      if (mounted) setState(() => _playingUrl = widget.audioUrl);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ses dosyası oynatılamadı.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() {
        _playerState = PlayerState.stopped;
        _playingUrl = null;
      });
    }
  }

  String _fmtDuration(int seconds) {
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('HH:mm').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying =
        (_playerState == PlayerState.playing) && (_playingUrl == widget.audioUrl);

    final bubble = widget.isMe ? widget.meBubble : widget.otherBubble;
    final txt = widget.isMe ? widget.meText : widget.otherText;

    return Column(
      crossAxisAlignment:
      widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: bubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: widget.isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: widget.isMe ? Radius.zero : const Radius.circular(16),
            ),
            border: Border.all(color: widget.bubbleBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.shadowOpacity),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _toggle,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: txt),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                _fmtDuration(widget.duration),
                style: TextStyle(color: txt.withOpacity(0.85)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtTs(widget.timestamp),
                style: TextStyle(fontSize: 12, color: widget.metaText),
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.done_all,
                  size: 16,
                  color: widget.isRead ? widget.readTick : widget.metaText,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
