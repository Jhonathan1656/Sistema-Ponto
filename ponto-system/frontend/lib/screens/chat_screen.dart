import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String title;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _apiService = ApiService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isPaused = false;
  Duration _recordDuration = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _audioLevels = <double>[];
  double _noiseFloorDb = -95;
  double _smoothedAudioLevel = 0.08;
  String? _currentlyPlayingUrl;
  bool _showIntroTyping = true;
  bool _showIntroMessage = false;
  bool _showConfirmationTyping = false;
  bool _showConfirmation = false;
  int _typingDotCount = 1;
  Timer? _introTypingTimer;
  Timer? _confirmationTypingTimer;
  Timer? _typingDotsTimer;

  static const Color wineColor = Color(0xFF8B0000);
  static const int _maxAudioBars = 90;

  @override
  void initState() {
    super.initState();
    _startTypingDots();
    _introTypingTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showIntroTyping = false;
        _showIntroMessage = true;
      });
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _introTypingTimer?.cancel();
    _confirmationTypingTimer?.cancel();
    _typingDotsTimer?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _watchMessages() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _db
        .collection('adjustment_requests')
        .where('conversation_id', isEqualTo: widget.conversationId)
        .where('user_id', isEqualTo: user.uid)
        .snapshots()
        .map((snap) {
      final messages =
          snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      messages.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));
      return messages;
    });
  }

  Future<void> _sendMessage(
      {String? text,
      String? audioPath,
      Uint8List? audioBytes,
      List<double>? audioLevels}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final userName =
        (userDoc.data()?['name'] ?? user.email ?? 'Usuario').toString();
    final hasAudio = audioPath != null || audioBytes != null;
    final now = DateTime.now().toIso8601String();
    final message = text ?? (hasAudio ? 'Mensagem de audio' : '');

    final docRef = await _db.collection('adjustment_requests').add({
      'conversation_id': widget.conversationId,
      'user_id': user.uid,
      'user_name': userName,
      'sender_id': user.uid,
      'sender_role': 'user',
      'message': message,
      'audio_url': null,
      'audio_levels': audioLevels,
      'audio_upload_status': hasAudio ? 'uploading' : null,
      'timestamp': now,
      'status': 'unread',
    });

    await _db
        .collection('adjustment_conversations')
        .doc(widget.conversationId)
        .set({
      'user_id': user.uid,
      'user_name': userName,
      'title': message,
      'last_message': message,
      'last_time': now,
      'updated_at': now,
      'status': 'open',
      'deleted': false,
      'deleted_at': null,
      'deleted_by_type': null,
      'deleted_by_name': null,
    }, SetOptions(merge: true));

    if (hasAudio) {
      unawaited(_uploadAudio(docRef.id,
          audioPath: audioPath, audioBytes: audioBytes));
    }

    _showAssistantConfirmationAfterTyping();
    _scrollToBottom();
  }

  void _startTypingDots() {
    _typingDotsTimer?.cancel();
    _typingDotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      if (!_showIntroTyping && !_showConfirmationTyping) return;
      setState(() =>
          _typingDotCount = _typingDotCount == 4 ? 1 : _typingDotCount + 1);
    });
  }

  void _showAssistantConfirmationAfterTyping() {
    _confirmationTypingTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showConfirmation = false;
      _showConfirmationTyping = true;
      _typingDotCount = 1;
    });
    _scrollToBottom();

    _confirmationTypingTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showConfirmationTyping = false;
        _showConfirmation = true;
      });
      _scrollToBottom();
    });
  }

  Future<void> _uploadAudio(String requestId,
      {String? audioPath, Uint8List? audioBytes}) async {
    try {
      Uint8List bytes;
      String mimeType;
      if (kIsWeb && audioBytes != null) {
        bytes = audioBytes;
        mimeType = 'audio/webm';
      } else if (!kIsWeb && audioPath != null) {
        bytes = await File(audioPath).readAsBytes();
        mimeType = 'audio/mp4';
      } else {
        throw Exception('Audio nao encontrado.');
      }

      const maxEmbeddedBytes = 700 * 1024;
      if (bytes.length > maxEmbeddedBytes) {
        throw Exception('Audio muito grande. Grave um audio mais curto.');
      }

      await _db.collection('adjustment_requests').doc(requestId).update({
        'audio_data_url': 'data:$mimeType;base64,${base64Encode(bytes)}',
        'audio_mime_type': mimeType,
        'audio_upload_status': 'embedded',
      });
    } catch (e) {
      await _db.collection('adjustment_requests').doc(requestId).update({
        'audio_upload_status': 'error',
        'audio_upload_error': e.toString(),
      });
    }
  }

  Future<void> _editMessage(Map<String, dynamic> msg) async {
    final id = msg['id'];
    if (id == null) return;

    final controller =
        TextEditingController(text: msg['message']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Digite o novo texto...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                await _apiService.updateAdjustmentMessage(id, newText);
                await _updateConversationPreview(
                  title: newText,
                  lastMessage: newText,
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final id = msg['id'];
    if (id == null) return;
    await _apiService.deleteAdjustmentRequest(id, audioUrl: msg['audio_url']);
    await _refreshConversationPreviewAfterDelete();
  }

  Future<void> _updateConversationPreview(
      {required String title, required String lastMessage}) async {
    await _db
        .collection('adjustment_conversations')
        .doc(widget.conversationId)
        .set({
      'title': title,
      'last_message': lastMessage,
      'last_time': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> _refreshConversationPreviewAfterDelete() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snap = await _db
        .collection('adjustment_requests')
        .where('conversation_id', isEqualTo: widget.conversationId)
        .where('user_id', isEqualTo: user.uid)
        .get();

    final remaining = snap.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList()
      ..sort((a, b) =>
          (b['timestamp'] as String).compareTo(a['timestamp'] as String));

    if (remaining.isEmpty) {
      await _db
          .collection('adjustment_conversations')
          .doc(widget.conversationId)
          .delete();
      return;
    }

    final last = remaining.first;
    final lastMessage = (last['message'] ?? 'Mensagem').toString();
    await _updateConversationPreview(
        title: lastMessage, lastMessage: lastMessage);
  }

  Future<void> _startRecording() async {
    bool hasPermission;
    if (kIsWeb) {
      hasPermission = await _audioRecorder.hasPermission();
    } else {
      final status = await Permission.microphone.request();
      hasPermission = status.isGranted && await _audioRecorder.hasPermission();
    }

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissao de microfone negada.')));
      }
      return;
    }

    String? path;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/adjustment_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }

    await _audioRecorder.start(
      const RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path ?? '',
    );

    setState(() {
      _isRecording = true;
      _isPaused = false;
      _recordDuration = Duration.zero;
      _resetAudioLevels();
    });
    _startAmplitudeListener();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_isPaused) {
        setState(() => _recordDuration += const Duration(seconds: 1));
      }
    });
  }

  void _startAmplitudeListener() {
    _amplitudeSub?.cancel();
    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amplitude) {
      if (!mounted) return;
      final level = _isPaused ? 0.08 : _normalizeAmplitude(amplitude);
      setState(() {
        if (_audioLevels.length >= _maxAudioBars) {
          _audioLevels.removeAt(0);
        }
        _audioLevels.add(level);
      });
    });
  }

  double _normalizeAmplitude(Amplitude amplitude) {
    final dbfs = amplitude.current;
    if (dbfs.isNaN || dbfs.isInfinite) return 0.08;
    final currentDb = dbfs.clamp(-160.0, 0.0);

    if (currentDb <= -155) {
      _smoothedAudioLevel = (_smoothedAudioLevel * 0.7) + (0.08 * 0.3);
      return _smoothedAudioLevel;
    }

    if (currentDb < _noiseFloorDb + 6) {
      _noiseFloorDb = (_noiseFloorDb * 0.92) + (currentDb * 0.08);
    } else {
      _noiseFloorDb = (_noiseFloorDb * 0.995) + (currentDb * 0.005);
    }

    final voiceLift = ((currentDb - _noiseFloorDb - 3) / 32).clamp(0.0, 1.0);
    final absoluteLift = ((currentDb + 92) / 62).clamp(0.0, 1.0);
    final boosted = math.max(voiceLift, absoluteLift);
    final target = 0.06 + math.pow(boosted, 0.48).toDouble() * 0.94;
    final smoothing = target > _smoothedAudioLevel ? 0.62 : 0.28;

    _smoothedAudioLevel =
        (_smoothedAudioLevel * (1 - smoothing)) + (target * smoothing);
    return _smoothedAudioLevel.clamp(0.06, 1.0);
  }

  void _resetAudioLevels() {
    _noiseFloorDb = -95;
    _smoothedAudioLevel = 0.08;
    _audioLevels.clear();
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _audioRecorder.stop();
    final audioLevels = List<double>.of(_audioLevels);
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _resetAudioLevels();
    });

    if (path == null) return;

    if (kIsWeb) {
      final response =
          await http.get(Uri.parse(path)).timeout(const Duration(seconds: 15));
      if (response.bodyBytes.isEmpty) return;
      await _sendMessage(
          audioBytes: response.bodyBytes, audioLevels: audioLevels);
    } else {
      await _sendMessage(audioPath: path, audioLevels: audioLevels);
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _audioRecorder.cancel();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _resetAudioLevels();
    });
  }

  Future<void> _pauseResumeRecording() async {
    if (_isPaused) {
      await _audioRecorder.resume();
      setState(() => _isPaused = false);
    } else {
      await _audioRecorder.pause();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _playAudio(String? url) async {
    if (url == null) return;
    if (_currentlyPlayingUrl == url) {
      await _audioPlayer.stop();
      setState(() => _currentlyPlayingUrl = null);
      return;
    }

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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _sendMessage(text: text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: wineColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _watchMessages(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          'Erro ao carregar mensagens: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: wineColor),
                  );
                }

                final messages = snapshot.data ?? [];
                final showIntro =
                    messages.isEmpty && (_showIntroTyping || _showIntroMessage);
                final showConfirmation =
                    _showConfirmationTyping || _showConfirmation;
                final introCount = showIntro ? 1 : 0;
                final confirmationCount = showConfirmation ? 1 : 0;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + introCount + confirmationCount,
                  itemBuilder: (context, index) {
                    if (showIntro && index == 0) {
                      if (_showIntroTyping) return _buildTypingBubble();
                      return _buildBotBubble();
                    }

                    final messageIndex = index - introCount;
                    if (showConfirmation && messageIndex == messages.length) {
                      if (_showConfirmationTyping) return _buildTypingBubble();
                      return _buildConfirmationBubble();
                    }

                    return _buildMessageBubble(messages[messageIndex]);
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildBotBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Text(
            'Ola! Sou o assistente VMac. Como posso ajustar seu ponto hoje?'),
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          'digitando${'.' * _typingDotCount}',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Text(
            'Obrigado! Sua solicitacao foi enviada para o painel do administrador.'),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final audioSource = msg['audio_url'] ?? msg['audio_data_url'];
    final hasAudio = audioSource != null || msg['audio_upload_status'] != null;
    final isSending = msg['audio_upload_status'] == 'uploading';
    final hasError = msg['audio_upload_status'] == 'error';
    final isManagerMessage = msg['sender_role'] == 'admin';
    final time =
        DateTime.tryParse(msg['timestamp']?.toString() ?? '') ?? DateTime.now();

    return Align(
      alignment:
          isManagerMessage ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSending && !isManagerMessage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
              onSelected: (value) {
                if (value == 'edit') {
                  _editMessage(msg);
                } else if (value == 'delete') {
                  _confirmDeleteMessage(msg, hasAudio);
                }
              },
              itemBuilder: (context) => [
                if (!hasAudio)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(hasAudio ? 'Apagar audio' : 'Apagar'),
                    ],
                  ),
                ),
              ],
            ),
          GestureDetector(
            onLongPress: isSending || isManagerMessage
                ? null
                : () => _showOptions(msg, hasAudio),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isManagerMessage
                    ? Colors.grey.shade200
                    : (hasError ? Colors.red.shade900 : wineColor),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isManagerMessage ? 0 : 16),
                  bottomRight: Radius.circular(isManagerMessage ? 16 : 0),
                ),
              ),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasAudio)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (audioSource != null)
                          IconButton(
                            icon: Icon(
                                _currentlyPlayingUrl == audioSource
                                    ? Icons.stop
                                    : Icons.play_arrow,
                                color: isManagerMessage
                                    ? wineColor
                                    : Colors.white),
                            onPressed: () => _playAudio(audioSource),
                          )
                        else
                          Icon(Icons.mic,
                              color: isManagerMessage
                                  ? Colors.black54
                                  : Colors.white70,
                              size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isSending
                              ? 'Enviando audio...'
                              : (hasError
                                  ? 'Falha ao anexar audio'
                                  : 'Mensagem de audio'),
                          style: TextStyle(
                              color: isManagerMessage
                                  ? Colors.black87
                                  : Colors.white),
                        ),
                      ],
                    )
                  else
                    Text(msg['message']?.toString() ?? '',
                        style: TextStyle(
                            color: isManagerMessage
                                ? Colors.black87
                                : Colors.white)),
                  const SizedBox(height: 4),
                  Text(DateFormat('HH:mm').format(time),
                      style: TextStyle(
                          color: isManagerMessage
                              ? Colors.black54
                              : Colors.white70,
                          fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOptions(Map<String, dynamic> msg, bool hasAudio) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasAudio)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(context);
                _editMessage(msg);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(hasAudio ? 'Apagar audio' : 'Apagar'),
            onTap: () {
              Navigator.pop(context);
              _confirmDeleteMessage(msg, hasAudio);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteMessage(
      Map<String, dynamic> msg, bool hasAudio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasAudio ? 'Apagar audio?' : 'Apagar mensagem?'),
        content: const Text('Essa acao nao pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('APAGAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteMessage(msg);
    }
  }

  Widget _buildInputArea() {
    if (_isRecording) return _buildRecordingOverlay();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.mic, color: wineColor),
                onPressed: _startRecording),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Digite o que precisa ajustar...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.1),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.send, color: wineColor),
                onPressed: _sendText),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    final duration =
        '${_recordDuration.inMinutes.toString().padLeft(2, '0')}:${(_recordDuration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Text(duration,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 32,
                child: _AudioLevelWaveform(
                  levels: _audioLevels,
                  color: _isPaused ? Colors.grey : wineColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: _cancelRecording),
            IconButton(
                icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause,
                    color: wineColor),
                onPressed: _pauseResumeRecording),
            IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _stopAndSend),
          ],
        ),
      ),
    );
  }
}

class _AudioLevelWaveform extends StatelessWidget {
  final List<double> levels;
  final Color color;

  const _AudioLevelWaveform({
    required this.levels,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AudioLevelWaveformPainter(
        levels: List<double>.of(levels),
        color: color,
      ),
    );
  }
}

class _AudioLevelWaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;

  const _AudioLevelWaveformPainter({
    required this.levels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final centerY = size.height / 2;
    const spacing = 9.0;

    for (var i = 0; i < levels.length; i++) {
      final x = spacing * i + paint.strokeWidth / 2;
      if (x > size.width) break;

      final level = levels[i].clamp(0.0, 1.0);
      final height = 3 + level * (size.height - 3);
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioLevelWaveformPainter oldDelegate) {
    return oldDelegate.levels != levels || oldDelegate.color != color;
  }
}
