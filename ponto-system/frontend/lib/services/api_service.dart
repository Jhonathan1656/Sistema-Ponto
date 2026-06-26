import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

class AdjustmentRequestResult {
  final String id;
  final String? audioUrl;
  final bool audioUploadPending;

  const AdjustmentRequestResult({
    required this.id,
    this.audioUrl,
    this.audioUploadPending = false,
  });
}

class ApiService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _offlineRecordsKey = 'offline_time_records';
  static const String _cachedUserKey = 'cached_current_user';
  static String get backendUrl => AppConfig.backendUrl;
  static List<String> get backendUrls => AppConfig.backendUrls;

  Future<User> _waitForAuthenticatedUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) return currentUser;

    final user = await _auth
        .authStateChanges()
        .firstWhere((user) => user != null)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (user == null) {
      throw Exception('Usuario nao autenticado.');
    }
    return user;
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final user = await _waitForAuthenticatedUser();
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception('Nao foi possivel renovar sua sessao. Entre novamente.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  String _apiError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded['detail']?.toString() ?? response.body;
    } catch (_) {
      return response.body;
    }
  }

  Future<http.Response> _getBackend(
    String path, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    Object? lastError;
    for (final baseUrl in backendUrls) {
      try {
        return await http
            .get(Uri.parse('$baseUrl$path'), headers: headers)
            .timeout(timeout);
      } catch (e) {
        lastError = e;
        debugPrint('ApiService: falha em $baseUrl$path: $e');
      }
    }
    throw Exception(
      'Nao foi possivel conectar ao servidor. Tentativas: ${backendUrls.join(', ')}. Ultimo erro: $lastError',
    );
  }

  Future<http.Response> _postBackend(
    String path, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    Object? lastError;
    for (final baseUrl in backendUrls) {
      try {
        return await http
            .post(Uri.parse('$baseUrl$path'), headers: headers)
            .timeout(timeout);
      } catch (e) {
        lastError = e;
        debugPrint('ApiService: falha em $baseUrl$path: $e');
      }
    }
    throw Exception(
      'Nao foi possivel conectar ao servidor. Tentativas: ${backendUrls.join(', ')}. Ultimo erro: $lastError',
    );
  }

  Future<List<Map<String, dynamic>>> getSignatureDocuments(
      {required bool admin}) async {
    final response = await _getBackend(
      admin ? '/admin/signature-documents' : '/signature-documents',
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createSignatureDocument({
    required String targetUserId,
    required String targetUserName,
    required String targetUserEmail,
    required String title,
    required String message,
    required String fileName,
    required Uint8List pdfBytes,
  }) async {
    final documentId =
        '${DateTime.now().microsecondsSinceEpoch}_${targetUserId.substring(0, 6)}';
    final headers = await _authorizedHeaders();
    http.Response? response;
    Object? lastError;
    for (final baseUrl in backendUrls) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/admin/signature-documents'),
        );
        request.headers.addAll(headers);
        request.fields.addAll({
          'target_user_id': targetUserId,
          'target_user_name': targetUserName,
          'target_user_email': targetUserEmail,
          'local_document_id': documentId,
          'title': title,
          'message': message,
        });
        request.files.add(http.MultipartFile.fromBytes(
          'pdf',
          pdfBytes,
          filename: fileName,
        ));
        final streamed =
            await request.send().timeout(const Duration(seconds: 45));
        response = await http.Response.fromStream(streamed);
        break;
      } catch (e) {
        lastError = e;
        debugPrint('ApiService: falha ao enviar documento em $baseUrl: $e');
      }
    }
    if (response == null) {
      throw Exception(
        'Nao foi possivel conectar ao servidor. Tentativas: ${backendUrls.join(', ')}. Ultimo erro: $lastError',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> refreshSignatureDocument(
      String documentId) async {
    final response = await _postBackend(
      '/signature-documents/$documentId/refresh',
      headers: await _authorizedHeaders(),
      timeout: const Duration(seconds: 20),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<List<Map<String, dynamic>>> getSignatureNotifications() async {
    final response = await _getBackend(
      '/signature-notifications',
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> markSignatureNotificationsRead() async {
    final response = await _postBackend(
      '/signature-notifications/read',
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
  }

  Future<void> _cacheCurrentUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUser = <String, dynamic>{
      for (final key in const [
        'id',
        'uid',
        'email',
        'name',
        'cpf',
        'role',
        'job_title',
        'daily_hours',
      ])
        if (user[key] != null) key: user[key],
    };
    await prefs.setString(_cachedUserKey, jsonEncode(cachedUser));
  }

  Future<Map<String, dynamic>?> getCachedCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString(_cachedUserKey);
    if (rawUser == null || rawUser.isEmpty) return null;

    try {
      return Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
    } catch (e) {
      debugPrint('Erro ao ler perfil offline: $e');
      await prefs.remove(_cachedUserKey);
      return null;
    }
  }

  Future<bool> hasCachedSession() async {
    return await getCachedCurrentUser() != null;
  }

  Future<bool> _hasNetworkConnection() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  // --- MÉTODOS DE AJUSTE (CHAT INTERNO) ---

  Future<AdjustmentRequestResult> createAdjustmentRequest(
      {String? text, String? audioPath, Uint8List? audioBytes}) async {
    final user = await getCurrentUser();
    final hasAudio = audioPath != null || audioBytes != null;

    try {
      final docRef = await _db.collection('adjustment_requests').add({
        'user_id': user['id'],
        'user_name': user['name'],
        'message': text ?? (hasAudio ? 'Mensagem de áudio' : null),
        'audio_url': null,
        'audio_upload_status': hasAudio ? 'uploading' : null,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'unread',
      });

      debugPrint('ApiService: Documento Firestore criado: ${docRef.id}');

      if (hasAudio) {
        unawaited(_uploadAndAttachAdjustmentAudio(
          requestId: docRef.id,
          audioPath: audioPath,
          audioBytes: audioBytes,
        ));
      }

      return AdjustmentRequestResult(
          id: docRef.id, audioUploadPending: hasAudio);
    } catch (e) {
      debugPrint('ERRO CRÍTICO em createAdjustmentRequest: $e');
      rethrow;
    }
  }

  Future<void> _uploadAndAttachAdjustmentAudio({
    required String requestId,
    String? audioPath,
    Uint8List? audioBytes,
  }) async {
    try {
      String audioUrl;
      if (kIsWeb && audioBytes != null) {
        debugPrint(
            'ApiService: Iniciando upload áudio Web (${audioBytes.length} bytes)');
        audioUrl = await uploadAdjustmentAudioWeb(audioBytes);
      } else if (!kIsWeb && audioPath != null) {
        debugPrint('ApiService: Iniciando upload áudio Mobile ($audioPath)');
        audioUrl = await uploadAdjustmentAudioMobile(audioPath);
      } else {
        throw Exception('Áudio não encontrado para upload.');
      }

      await _db.collection('adjustment_requests').doc(requestId).update({
        'audio_url': audioUrl,
        'audio_upload_status': 'sent',
      });
      debugPrint('ApiService: Upload concluído e anexado. URL: $audioUrl');
    } catch (e) {
      debugPrint('Erro ao anexar áudio no ajuste $requestId: $e');
      if (audioBytes != null &&
          await _embedAudioInRequest(requestId, audioBytes, 'audio/webm')) {
        return;
      }

      if (audioPath != null && !kIsWeb) {
        try {
          final bytes = await File(audioPath).readAsBytes();
          if (await _embedAudioInRequest(requestId, bytes, 'audio/mp4')) {
            return;
          }
        } catch (fileError) {
          debugPrint('Erro ao ler áudio local para fallback: $fileError');
        }
      }

      try {
        await _db.collection('adjustment_requests').doc(requestId).update({
          'audio_upload_status': 'error',
          'audio_upload_error': e.toString(),
        }).timeout(const Duration(seconds: 10));
      } catch (updateError) {
        debugPrint(
            'Erro ao atualizar status do áudio no ajuste $requestId: $updateError');
      }
    }
  }

  Future<bool> _embedAudioInRequest(
      String requestId, Uint8List bytes, String mimeType) async {
    const maxEmbeddedBytes = 700 * 1024;
    if (bytes.length > maxEmbeddedBytes) {
      debugPrint(
          'Áudio muito grande para embutir no Firestore: ${bytes.length} bytes');
      return false;
    }

    try {
      await _db.collection('adjustment_requests').doc(requestId).update({
        'audio_data_url': 'data:$mimeType;base64,${base64Encode(bytes)}',
        'audio_mime_type': mimeType,
        'audio_upload_status': 'embedded',
      }).timeout(const Duration(seconds: 15));
      debugPrint(
          'Áudio embutido no Firestore como fallback (${bytes.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('Erro ao embutir áudio no Firestore: $e');
      return false;
    }
  }

  Future<String> uploadAdjustmentAudioMobile(String filePath) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não logado');

    final ref = _storage.ref().child(
        'adjustments/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await ref.putFile(File(filePath)).timeout(const Duration(seconds: 45));
    return await ref.getDownloadURL();
  }

  Future<String> uploadAdjustmentAudioWeb(Uint8List bytes) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não logado');

    final ref = _storage.ref().child(
        'adjustments/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.webm');

    // Configura o metadata para garantir que o navegador entenda que é um áudio
    final metadata = SettableMetadata(
      contentType: 'audio/webm',
      customMetadata: {'platform': 'web'},
    );

    final uploadTask = ref.putData(bytes, metadata);

    // Acompanha o progresso (opcional, mas bom para debug)
    final progressSubscription = uploadTask.snapshotEvents.listen((event) {
      debugPrint(
          'Upload progress: ${event.bytesTransferred}/${event.totalBytes}');
    });

    try {
      final snapshot = await uploadTask.timeout(
        const Duration(seconds: 120),
        onTimeout: () async {
          await uploadTask.cancel();
          throw TimeoutException(
              'Upload do áudio demorou mais de 120 segundos.');
        },
      );
      return await snapshot.ref.getDownloadURL();
    } finally {
      await progressSubscription.cancel();
    }
  }

  Stream<int> getUnreadAdjustmentsCount() {
    return _db
        .collection('adjustment_requests')
        .where('status', isEqualTo: 'unread')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<List<Map<String, dynamic>>> getAllAdjustmentRequests() async {
    final snap = await _db
        .collection('adjustment_requests')
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Stream<List<Map<String, dynamic>>> watchAdjustmentRequestsForUser(
      String userId) {
    return _db
        .collection('adjustment_requests')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final requests =
          snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      requests.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));
      return requests;
    });
  }

  Stream<List<Map<String, dynamic>>> watchCurrentUserAdjustmentRequests() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.error(Exception('Usuário não logado'));
    }
    return watchAdjustmentRequestsForUser(user.uid);
  }

  Future<void> markAdjustmentAsRead(String requestId) async {
    await _db
        .collection('adjustment_requests')
        .doc(requestId)
        .update({'status': 'read'});
  }

  Future<void> updateAdjustmentMessage(
      String requestId, String newMessage) async {
    await _db.collection('adjustment_requests').doc(requestId).update({
      'message': newMessage,
      'edited_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteAdjustmentRequest(String requestId,
      {String? audioUrl}) async {
    if (audioUrl != null) {
      try {
        await _storage.refFromURL(audioUrl).delete();
      } catch (e) {
        debugPrint('Erro ao deletar áudio do storage: $e');
      }
    }
    await _db.collection('adjustment_requests').doc(requestId).delete();
  }

  // --- MÉTODOS DE AUTH ---
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      // 1. Tentar Login no Firebase Auth
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);

      if (result.user == null) {
        throw Exception('Firebase Auth: Usuário nulo após login.');
      }

      // 2. Buscar documento no Firestore
      DocumentSnapshot userDoc =
          await _db.collection('users').doc(result.user!.uid).get();

      Map<String, dynamic> userData;
      if (userDoc.exists) {
        userData = userDoc.data() as Map<String, dynamic>;
      } else {
        // Se não existir no Firestore, cria um documento básico para não quebrar o login
        userData = {
          'email': email,
          'name': email.split('@')[0],
          'role': 'employee',
          'daily_hours': 8.0,
          'created_at': FieldValue.serverTimestamp(),
        };
        await _db.collection('users').doc(result.user!.uid).set(userData);
      }

      final String? token = await result.user!.getIdToken();

      final response = {
        'access_token': token,
        'user': {'id': result.user!.uid, ...userData}
      };
      await _cacheCurrentUser(
          Map<String, dynamic>.from(response['user'] as Map));
      return response;
    } on FirebaseAuthException catch (e) {
      // Mapeamento de erros amigáveis para o usuário
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'E-mail não cadastrado.';
          break;
        case 'wrong-password':
          errorMessage = 'Senha incorreta.';
          break;
        case 'invalid-email':
          errorMessage = 'Formato de e-mail inválido.';
          break;
        case 'user-disabled':
          errorMessage = 'Esta conta foi desativada.';
          break;
        case 'too-many-requests':
          errorMessage = 'Muitas tentativas. Aguarde um momento.';
          break;
        case 'invalid-credential':
          errorMessage = 'E-mail ou senha incorretos.';
          break;
        default:
          errorMessage = 'Erro de Autenticação (${e.code}): ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      // Erro genérico
      throw Exception('Falha ao processar login: $e');
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String name,
    required String cpf,
    required String password,
    String role = 'employee',
    double dailyHours = 8.0,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      Map<String, dynamic> userData = {
        'uid': result.user!.uid,
        'email': email,
        'name': name,
        'cpf': cpf,
        'role': role,
        'job_title': role == 'intern' ? 'Estagiario' : 'Aux. Geral',
        'daily_hours': dailyHours,
        'created_at': FieldValue.serverTimestamp(),
      };
      await _db.collection('users').doc(result.user!.uid).set(userData);
      final user = {'id': result.user!.uid, ...userData};
      await _cacheCurrentUser(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception('Registro falhou: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final user = await _auth.authStateChanges().first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => _auth.currentUser,
        );
    if (user != null) {
      try {
        final currentUser =
            await _getCurrentUserOnline().timeout(const Duration(seconds: 10));
        await _cacheCurrentUser(currentUser);
        return currentUser;
      } catch (e) {
        debugPrint('Perfil online indisponivel, usando cache local: $e');
      }
    }

    final cachedUser = await getCachedCurrentUser();
    if (cachedUser != null &&
        (user == null || cachedUser['id']?.toString() == user.uid)) {
      return cachedUser;
    }

    throw Exception('Perfil do usuario nao encontrado neste aparelho.');
  }

  Future<Map<String, dynamic>> _getCurrentUserOnline() async {
    final user = await _waitForAuthenticatedUser();
    DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return {'id': user.uid, ...doc.data() as Map<String, dynamic>};
    }
    throw Exception('Perfil do usuário não encontrado');
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUserKey);
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception('Erro ao enviar e-mail de recuperação: ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>> getOfflineRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final rawRecords = prefs.getStringList(_offlineRecordsKey) ?? [];

    return rawRecords
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .toList();
  }

  Future<void> _saveOfflineRecord(Map<String, dynamic> recordData) async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_offlineRecordsKey) ?? [];
    records.add(jsonEncode(recordData));
    await prefs.setStringList(_offlineRecordsKey, records);
  }

  Future<void> _replaceOfflineRecords(
      List<Map<String, dynamic>> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _offlineRecordsKey,
      records.map((record) => jsonEncode(record)).toList(),
    );
  }

  Future<int> syncOfflineRecords() async {
    final pendingRecords = await getOfflineRecords();
    if (pendingRecords.isEmpty) return 0;

    int syncedCount = 0;
    final failedRecords = <Map<String, dynamic>>[];

    for (final record in pendingRecords) {
      try {
        final firestoreData = Map<String, dynamic>.from(record)
          ..remove('id')
          ..remove('offline')
          ..remove('sync_status')
          ..remove('created_at_local');

        firestoreData['created_at'] = FieldValue.serverTimestamp();
        firestoreData['synced_from_offline'] = true;

        final recordId = record['id']?.toString();
        if (recordId == null || recordId.isEmpty) {
          throw Exception('Registro offline sem identificador.');
        }

        await _db
            .collection('time_records')
            .doc(recordId)
            .set(firestoreData)
            .timeout(const Duration(seconds: 15));
        syncedCount++;
      } catch (e) {
        debugPrint('Erro ao sincronizar ponto offline ${record['id']}: $e');
        failedRecords.add(record);
      }
    }

    await _replaceOfflineRecords(failedRecords);
    return syncedCount;
  }

  // --- LÓGICA DE CÁLCULO (BASEADA NOS SCRIPTS PYTHON) ---

  DateTime _roundTime(DateTime dt) {
    int minutes = dt.minute;
    if (minutes <= 15) return DateTime(dt.year, dt.month, dt.day, dt.hour, 0);
    if (minutes <= 45) return DateTime(dt.year, dt.month, dt.day, dt.hour, 30);
    return DateTime(dt.year, dt.month, dt.day, dt.hour + 1, 0);
  }

  bool _isFeriado(DateTime date) {
    final ano = date.year;
    final fixos = [
      '01/01',
      '21/04',
      '01/05',
      '07/09',
      '12/10',
      '02/11',
      '15/11',
      '25/12'
    ];
    String diaMes = DateFormat('dd/MM').format(date);
    if (fixos.contains(diaMes)) return true;

    // Páscoa e Sexta-feira Santa (Algoritmo de Meeus/Jones/Butcher)
    int a = ano % 19;
    int b = ano ~/ 100;
    int c = ano % 100;
    int d = b ~/ 4;
    int e = b % 4;
    int f = (b + 8) ~/ 25;
    int g = (b - f + 1) ~/ 3;
    int h = (19 * a + b - d - g + 15) % 30;
    int i = c ~/ 4;
    int k = c % 4;
    int l = (32 + 2 * e + 2 * i - h - k) % 7;
    int m = (a + 11 * h + 22 * l) ~/ 451;
    int mesPascoa = (h + l - 7 * m + 114) ~/ 31;
    int diaPascoa = ((h + l - 7 * m + 114) % 31) + 1;
    DateTime pascoa = DateTime(ano, mesPascoa, diaPascoa);
    DateTime sextaSanta = pascoa.subtract(const Duration(days: 2));

    return date.day == sextaSanta.day && date.month == sextaSanta.month;
  }

  Map<String, double> _classifyHours(
      DateTime start, DateTime end, String role) {
    double normal = 0, extras = 0, extra50 = 0, extra100 = 0;
    bool isEstagiario = role == 'intern' || role == 'estagiario';
    bool holidayOrSunday =
        _isFeriado(start) || start.weekday == DateTime.sunday;

    DateTime current = start;
    while (current.isBefore(end)) {
      DateTime next = current.add(const Duration(minutes: 1));
      int hour = current.hour;
      double minFrac = 1 / 60.0;

      if (holidayOrSunday) {
        extra100 += minFrac;
      } else {
        // 100% Noturno: 22h às 05h
        if (hour >= 22 || hour < 5) {
          extra100 += minFrac;
        }
        // Sábado 05h às 22h: 50%
        else if (start.weekday == DateTime.saturday) {
          extra50 += minFrac;
        }
        // Dias Úteis
        else {
          if (isEstagiario) {
            // Regra Estagiário: 13:30 às 19:30 é normal
            double timeVal = current.hour + (current.minute / 60.0);
            if (timeVal >= 13.5 && timeVal < 19.5) {
              normal += minFrac;
            } else {
              extras += minFrac;
            }
          } else {
            normal += minFrac;
          }
        }
      }
      current = next;
    }
    return {
      'normal': normal,
      'extras': extras,
      'extra50': extra50,
      'extra100': extra100
    };
  }

  // --- MÉTODOS DE DADOS ---

  Future<Map<String, dynamic>> createTimeRecord({
    required String recordType,
    String? location,
    String? notes,
    String? timestamp,
    String? userId,
    double? latitude,
    double? longitude,
  }) async {
    final currentUser = _auth.currentUser;
    final cachedUser = await getCachedCurrentUser();
    final currentUserId = currentUser?.uid ?? cachedUser?['id']?.toString();
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception(
          'Faca login com internet uma vez antes de registrar offline.');
    }

    final targetUid = userId ?? currentUserId;
    final now = DateTime.now();
    final recordTimestamp = timestamp ?? now.toIso8601String();
    final recordData = {
      'user_id': targetUid,
      'record_type': recordType,
      'location': location ?? 'App',
      'notes': notes,
      'timestamp': recordTimestamp,
      'latitude': latitude,
      'longitude': longitude,
      if (userId != null && userId != currentUserId) 'created_by_admin': true,
    };

    try {
      if (currentUser == null) {
        throw Exception('Sem sessao online.');
      }
      if (!await _hasNetworkConnection()) {
        throw Exception('Sem conexao de rede.');
      }

      final docRef = await _db.collection('time_records').add({
        ...recordData,
        'created_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      return {'id': docRef.id, ...recordData};
    } catch (e) {
      if (userId != null && userId != currentUserId) rethrow;

      final offlineRecord = {
        'id': 'offline_${now.microsecondsSinceEpoch}',
        ...recordData,
        'offline': true,
        'sync_status': 'pending',
        'created_at_local': now.toIso8601String(),
      };
      await _saveOfflineRecord(offlineRecord);
      debugPrint(
          'Ponto salvo offline para sincronizar depois: ${offlineRecord['id']}');
      return offlineRecord;
    }
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _createTimeRecordLegacy({
    required String recordType,
    String? location,
    String? notes,
    String? timestamp,
    String? userId,
    double? latitude,
    double? longitude,
  }) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Usuário não autenticado');

    final targetUid = userId ?? currentUser.uid;

    final now = DateTime.now();
    final recordTimestamp = timestamp ?? now.toIso8601String();
    final recordData = {
      'user_id': targetUid,
      'record_type': recordType,
      'location': location ?? 'App',
      'notes': notes,
      'timestamp': recordTimestamp,
      'latitude': latitude,
      'longitude': longitude,
      if (userId != null && userId != currentUser.uid) 'created_by_admin': true,
    };

    try {
      DocumentReference docRef = await _db.collection('time_records').add({
        ...recordData,
        'created_at': FieldValue.serverTimestamp(),
      });
      return {'id': docRef.id, ...recordData};
    } catch (e) {
      if (userId != null && userId != currentUser.uid) {
        rethrow;
      }

      final offlineRecord = {
        'id': 'offline_${now.microsecondsSinceEpoch}',
        ...recordData,
        'offline': true,
        'sync_status': 'pending',
        'created_at_local': now.toIso8601String(),
      };
      await _saveOfflineRecord(offlineRecord);
      debugPrint(
          'Ponto salvo offline para sincronizar depois: ${offlineRecord['id']}');
      return offlineRecord;
    }
  }

  Future<List<dynamic>> getTimeRecords(
      {String? startDate, String? endDate, String? userId}) async {
    final cachedUser = await getCachedCurrentUser();
    final currentUserId =
        _auth.currentUser?.uid ?? cachedUser?['id']?.toString();
    final targetUid = userId ?? currentUserId;
    var records = <Map<String, dynamic>>[];

    try {
      final snapshot = await _db
          .collection('time_records')
          .where('user_id', isEqualTo: targetUid)
          .get()
          .timeout(const Duration(seconds: 10));
      records =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('Pontos online indisponiveis, usando registros offline: $e');
    }

    if (targetUid == currentUserId) {
      final offlineRecords = await getOfflineRecords();
      records.addAll(
          offlineRecords.where((record) => record['user_id'] == targetUid));
    }

    records.sort((a, b) =>
        (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    if (startDate != null || endDate != null) {
      records = records.where((record) {
        final timestamp = record['timestamp'] as String;
        var matches = true;
        if (startDate != null) {
          matches = matches && timestamp.compareTo(startDate) >= 0;
        }
        if (endDate != null) {
          matches = matches && timestamp.compareTo(endDate) <= 0;
        }
        return matches;
      }).toList();
    }

    return records;
  }

  // ignore: unused_element
  Future<List<dynamic>> _getTimeRecordsLegacy(
      {String? startDate, String? endDate, String? userId}) async {
    String? targetUid = userId ?? _auth.currentUser?.uid;
    var records = <Map<String, dynamic>>[];

    try {
      QuerySnapshot snapshot = await _db
          .collection('time_records')
          .where('user_id', isEqualTo: targetUid)
          .get();
      records = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
    } catch (e) {
      debugPrint(
          'Erro ao buscar pontos online, usando fila offline se houver: $e');
    }

    if (targetUid == _auth.currentUser?.uid) {
      final offlineRecords = await getOfflineRecords();
      records.addAll(
          offlineRecords.where((record) => record['user_id'] == targetUid));
    }

    records.sort((a, b) =>
        (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    if (startDate != null || endDate != null) {
      records = records.where((r) {
        final ts = r['timestamp'] as String;
        bool match = true;
        if (startDate != null) match = match && ts.compareTo(startDate) >= 0;
        if (endDate != null) match = match && ts.compareTo(endDate) <= 0;
        return match;
      }).toList();
    }
    return records;
  }

  Future<List<dynamic>> getWorkSummary(
      {required String startDate, required String endDate}) async {
    final user = await getCurrentUser();
    final exportData = await exportTimesheet(
        startDate: startDate, endDate: endDate, userId: user['id']);
    return exportData['daily_records'];
  }

  Future<Map<String, dynamic>> exportTimesheet(
      {required String startDate,
      required String endDate,
      dynamic userId}) async {
    Map<String, dynamic> user;
    if (userId != null) {
      DocumentSnapshot doc =
          await _db.collection('users').doc(userId.toString()).get();
      user = {'id': userId.toString(), ...doc.data() as Map<String, dynamic>};
    } else {
      user = await getCurrentUser();
    }

    final records = await getTimeRecords(
        startDate: startDate, endDate: endDate, userId: user['id']);
    Map<String, List<dynamic>> grouped = {};
    for (var r in records) {
      final d = (r['timestamp'] as String).substring(0, 10);
      grouped.putIfAbsent(d, () => []).add(r);
    }

    List<Map<String, dynamic>> dailyRecords = [];
    double totalN = 0, totalE = 0, total50 = 0, total100 = 0;

    grouped.forEach((date, dayRecords) {
      dayRecords.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));

      double dNormal = 0, dExtras = 0, d50 = 0, d100 = 0;
      String? checkIn, checkOut;
      DateTime? lastIn;

      for (var r in dayRecords) {
        DateTime ts = _roundTime(DateTime.parse(r['timestamp']));
        String type = r['record_type'];

        if (type == 'check_in' || type == 'break_end') {
          if (type == 'check_in') checkIn = DateFormat('HH:mm').format(ts);
          lastIn = ts;
        } else if (type == 'check_out' || type == 'break_start') {
          if (type == 'check_out') checkOut = DateFormat('HH:mm').format(ts);
          if (lastIn != null) {
            var classification =
                _classifyHours(lastIn, ts, user['role'] ?? 'employee');
            dNormal += classification['normal']!;
            dExtras += classification['extras']!;
            d50 += classification['extra50']!;
            d100 += classification['extra100']!;
            lastIn = null;
          }
        }
      }

      totalN += dNormal;
      totalE += dExtras;
      total50 += d50;
      total100 += d100;
      dailyRecords.add({
        'date': date,
        'check_in': checkIn,
        'check_out': checkOut,
        'total_hours': dNormal + dExtras + d50 + d100,
        'regular_hours': dNormal,
        'overtime_hours': dExtras + d50 + d100,
        'extra_50': d50,
        'extra_100': d100,
      });
    });

    dailyRecords
        .sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    return {
      'employee': user,
      'summary': {
        'total_hours':
            (totalN + totalE + total50 + total100).toStringAsFixed(1),
        'total_regular_hours': totalN.toStringAsFixed(1),
        'total_extras': totalE.toStringAsFixed(1),
        'total_50': total50.toStringAsFixed(1),
        'total_100': total100.toStringAsFixed(1),
      },
      'daily_records': dailyRecords,
    };
  }

  // --- MÉTODOS DE ADMIN ---

  Future<List<dynamic>> getUsers() async {
    QuerySnapshot snapshot = await _db.collection('users').get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList();
  }

  Future<Map<String, dynamic>> updateUserAdmin(
    dynamic userId, {
    required String name,
    required String email,
    required String role,
    required String jobTitle,
    required double dailyHours,
    required String cpf,
  }) async {
    await _db.collection('users').doc(userId.toString()).update({
      'name': name,
      'email': email,
      'role': role,
      'job_title': jobTitle,
      'daily_hours': dailyHours,
      'cpf': cpf,
    });
    return {'status': 'success'};
  }

  Future<void> deleteUserAdmin(dynamic userId) async {
    final targetId = userId.toString();
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw Exception('Usuario nao autenticado.');
    }

    if (currentUser.uid == targetId) {
      throw Exception('Voce nao pode excluir a propria conta.');
    }

    final token = await currentUser.getIdToken();
    final response = await http.delete(
      Uri.parse('$backendUrl/admin/users/$targetId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        detail = decoded['detail']?.toString() ?? response.body;
      } catch (_) {}
      throw Exception('Falha ao excluir usuario: $detail');
    }
  }

  Future<List<dynamic>> getAdminTimeRecords({
    dynamic userId,
    String? startDate,
    String? endDate,
  }) async {
    Query query = _db.collection('time_records');
    if (userId != null && userId.toString().isNotEmpty) {
      query = query.where('user_id', isEqualTo: userId.toString());
    }
    QuerySnapshot snapshot = await query.get();
    var records = snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList();
    records.sort((a, b) =>
        (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    if (startDate != null || endDate != null) {
      records = records.where((r) {
        final ts = r['timestamp'] as String;
        bool match = true;
        if (startDate != null) match = match && ts.compareTo(startDate) >= 0;
        if (endDate != null) match = match && ts.compareTo(endDate) <= 0;
        return match;
      }).toList();
    }
    return records;
  }

  Future<void> updateTimeRecordAdmin({
    required String recordId,
    required String newTimestamp,
    required String reason,
    String? notes,
  }) async {
    final admin = await getCurrentUser();
    if (admin['role'] != 'admin') {
      throw Exception('Apenas admin pode editar registros de ponto.');
    }
    final recordRef = _db.collection('time_records').doc(recordId);
    final auditRef = _db.collection('time_record_audits').doc();

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(recordRef);
      if (!snapshot.exists) {
        throw Exception('Registro de ponto nao encontrado.');
      }

      final oldData = snapshot.data() as Map<String, dynamic>;
      final oldTimestamp = oldData['timestamp']?.toString();
      final oldNotes = oldData['notes']?.toString();

      transaction.update(recordRef, {
        'timestamp': newTimestamp,
        'notes': notes ?? '',
        'updated_at': FieldValue.serverTimestamp(),
        'edited_by_admin': true,
        'admin_edit_message': 'Editado pelo admin',
        'last_admin_edit_reason': reason,
        'last_admin_edit_by_id': admin['id'],
        'last_admin_edit_by_name': admin['name'] ?? admin['email'] ?? 'Admin',
        'last_admin_edit_at': FieldValue.serverTimestamp(),
      });

      transaction.set(auditRef, {
        'record_id': recordId,
        'record_user_id': oldData['user_id'],
        'record_type': oldData['record_type'],
        'old_timestamp': oldTimestamp,
        'new_timestamp': newTimestamp,
        'old_notes': oldNotes,
        'new_notes': notes ?? '',
        'reason': reason,
        'admin_id': admin['id'],
        'admin_name': admin['name'] ?? '',
        'admin_email': admin['email'] ?? '',
        'edited_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      });
    });
  }
}
