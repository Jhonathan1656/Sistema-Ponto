import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_app/services/api_service.dart';

Map<String, dynamic> _queued(String type, String timestamp,
        {String status = 'pending', bool? awaitingApproval}) =>
    {
      'id': '$type-$timestamp',
      'record_type': type,
      'timestamp': timestamp,
      'sync_status': status,
      if (awaitingApproval != null) 'sync_awaiting_approval': awaitingApproval,
    };

void main() {
  test('pontos da fila esperam pela primeira saida recusada', () {
    final queue = [
      _queued('check_in', '2026-10-20T13:30:00.000'),
      _queued('check_out', '2026-10-19T20:10:00.000', status: 'blocked'),
      _queued('check_out', '2026-10-20T19:20:00.000'),
      // Entrada recusada nao segura a tela: a regra e so para a saida.
      _queued('check_in', '2026-10-18T09:00:00.000', status: 'blocked'),
    ];
    expect(ApiService.firstBlockedCheckOutTimestamp(queue),
        '2026-10-19T20:10:00.000');
    expect(
        ApiService.firstBlockedCheckOutTimestamp(
            [_queued('check_out', '2026-10-19T20:10:00.000')]),
        isNull);
  });

  test('saida recusada so por falta da liberacao espera o gestor', () {
    expect(
        ApiService.isAwaitingApprovalOfflineRecord(_queued(
            'check_out', '2026-10-19T20:10:00.000',
            status: 'blocked', awaitingApproval: true)),
        isTrue);
    expect(
        ApiService.isAwaitingApprovalOfflineRecord(_queued(
            'check_out', '2026-10-19T20:10:00.000',
            status: 'blocked', awaitingApproval: false)),
        isFalse);
    // Pendente ainda nao foi recusada.
    expect(
        ApiService.isAwaitingApprovalOfflineRecord(_queued(
            'check_out', '2026-10-19T20:10:00.000',
            awaitingApproval: true)),
        isFalse);
  });

  group('awaitingApprovalRetryAnswered', () {
    Map<String, dynamic> parked(String refusedAt,
            {bool awaitingApproval = true}) =>
        {
          ..._queued('check_out', '2026-10-15T20:10:00.000',
              status: 'blocked', awaitingApproval: awaitingApproval),
          'sync_refused_at': refusedAt,
        };
    final exit = parked('2026-10-15T20:12:00.000');

    test('reenvio que nao chegou (timeout): tenta de novo', () {
      expect(ApiService.awaitingApprovalRetryAnswered([exit], [exit]),
          isFalse);
      // Parada antes da hora da recusa existir (fila antiga): igual.
      final old = Map<String, dynamic>.from(exit)..remove('sync_refused_at');
      expect(ApiService.awaitingApprovalRetryAnswered([old], [old]), isFalse);
      // Outro ponto enviado antes dela (sincronizacao sem reenvio): igual.
      final entry = _queued('check_in', '2026-10-16T13:30:00.000');
      expect(ApiService.awaitingApprovalRetryAnswered([exit, entry], [exit]),
          isFalse);
    });

    test('saida enviada: pronto', () {
      expect(ApiService.awaitingApprovalRetryAnswered([exit], []), isTrue);
    });

    test('recusada de novo, pela liberacao ou por outro motivo: pronto', () {
      expect(
          ApiService.awaitingApprovalRetryAnswered(
              [exit], [parked('2026-10-15T20:31:00.000')]),
          isTrue);
      expect(
          ApiService.awaitingApprovalRetryAnswered([exit], [
            parked('2026-10-15T20:31:00.000', awaitingApproval: false),
          ]),
          isTrue);
    });

    test('ponto anterior recusado segura a saida: pronto', () {
      final earlier = _queued('check_in', '2026-10-15T13:30:00.000');
      final refused = {
        ...earlier,
        'sync_status': 'blocked',
        'sync_refused_at': '2026-10-15T20:31:00.000',
      };
      expect(
          ApiService.awaitingApprovalRetryAnswered(
              [earlier, exit], [refused, exit]),
          isTrue);
    });
  });
}
