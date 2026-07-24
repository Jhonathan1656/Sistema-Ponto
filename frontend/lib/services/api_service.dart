import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import '../utils/chat_timestamp.dart';
import '../utils/work_schedule_rules.dart';

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

  Future<Map<String, String>> _authorizedHeaders() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado.');
    final token = await user.getIdToken();
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

  Future<List<Map<String, dynamic>>> getSignatureDocuments(
      {required bool admin}) async {
    final response = await http
        .get(
          Uri.parse(admin
              ? '$backendUrl/admin/signature-documents'
              : '$backendUrl/signature-documents'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 30));
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
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$backendUrl/admin/signature-documents'),
    );
    request.headers.addAll(await _authorizedHeaders());
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

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> _updateUserAdminInFirestore(
    String userId, {
    required String name,
    required String email,
    required String role,
    required String jobTitle,
    required double dailyHours,
    required String cpf,
    required bool disabled,
    String? newPassword,
    required bool workScheduleOverrideEnabled,
    Map<String, dynamic>? workScheduleOverride,
  }) async {
    final admin = await getCurrentUser();
    if (admin['role'] != 'admin') {
      throw Exception('Apenas administradores podem editar usuarios.');
    }

    final userRef = _db.collection('users').doc(userId);
    final snapshot = await userRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw Exception('Usuario nao encontrado.');
    }
    final current = snapshot.data()!;
    final currentEmail =
        (current['email'] ?? '').toString().trim().toLowerCase();
    final requestedEmail = email.trim().toLowerCase();
    if (requestedEmail != currentEmail) {
      throw Exception(
          'Para alterar o e-mail de login, configure a credencial Firebase Admin no servidor.');
    }
    if ((newPassword ?? '').trim().isNotEmpty) {
      throw Exception(
          'Para redefinir a senha, configure a credencial Firebase Admin no servidor.');
    }
    if (disabled != (current['disabled'] == true)) {
      throw Exception(
          'Para ativar ou desativar a conta, configure a credencial Firebase Admin no servidor.');
    }

    final updateData = <String, dynamic>{
      'name': name.trim(),
      'email': currentEmail,
      'role': role,
      'job_title': jobTitle.trim(),
      'daily_hours': dailyHours,
      'cpf': cpf.trim(),
      'disabled': disabled,
      'work_schedule_override_enabled': workScheduleOverrideEnabled,
      'work_schedule_override':
          workScheduleOverrideEnabled ? workScheduleOverride : null,
      'updated_at': FieldValue.serverTimestamp(),
      'last_admin_update_by_id': admin['id'],
      'last_admin_update_by_name': admin['name'] ?? '',
      'last_admin_update_by_email': admin['email'] ?? '',
      'compatibility_mode': true,
    };
    final auditRef = _db.collection('system_audits').doc();
    final batch = _db.batch();
    batch.update(userRef, updateData);
    batch.set(auditRef, {
      'action': 'update_user_admin_compatibility',
      'target_user_id': userId,
      'admin_id': admin['id'],
      'admin_name': admin['name'] ?? '',
      'admin_email': admin['email'] ?? '',
      'updated_fields': [
        'name',
        'role',
        'job_title',
        'daily_hours',
        'cpf',
        'work_schedule_override_enabled',
        'work_schedule_override',
      ],
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return {'status': 'success', 'id': userId, 'compatibility_mode': true};
  }

  Future<Map<String, dynamic>> refreshSignatureDocument(
      String documentId) async {
    final response = await http
        .post(
          Uri.parse('$backendUrl/signature-documents/$documentId/refresh'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<void> deleteSignatureDocument(String documentId) async {
    final response = await http
        .delete(
          Uri.parse('$backendUrl/admin/signature-documents/$documentId'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
  }

  Future<List<Map<String, dynamic>>> getSignatureNotifications() async {
    final response = await http
        .get(
          Uri.parse('$backendUrl/signature-notifications'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(response));
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> markSignatureNotificationsRead() async {
    final response = await http
        .post(
          Uri.parse('$backendUrl/signature-notifications/read'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 30));
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
        'disabled',
        'work_schedule_override_enabled',
        'work_schedule_override',
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
        'created_at': FieldValue.serverTimestamp(),
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
    final snap = await _db.collection('adjustment_requests').get();

    final requests =
        snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    requests.sort((a, b) => compareChatMessages(b, a));
    return requests;
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
      requests.sort(compareChatMessages);
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
    final user = _auth.currentUser;
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
    User? user = _auth.currentUser;
    if (user == null) throw Exception('Nenhum usuário logado');
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

  /// Descarta a fila offline local. Escape para registros que nunca
  /// sincronizam (ex.: entrada de estagiario fora da janela) e ficam
  /// reaparecendo a cada leitura.
  Future<void> clearOfflineRecords() async {
    await _replaceOfflineRecords([]);
  }

  Future<int> syncOfflineRecords() async {
    final pendingRecords = await getOfflineRecords();
    if (pendingRecords.isEmpty) return 0;
    final cachedUser = await getCachedCurrentUser();
    final cachedRole = (cachedUser?['role'] ?? '').toString().toLowerCase();
    final isIntern =
        cachedRole.contains('intern') || cachedRole.contains('estag');

    int syncedCount = 0;
    final failedRecords = <Map<String, dynamic>>[];

    for (final record in pendingRecords) {
      try {
        final recordType = record['record_type']?.toString() ?? '';
        if (isIntern &&
            (recordType == 'check_in' || recordType == 'check_out')) {
          final result = await createScheduleControlledPunch(
            recordType: recordType,
            timestamp: record['timestamp']?.toString(),
            location: record['location']?.toString(),
            notes: record['notes']?.toString(),
            latitude: (record['latitude'] as num?)?.toDouble(),
            longitude: (record['longitude'] as num?)?.toDouble(),
          );
          if (result['status'] == 'approval_required') {
            throw Exception('Registro depende de liberacao do gestor.');
          }
          syncedCount++;
          continue;
        }

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

  String _hhmm(DateTime dt) => DateFormat('HH:mm').format(dt);

  // Constroi ate 3 sessoes de trabalho (pares entrada/saida) a partir dos marcos
  // do dia. O modelo da folha tem 3 pares C-D / E-F / G-H, e as REFEICOES sao os
  // intervalos ENTRE as sessoes (por isso ficam descontadas do total).
  //   inicio/fim       -> check_in / check_out (turno)
  //   almI/almF        -> Pausa 1 (almoco)
  //   janI/janF        -> Pausa 2 (jantar)
  // Regras (portadas do Pontocampo.py, ajustadas ao que foi combinado):
  //   - Pausa deixada aberta (bateu inicio, esqueceu o fim) fecha com 1 hora.
  //   - Almoco automatico 12:00-13:00 se nao registrado e o turno cobrir a janela.
  //   - Jantar automatico 20:00-21:00 se nao registrado e o turno cobrir a janela.
  List<List<DateTime>> _buildWorkSessions({
    required DateTime? inicio,
    required DateTime? fim,
    DateTime? almI,
    DateTime? almF,
    DateTime? janI,
    DateTime? janF,
  }) {
    if (inicio == null || fim == null) return [];
    if (fim.isBefore(inicio)) fim = fim.add(const Duration(days: 1));

    // Fecha refeicao deixada aberta com 1 hora.
    if (almI != null && almF == null) almF = almI.add(const Duration(hours: 1));
    if (janI != null && janF == null) janF = janI.add(const Duration(hours: 1));

    final base = DateTime(inicio.year, inicio.month, inicio.day);

    // Almoco automatico 12:00-13:00.
    if (almI == null && almF == null) {
      final ai = base.add(const Duration(hours: 12));
      final af = base.add(const Duration(hours: 13));
      if (!inicio.isAfter(ai) && !fim.isBefore(af)) {
        almI = ai;
        almF = af;
      }
    }
    // Jantar automatico 20:00-21:00.
    if (janI == null && janF == null) {
      final ji = base.add(const Duration(hours: 20));
      final jf = base.add(const Duration(hours: 21));
      if (!inicio.isAfter(ji) && !fim.isBefore(jf)) {
        janI = ji;
        janF = jf;
      }
    }

    final marks = <DateTime>[inicio, fim];
    for (final m in [almI, almF, janI, janF]) {
      if (m != null) marks.add(m);
    }
    marks.sort((a, b) => a.compareTo(b));

    final sessions = <List<DateTime>>[];
    for (int i = 0; i + 1 < marks.length; i += 2) {
      final s = marks[i];
      final e = marks[i + 1];
      if (e.isAfter(s)) sessions.add([s, e]);
    }
    // O modelo suporta no maximo 3 sessoes (3 pares de colunas).
    return sessions.length > 3 ? sessions.sublist(0, 3) : sessions;
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

      // Marcos do dia. Pausa 1 (break_*) = almoco; Pausa 2 (entry_3/exit_3) = jantar.
      DateTime? inicio, fim, almI, almF, janI, janF;
      for (final r in dayRecords) {
        final ts = _roundTime(DateTime.parse(r['timestamp'] as String).toLocal());
        switch (r['record_type']) {
          case 'check_in':
            inicio ??= ts;
            break;
          case 'check_out':
            fim = ts; // ultimo check_out do dia
            break;
          case 'break_start':
            almI ??= ts;
            break;
          case 'break_end':
            almF ??= ts;
            break;
          case 'entry_3':
            janI ??= ts;
            break;
          case 'exit_3':
            janF ??= ts;
            break;
        }
      }

      final sessions = _buildWorkSessions(
        inicio: inicio,
        fim: fim,
        almI: almI,
        almF: almF,
        janI: janI,
        janF: janF,
      );

      double dNormal = 0, dExtras = 0, d50 = 0, d100 = 0;
      for (final s in sessions) {
        final c = _classifyHours(s[0], s[1], user['role'] ?? 'employee');
        dNormal += c['normal']!;
        dExtras += c['extras']!;
        d50 += c['extra50']!;
        d100 += c['extra100']!;
      }

      // Mapeia ate 3 sessoes para os 3 pares de colunas (C-D / E-F / G-H).
      String? colCheckIn, colCheckOut;
      String? colBreakStart, colBreakEnd, colEntry3, colExit3;
      if (sessions.isNotEmpty) {
        colCheckIn = _hhmm(sessions[0][0]);
        colCheckOut = _hhmm(sessions[0][1]);
      } else if (inicio != null) {
        // Turno aberto (sem saida): mostra so a entrada, sem contar horas.
        colCheckIn = _hhmm(inicio);
      }
      if (sessions.length >= 2) {
        colBreakStart = _hhmm(sessions[1][0]);
        colBreakEnd = _hhmm(sessions[1][1]);
      }
      if (sessions.length >= 3) {
        colEntry3 = _hhmm(sessions[2][0]);
        colExit3 = _hhmm(sessions[2][1]);
      }

      totalN += dNormal;
      totalE += dExtras;
      total50 += d50;
      total100 += d100;
      dailyRecords.add({
        'date': date,
        'check_in': colCheckIn,
        'check_out': colCheckOut,
        'break_start': colBreakStart,
        'break_end': colBreakEnd,
        'entry_3': colEntry3,
        'exit_3': colExit3,
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
    bool disabled = false,
    String? newPassword,
    bool workScheduleOverrideEnabled = false,
    Map<String, dynamic>? workScheduleOverride,
  }) async {
    final response = await http
        .put(
          Uri.parse('$backendUrl/admin/users/${userId.toString()}'),
          headers: {
            ...await _authorizedHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': name,
            'email': email,
            'role': role,
            'job_title': jobTitle,
            'daily_hours': dailyHours,
            'cpf': cpf,
            'disabled': disabled,
            'new_password': newPassword,
            'work_schedule_override_enabled': workScheduleOverrideEnabled,
            'work_schedule_override': workScheduleOverride,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _updateUserAdminInFirestore(
          userId.toString(),
          name: name,
          email: email,
          role: role,
          jobTitle: jobTitle,
          dailyHours: dailyHours,
          cpf: cpf,
          disabled: disabled,
          newPassword: newPassword,
          workScheduleOverrideEnabled: workScheduleOverrideEnabled,
          workScheduleOverride: workScheduleOverride,
        );
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<List<Map<String, dynamic>>> getUserNotifications() async {
    final response = await http
        .get(
          Uri.parse('$backendUrl/notifications'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        final user = _auth.currentUser;
        if (user == null) return [];
        final snapshot = await _db
            .collection('user_notifications')
            .where('user_id', isEqualTo: user.uid)
            .get();
        final notifications = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList()
          ..sort((a, b) =>
              _firestoreCreatedAt(b).compareTo(_firestoreCreatedAt(a)));
        return notifications;
      }
      throw Exception(_apiError(response));
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> markUserNotificationsRead() async {
    final response = await http
        .post(
          Uri.parse('$backendUrl/notifications/read'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        final user = _auth.currentUser;
        if (user == null) return;
        final snapshot = await _db
            .collection('user_notifications')
            .where('user_id', isEqualTo: user.uid)
            .get();
        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          if (doc.data()['is_read'] != true) {
            batch.update(doc.reference, {
              'is_read': true,
              'read_at': FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commit();
        return;
      }
      throw Exception(_apiError(response));
    }
  }

  Future<Map<String, dynamic>> getEffectiveWorkSchedule() async {
    final response = await http
        .get(
          Uri.parse('$backendUrl/work-schedule/effective'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _getEffectiveWorkScheduleFromFirestore();
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> createScheduleControlledPunch({
    required String recordType,
    String? timestamp,
    String? location,
    String? notes,
    double? latitude,
    double? longitude,
    bool closeAtScheduledEnd = false,
  }) async {
    final response = await http
        .post(
          Uri.parse('$backendUrl/work-schedule/punch'),
          headers: {
            ...await _authorizedHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'record_type': recordType,
            'timestamp': timestamp,
            'location': location,
            'notes': notes,
            'latitude': latitude,
            'longitude': longitude,
            'close_at_scheduled_end': closeAtScheduledEnd,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _createScheduleControlledPunchInFirestore(
          recordType: recordType,
          timestamp: timestamp,
          location: location,
          notes: notes,
          latitude: latitude,
          longitude: longitude,
          closeAtScheduledEnd: closeAtScheduledEnd,
        );
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> createScheduleApprovalRequest({
    required String requestType,
    required String attemptedAt,
    String? shiftStartAt,
    String? location,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    final observation = notes?.trim() ?? '';
    if (observation.isEmpty) {
      throw Exception('Informe uma observacao explicando a solicitacao.');
    }
    if (observation.length > 500) {
      throw Exception('A observacao deve ter no maximo 500 caracteres.');
    }
    final response = await http
        .post(
          Uri.parse('$backendUrl/work-schedule/approval-requests'),
          headers: {
            ...await _authorizedHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'request_type': requestType,
            'attempted_at': attemptedAt,
            'shift_start_at': shiftStartAt,
            'location': location,
            'notes': observation,
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _createScheduleApprovalRequestInFirestore(
          requestType: requestType,
          attemptedAt: attemptedAt,
          shiftStartAt: shiftStartAt,
          location: location,
          notes: observation,
          latitude: latitude,
          longitude: longitude,
        );
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<List<Map<String, dynamic>>> getScheduleApprovalRequests(
      {String? status}) async {
    final uri = Uri.parse('$backendUrl/admin/work-schedule/approval-requests')
        .replace(queryParameters: status == null ? null : {'status': status});
    final response = await http
        .get(uri, headers: await _authorizedHeaders())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _getScheduleApprovalRequestsFromFirestore(status: status);
      }
      throw Exception(_apiError(response));
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> decideScheduleApproval(
    String requestId, {
    required bool approve,
    String? reason,
  }) async {
    final action = approve ? 'approve' : 'reject';
    final response = await http
        .post(
          Uri.parse(
              '$backendUrl/admin/work-schedule/approval-requests/$requestId/$action'),
          headers: {
            ...await _authorizedHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        await _decideScheduleApprovalInFirestore(
          requestId,
          approve: approve,
          reason: reason,
        );
        return;
      }
      throw Exception(_apiError(response));
    }
  }

  Future<Map<String, dynamic>> getGlobalWorkSchedule() async {
    final response = await http
        .get(
          Uri.parse('$backendUrl/admin/work-schedule/settings'),
          headers: await _authorizedHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        return _getGlobalWorkScheduleFromFirestore();
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> updateGlobalWorkSchedule(
      Map<String, dynamic> schedule) async {
    final response = await http
        .put(
          Uri.parse('$backendUrl/admin/work-schedule/settings'),
          headers: {
            ...await _authorizedHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(schedule),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404 || response.statusCode >= 500) {
        await _db
            .collection('work_schedule_settings')
            .doc('intern_default')
            .set({
          ...schedule,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by_id': _auth.currentUser?.uid,
        });
        return schedule;
      }
      throw Exception(_apiError(response));
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  static const Map<String, dynamic> _defaultInternSchedule = {
    'shift_start': '13:30',
    'shift_end': '19:30',
    'start_allowed_from': '13:25',
    'start_allowed_until': '19:25',
    'overtime_prompt_after': '19:35',
    'timezone': 'America/Sao_Paulo',
  };

  DateTime _scheduleTime(DateTime day, dynamic value) {
    final parts = value.toString().split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.tryParse(parts.first) ?? 0,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  DateTime _firestoreCreatedAt(Map<String, dynamic> item) {
    final value = item['created_at'];
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Map<String, dynamic>> _getGlobalWorkScheduleFromFirestore() async {
    try {
      final snapshot = await _db
          .collection('work_schedule_settings')
          .doc('intern_default')
          .get();
      if (snapshot.exists && snapshot.data() != null) {
        return {..._defaultInternSchedule, ...snapshot.data()!};
      }
    } catch (e) {
      debugPrint('Horario global remoto indisponivel, usando padrao: $e');
    }
    return Map<String, dynamic>.from(_defaultInternSchedule);
  }

  Future<Map<String, dynamic>> _getEffectiveWorkScheduleFromFirestore() async {
    final user = await getCurrentUser();
    final override = user['work_schedule_override'];
    final overrideEnabled =
        user['work_schedule_override_enabled'] == true && override is Map;
    final schedule = overrideEnabled
        ? {..._defaultInternSchedule, ...Map<String, dynamic>.from(override)}
        : await _getGlobalWorkScheduleFromFirestore();

    final now = DateTime.now();
    final dayKey = DateFormat('yyyy-MM-dd').format(now);
    Map<String, dynamic>? overtimeRequest;
    Map<String, dynamic>? startRequest;
    try {
      final snapshot = await _db
          .collection('work_schedule_approval_requests')
          .where('user_id', isEqualTo: user['id'])
          .get();
      final requests = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((item) => item['day_key'] == dayKey)
          .toList()
        ..sort(
            (a, b) => _firestoreCreatedAt(b).compareTo(_firestoreCreatedAt(a)));
      for (final item in requests) {
        if (item['request_type'] == 'overtime' && overtimeRequest == null) {
          overtimeRequest = item;
        }
        if (item['request_type'] == 'start_exception' && startRequest == null) {
          startRequest = item;
        }
      }
    } catch (e) {
      debugPrint('Solicitacoes de horario indisponiveis no Firestore: $e');
    }
    return {
      'schedule': schedule,
      'source': overrideEnabled ? 'user_override' : 'global',
      'server_now': now.toIso8601String(),
      'overtime_request': overtimeRequest,
      'start_request': startRequest,
      'compatibility_mode': true,
    };
  }

  Future<Map<String, dynamic>> _createScheduleControlledPunchInFirestore({
    required String recordType,
    String? timestamp,
    String? location,
    String? notes,
    double? latitude,
    double? longitude,
    bool closeAtScheduledEnd = false,
  }) async {
    final user = await getCurrentUser();
    final state = await _getEffectiveWorkScheduleFromFirestore();
    final schedule = Map<String, dynamic>.from(state['schedule'] as Map);
    var attempted = DateTime.tryParse(timestamp ?? '') ?? DateTime.now();
    final records = (await getTimeRecords(userId: user['id']))
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList()
      ..sort((a, b) =>
          a['timestamp'].toString().compareTo(b['timestamp'].toString()));
    Map<String, dynamic>? openShift;
    for (final record in records) {
      if (record['record_type'] == 'check_in') {
        openShift = record;
      } else if (record['record_type'] == 'check_out') {
        openShift = null;
      }
    }

    if (recordType == 'check_in') {
      if (openShift != null) throw Exception('Ja existe um turno aberto.');
      if (!isInternStartWithinSchedule(attempted, schedule)) {
        return {
          'status': 'approval_required',
          'request_type': 'start_exception',
          'reason': isInternWorkday(attempted)
              ? 'outside_start_window'
              : 'non_working_day',
          'attempted_at': attempted.toIso8601String(),
          'schedule': schedule,
        };
      }
    } else if (recordType == 'check_out') {
      if (openShift == null) throw Exception('Nao existe turno aberto.');
      final shiftStart = DateTime.parse(openShift['timestamp'].toString());
      final scheduledEnd = _scheduleTime(shiftStart, schedule['shift_end']);
      if (closeAtScheduledEnd) {
        if (scheduledEnd.isBefore(shiftStart)) {
          throw Exception(
              'A entrada ocorreu depois do fim programado. Encerre no horario real.');
        }
        attempted = scheduledEnd;
      } else {
        final threshold =
            _scheduleTime(shiftStart, schedule['overtime_prompt_after']);
        final overtime = state['overtime_request'];
        if (!attempted.isBefore(threshold) &&
            (overtime is! Map || overtime['status'] != 'approved')) {
          return {
            'status': 'approval_required',
            'request_type': 'overtime',
            'attempted_at': attempted.toIso8601String(),
            'schedule': schedule,
          };
        }
      }
    }

    final data = {
      'user_id': user['id'],
      'record_type': recordType,
      'location': location ?? 'App',
      'notes': notes,
      'timestamp': attempted.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'schedule_controlled': true,
      'schedule_snapshot': schedule,
      'compatibility_mode': true,
      'created_at': FieldValue.serverTimestamp(),
    };
    final ref = await _db.collection('time_records').add(data);
    return {'status': 'created', 'id': ref.id, ...data};
  }

  Future<Map<String, dynamic>> _createScheduleApprovalRequestInFirestore({
    required String requestType,
    required String attemptedAt,
    String? shiftStartAt,
    String? location,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    final observation = notes?.trim() ?? '';
    if (observation.isEmpty) {
      throw Exception('Informe uma observacao explicando a solicitacao.');
    }
    if (observation.length > 500) {
      throw Exception('A observacao deve ter no maximo 500 caracteres.');
    }
    final user = await getCurrentUser();
    final state = await _getEffectiveWorkScheduleFromFirestore();
    final attempted = DateTime.parse(attemptedAt);
    final dayKey = DateFormat('yyyy-MM-dd').format(attempted);
    final snapshot = await _db
        .collection('work_schedule_approval_requests')
        .where('user_id', isEqualTo: user['id'])
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['request_type'] == requestType &&
          data['day_key'] == dayKey &&
          data['status'] == 'pending') {
        return {
          'status': 'existing',
          'request': {'id': doc.id, ...data}
        };
      }
    }
    final data = {
      'user_id': user['id'],
      'user_name': user['name'] ?? user['email'] ?? user['id'],
      'user_email': user['email'] ?? '',
      'request_type': requestType,
      'status': 'pending',
      'attempted_at': attempted.toIso8601String(),
      'shift_start_at': shiftStartAt,
      'day_key': dayKey,
      'location': location ?? 'App',
      'notes': observation,
      'latitude': latitude,
      'longitude': longitude,
      'schedule_snapshot': state['schedule'],
      'compatibility_mode': true,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    final ref =
        await _db.collection('work_schedule_approval_requests').add(data);
    return {
      'status': 'created',
      'request': {'id': ref.id, ...data}
    };
  }

  Future<List<Map<String, dynamic>>> _getScheduleApprovalRequestsFromFirestore(
      {String? status}) async {
    final snapshot =
        await _db.collection('work_schedule_approval_requests').get();
    final requests = snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .where((item) => status == null || item['status'] == status)
        .toList()
      ..sort(
          (a, b) => _firestoreCreatedAt(b).compareTo(_firestoreCreatedAt(a)));
    return requests;
  }

  Future<void> _decideScheduleApprovalInFirestore(
    String requestId, {
    required bool approve,
    String? reason,
  }) async {
    final manager = await getCurrentUser();
    if (manager['role'] != 'admin' && manager['role'] != 'manager') {
      throw Exception('Apenas gestores podem decidir liberacoes.');
    }
    final requestRef =
        _db.collection('work_schedule_approval_requests').doc(requestId);
    final snapshot = await requestRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw Exception('Solicitacao nao encontrada.');
    }
    final request = snapshot.data()!;
    if (request['status'] != 'pending') {
      throw Exception('Esta solicitacao ja foi decidida.');
    }

    final batch = _db.batch();
    String? linkedRecordId;
    if (approve && request['request_type'] == 'start_exception') {
      final records = (await getTimeRecords(userId: request['user_id']))
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList()
        ..sort((a, b) =>
            a['timestamp'].toString().compareTo(b['timestamp'].toString()));
      bool open = false;
      for (final record in records) {
        if (record['record_type'] == 'check_in') open = true;
        if (record['record_type'] == 'check_out') open = false;
      }
      if (open) throw Exception('O usuario ja possui um turno aberto.');
      final recordRef = _db.collection('time_records').doc();
      linkedRecordId = recordRef.id;
      batch.set(recordRef, {
        'user_id': request['user_id'],
        'record_type': 'check_in',
        'location': request['location'] ?? 'App (aprovado)',
        'notes':
            request['notes'] ?? 'Entrada fora do horario aprovada pelo gestor',
        'timestamp': request['attempted_at'],
        'latitude': request['latitude'],
        'longitude': request['longitude'],
        'schedule_controlled': true,
        'schedule_approval_request_id': requestId,
        'approved_by_id': manager['id'],
        'approved_by_name': manager['name'] ?? manager['email'],
        'schedule_snapshot': request['schedule_snapshot'],
        'compatibility_mode': true,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    batch.update(requestRef, {
      'status': approve ? 'approved' : 'rejected',
      'decision_reason': reason?.trim() ?? '',
      'decided_by_id': manager['id'],
      'decided_by_name': manager['name'] ?? manager['email'] ?? 'Gestor',
      'decided_at': FieldValue.serverTimestamp(),
      'linked_time_record_id': linkedRecordId,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    try {
      await _db.collection('user_notifications').add({
        'user_id': request['user_id'],
        'title': approve ? 'Horario liberado' : 'Horario nao liberado',
        'body': approve
            ? 'Sua solicitacao de horario foi liberada pelo gestor.'
            : 'O gestor nao liberou sua solicitacao de horario.',
        'type': 'schedule_decision',
        'request_id': requestId,
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Decisao salva, mas notificacao interna falhou: $e');
    }
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
