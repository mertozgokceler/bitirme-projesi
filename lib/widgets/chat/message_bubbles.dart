import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

typedef OpenUrl = Future<void> Function(String url);
typedef ShowImagePreview = Future<void> Function(String url);

class MessageBubbles {
  static String formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static Widget metaRow({
    required bool isMe,
    required Timestamp? timestamp,
    required bool isRead,
    required Color metaText,
    required Color readTick,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatTimestamp(timestamp),
              style: TextStyle(fontSize: 12, color: metaText)),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(Icons.done_all, size: 16, color: isRead ? readTick : metaText),
          ],
        ],
      ),
    );
  }

  static Widget bubbleContainer({
    required bool isMe,
    required Widget child,
    required Color bubbleColor,
    required Color bubbleBorder,
    required double shadowOpacity,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(shadowOpacity),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
          border: Border.all(color: bubbleBorder),
        ),
        child: child,
      ),
    );
  }

  static Widget textBubble({
    required String text,
    required bool isMe,
    required Timestamp? timestamp,
    required bool isRead,
    required Color bubbleColor,
    required Color bubbleBorder,
    required double shadowOpacity,
    required Color meText,
    required Color otherText,
    required Color metaText,
    required Color readTick,
  }) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubbleContainer(
          isMe: isMe,
          bubbleColor: bubbleColor,
          bubbleBorder: bubbleBorder,
          shadowOpacity: shadowOpacity,
          child: Text(text, style: TextStyle(color: isMe ? meText : otherText)),
        ),
        const SizedBox(height: 4),
        metaRow(
          isMe: isMe,
          timestamp: timestamp,
          isRead: isRead,
          metaText: metaText,
          readTick: readTick,
        ),
      ],
    );
  }

  static Widget imageBubble({
    required String url,
    required bool isMe,
    required Timestamp? timestamp,
    required bool isRead,
    required ShowImagePreview onPreview,
    required Color metaText,
    required Color readTick,
  }) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => onPreview(url),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: 220,
              height: 220,
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 220,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        metaRow(
          isMe: isMe,
          timestamp: timestamp,
          isRead: isRead,
          metaText: metaText,
          readTick: readTick,
        ),
      ],
    );
  }

  static Widget videoBubble({
    required String url,
    required bool isMe,
    required Timestamp? timestamp,
    required bool isRead,
    required OpenUrl openUrl,
    required Color bubbleColor,
    required Color bubbleBorder,
    required double shadowOpacity,
    required Color meText,
    required Color otherText,
    required Color metaText,
    required Color readTick,
  }) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => openUrl(url),
          child: bubbleContainer(
            isMe: isMe,
            bubbleColor: bubbleColor,
            bubbleBorder: bubbleBorder,
            shadowOpacity: shadowOpacity,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(Icons.videocam, color: isMe ? meText : otherText),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? meText : otherText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.play_circle_fill, color: isMe ? meText : otherText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        metaRow(
          isMe: isMe,
          timestamp: timestamp,
          isRead: isRead,
          metaText: metaText,
          readTick: readTick,
        ),
      ],
    );
  }

  static Widget fileBubble({
    required String fileName,
    required String? fileUrl,
    required String iconPath,
    required bool isMe,
    required Timestamp? timestamp,
    required bool isRead,
    required OpenUrl openUrl,
    required Color bubbleColor,
    required Color bubbleBorder,
    required double shadowOpacity,
    required Color meText,
    required Color otherText,
    required Color metaText,
    required Color readTick,
  }) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: fileUrl != null ? () => openUrl(fileUrl) : null,
          child: bubbleContainer(
            isMe: isMe,
            bubbleColor: bubbleColor,
            bubbleBorder: bubbleBorder,
            shadowOpacity: shadowOpacity,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Image.asset(iconPath, width: 28, height: 28),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? meText : otherText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        metaRow(
          isMe: isMe,
          timestamp: timestamp,
          isRead: isRead,
          metaText: metaText,
          readTick: readTick,
        ),
      ],
    );
  }
}
