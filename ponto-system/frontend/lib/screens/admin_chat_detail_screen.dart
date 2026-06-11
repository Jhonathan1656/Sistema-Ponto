import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class AdminChatDetailScreen extends StatefulWidget {
  final String? conversationId;
  final String userId;
  final String userName;
  final List<Map<String, dynamic>> requests;

  const AdminChatDetailScreen({
    super.key,
    this.conversationId,
    required this.userId,
    required this.userName,
    required this.requests,
  });

  @override
  State<AdminChatDetailScreen> createState() => _AdminChatDetailScreenState();
}

class _AdminChatDetailScreenState extends State<AdminChatDetailScreen> {
  final _db = FirebaseFirestore.instance;
  final _audioPlayer = AudioPlayer();
  Timer? _refreshTimer;
  String? _currentlyPlayingUrl;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  Stream<List<Map<String, dynamic>>> _watchRequests() {
    if (widget.conversationId == null) {
      return _db
          .collection('adjustment_requests')
          .where('user_id', isEqualTo: widget.userId)
          .snapshots()
          .map((snap) {
        final requests =
            snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        requests.sort((a, b) =>
            (a['timestamp'] as String).compareTo(b['timestamp'] as String));
        return requests;
      });
    }

    return _db
        .collection('adjustment_requests')
        .where('conversation_id', isEqualTo: widget.conversationId)
        .snapshots()
        .map((snap) {
      final requests =
          snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      requests.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));
      return requests;
    });
  }

  @override
  void initState() {
    super.initState();
    _positionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) setState(() => _audioPosition = position);
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _audioDuration = duration);
    });
    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingUrl = null;
          _audioPosition = Duration.zero;
          _audioDuration = Duration.zero;
        });
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    if (_currentlyPlayingUrl == url) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlayingUrl = null;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });
    } else {
      await _audioPlayer.stop();
      setState(() {
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });
      if (url.startsWith('data:')) {
        final commaIndex = url.indexOf(',');
        if (commaIndex == -1) return;
        final bytes = base64Decode(url.substring(commaIndex + 1));
        await _audioPlayer.play(BytesSource(Uint8List.fromList(bytes)));
      } else {
        await _audioPlayer.play(UrlSource(url));
      }
      setState(() => _currentlyPlayingUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: const Color(0xFF8B0000),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _watchRequests(),
        initialData: widget.requests,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Erro ao carregar conversa: ${snapshot.error}'));
          }

          final requests = snapshot.data ?? widget.requests;
          if (requests.isEmpty) {
            return const Center(
                child: Text('Nenhuma mensagem encontrada.',
                    style: TextStyle(color: Colors.grey)));
          }

          return _buildRequestsList(context, requests);
        },
      ),
    );
  }

  Widget _buildRequestsList(
      BuildContext context, List<Map<String, dynamic>> requests) {
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (var req in requests) {
      final date = DateFormat('dd/MM/yyyy')
          .format(DateTime.parse(req['timestamp'] as String));
      byDay.putIfAbsent(date, () => []).add(req);
    }

    final days = byDay.keys.toList();
    days.sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final dayRequests = byDay[day]!;
        dayRequests.sort((a, b) =>
            (a['timestamp'] as String).compareTo(b['timestamp'] as String));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(day,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54)),
              ),
            ),
            ...dayRequests.map((req) => _buildMessageBubble(req)),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> req) {
    final audioSource = req['audio_url'] ?? req['audio_data_url'];
    final hasAudio = audioSource != null;
    final audioStatus = req['audio_upload_status'];
    final timestamp = DateTime.parse(req['timestamp'] as String);
    final uploadExpired = audioStatus == 'uploading' &&
        DateTime.now().difference(timestamp).inMinutes >= 5;
    final isAudioUploading = audioStatus == 'uploading' && !uploadExpired;
    final hasAudioError = audioStatus == 'error' || uploadExpired;
    final time = DateFormat('HH:mm').format(timestamp);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)
          ],
        ),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAudio || isAudioUploading || hasAudioError)
              _buildAudioPlayer(
                audioSource: audioSource?.toString(),
                levels: _audioLevelsForRequest(req, audioSource?.toString()),
                isUploading: isAudioUploading,
                hasError: hasAudioError,
              )
            else
              Text(req['message'] ?? '',
                  style: const TextStyle(fontSize: 15, color: Colors.black87)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayer({
    required String? audioSource,
    required List<double> levels,
    required bool isUploading,
    required bool hasError,
  }) {
    final isPlaying =
        audioSource != null && _currentlyPlayingUrl == audioSource;
    final progress = isPlaying && _audioDuration.inMilliseconds > 0
        ? (_audioPosition.inMilliseconds / _audioDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        if (audioSource != null)
          IconButton(
            icon: Icon(
              isPlaying ? Icons.stop : Icons.play_arrow,
              color: const Color(0xFF8B0000),
            ),
            onPressed: () => _playAudio(audioSource),
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: hasError
                  ? const Icon(Icons.error_outline, color: Colors.red, size: 20)
                  : const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF8B0000),
                    ),
            ),
          ),
        Expanded(
          child: SizedBox(
            height: 34,
            child: hasError || isUploading
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasError
                          ? 'Falha ao anexar audio'
                          : 'Audio processando...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: hasError ? Colors.red : Colors.grey,
                      ),
                    ),
                  )
                : _PlaybackWaveform(
                    levels: levels,
                    progress: progress,
                    color: const Color(0xFF8B0000),
                    backgroundColor: Colors.grey.shade300,
                  ),
          ),
        ),
      ],
    );
  }

  List<double> _audioLevelsForRequest(Map<String, dynamic> req, String? seed) {
    final rawLevels = req['audio_levels'];
    if (rawLevels is List && rawLevels.isNotEmpty) {
      return rawLevels
          .map((value) => (value as num?)?.toDouble() ?? 0.08)
          .where((value) => value.isFinite)
          .map((value) => value.clamp(0.06, 1.0))
          .toList();
    }

    return _fallbackAudioLevels(seed ?? req['id']?.toString() ?? '');
  }

  List<double> _fallbackAudioLevels(String seed) {
    var hash = seed.hashCode.abs();
    final levels = <double>[];
    for (var i = 0; i < 64; i++) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final wave = (math.sin(i * 0.48) + 1) / 2;
      final random = (hash % 1000) / 1000;
      final level = 0.14 + (wave * 0.35) + (random * 0.42);
      levels.add(level.clamp(0.08, 0.95));
    }
    return levels;
  }
}

class _PlaybackWaveform extends StatelessWidget {
  final List<double> levels;
  final double progress;
  final Color color;
  final Color backgroundColor;

  const _PlaybackWaveform({
    required this.levels,
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PlaybackWaveformPainter(
        levels: List<double>.of(levels),
        progress: progress,
        color: color,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class _PlaybackWaveformPainter extends CustomPainter {
  final List<double> levels;
  final double progress;
  final Color color;
  final Color backgroundColor;

  const _PlaybackWaveformPainter({
    required this.levels,
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final playedUntil = size.width * progress.clamp(0.0, 1.0);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const spacing = 8.0;
    final centerY = size.height / 2;

    for (var i = 0; i < levels.length; i++) {
      final x = spacing * i + paint.strokeWidth / 2;
      if (x > size.width) break;

      final level = levels[i].clamp(0.0, 1.0);
      final height = 4 + level * (size.height - 4);
      paint.color = x <= playedUntil ? color : backgroundColor;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlaybackWaveformPainter oldDelegate) {
    return oldDelegate.levels != levels ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
