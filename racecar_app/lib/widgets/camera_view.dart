import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class CameraView extends StatelessWidget {
  final bool on;
  final String? host; // car IP; null = unknown
  final VoidCallback? onSetIp;

  const CameraView({super.key, required this.on, this.host, this.onSetIp});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0B13),
      child: Center(child: _content()),
    );
  }

  Widget _content() {
    if (!on) {
      return const _Hint(icon: Icons.videocam_off, label: 'Camera off');
    }
    if (host == null || host!.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Hint(icon: Icons.videocam, label: 'Camera on'),
          const SizedBox(height: 12),
          _SetIpButton(label: "Set car's IP to view", onTap: onSetIp),
        ],
      );
    }
    return _MjpegStream(
        url: 'http://$host:80/stream', onChangeIp: onSetIp);
  }
}

/// Decodes and displays an MJPEG-over-HTTP stream, with auto-reconnect.
class _MjpegStream extends StatefulWidget {
  final String url;
  final VoidCallback? onChangeIp;

  const _MjpegStream({required this.url, this.onChangeIp});

  @override
  State<_MjpegStream> createState() => _MjpegStreamState();
}

class _MjpegStreamState extends State<_MjpegStream> {
  static const _soi = [0xFF, 0xD8]; // JPEG start-of-image
  static const _eoi = [0xFF, 0xD9]; // JPEG end-of-image
  static const _maxBuffer = 512 * 1024; // drop junk if no frame found

  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;
  Timer? _retry;
  final List<int> _buf = [];
  Uint8List? _frame;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_MjpegStream old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    _stop();
    _buf.clear();
    if (mounted) setState(() => _error = false);
    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await _client!.getUrl(Uri.parse(widget.url));
      final resp = await req.close();
      _sub = resp.listen(_onData,
          onError: (_) => _fail(), onDone: _fail, cancelOnError: true);
    } catch (_) {
      _fail();
    }
  }

  void _stop() {
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _client?.close(force: true);
    _client = null;
  }

  void _fail() {
    if (!mounted) return;
    setState(() => _error = true);
    // Auto-reconnect (the car may still be booting / Wi-Fi blipped).
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), _start);
  }

  void _onData(List<int> data) {
    _buf.addAll(data);
    Uint8List? latest;
    // Drain every complete JPEG in the buffer, keep the most recent.
    while (true) {
      final start = _indexOf(_buf, _soi, 0);
      if (start < 0) break;
      final end = _indexOf(_buf, _eoi, start + 2);
      if (end < 0) {
        // No complete frame yet; guard against unbounded growth.
        if (_buf.length > _maxBuffer) _buf.removeRange(0, _buf.length - 2);
        break;
      }
      latest = Uint8List.fromList(_buf.sublist(start, end + 2));
      _buf.removeRange(0, end + 2);
    }
    if (latest != null && mounted) setState(() => _frame = latest);
  }

  // Find the first index of [pattern] in [data] at or after [from].
  int _indexOf(List<int> data, List<int> pattern, int from) {
    for (int i = from; i <= data.length - pattern.length; i++) {
      if (data[i] == pattern[0] && data[i + 1] == pattern[1]) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (_error && _frame == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Hint(icon: Icons.error_outline, label: "Can't reach camera"),
          const SizedBox(height: 4),
          Text(widget.url,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 8),
          _SetIpButton(label: 'Change IP', onTap: widget.onChangeIp),
        ],
      );
    }
    if (_frame == null) {
      return const _Hint(
          icon: Icons.hourglass_empty, label: 'Connecting to camera…');
    }
    return Image.memory(
      _frame!,
      gaplessPlayback: true, // no flicker between frames
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

class _SetIpButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SetIpButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.lan, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Hint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white24, size: 54),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white38)),
      ],
    );
  }
}
