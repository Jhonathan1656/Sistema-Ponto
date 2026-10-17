import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_app/utils/batch_entry.dart';
import 'package:ponto_app/utils/shift_records.dart';
import 'package:ponto_app/utils/timesheet.dart';

BatchTime _t(int hour, [int minute = 0]) => (hour: hour, minute: minute);

Map<String, DateTime> _byType(List<BatchPunch> punches) =>
    {for (final punch in punches) punch.recordType: punch.at};

void main() {
  final date = DateTime(2026, 10, 15, 14, 37); // hora da tela, ignorada

  group('planBatchPunches', () {
    test('noite: saida e pausas antes da entrada vao para o dia seguinte', () {
      final punches = planBatchPunches(date, {
        'check_in': _t(19, 30),
        'break_start': _t(2),
        'break_end': _t(3),
        'entry_3': _t(23),
        'exit_3': _t(23, 30),
        'check_out': _t(7),
      });
      expect(punches.map((p) => p.recordType), [
        'check_in',
        'break_start',
        'break_end',
        'entry_3',
        'exit_3',
        'check_out',
      ]);
      expect(_byType(punches), {
        'check_in': DateTime(2026, 10, 15, 19, 30),
        'break_start': DateTime(2026, 10, 16, 2),
        'break_end': DateTime(2026, 10, 16, 3),
        'entry_3': DateTime(2026, 10, 15, 23),
        'exit_3': DateTime(2026, 10, 15, 23, 30),
        'check_out': DateTime(2026, 10, 16, 7),
      });
      expect(punches.where((p) => p.nextDay).map((p) => p.recordType),
          ['break_start', 'break_end', 'check_out']);
      expect(batchShiftSpan(punches), const Duration(hours: 11, minutes: 30));
      expect(batchTooLong(punches), isFalse);
    });

    test('dia comum fica todo na data escolhida', () {
      final punches = planBatchPunches(date, {
        'check_in': _t(8),
        'break_start': _t(12),
        'break_end': _t(13),
        'check_out': _t(17),
      });
      expect(punches.every((p) => !p.nextDay), isTrue);
      expect(_byType(punches)['check_out'], DateTime(2026, 10, 15, 17));
      expect(batchShiftSpan(punches), const Duration(hours: 9));
    });

    test('so a saida fica na data escolhida', () {
      // So a saida, para corrigir o "Esqueci" da noite anterior.
      final exitOnly = planBatchPunches(date, {'check_out': _t(7)});
      expect(_byType(exitOnly), {'check_out': DateTime(2026, 10, 15, 7)});
      expect(exitOnly.single.nextDay, isFalse);
      expect(batchShiftSpan(exitOnly), Duration.zero);
      expect(batchTooLong(exitOnly), isFalse);
    });

    test('sem entrada a referencia e o primeiro horario do formulario', () {
      // Jantar 23:00-01:00 de uma noite do app, sem a entrada: o fim da
      // pausa, a Pausa 2 da madrugada e a saida vao para 16/10.
      final punches = planBatchPunches(date, {
        'break_start': _t(23),
        'break_end': _t(1),
        'entry_3': _t(3),
        'exit_3': _t(3, 30),
        'check_out': _t(7),
      });
      expect(_byType(punches), {
        'break_start': DateTime(2026, 10, 15, 23),
        'break_end': DateTime(2026, 10, 16, 1),
        'entry_3': DateTime(2026, 10, 16, 3),
        'exit_3': DateTime(2026, 10, 16, 3, 30),
        'check_out': DateTime(2026, 10, 16, 7),
      });
      expect(punches.where((p) => p.nextDay).map((p) => p.recordType),
          ['break_end', 'entry_3', 'exit_3', 'check_out']);
      expect(batchShiftSpan(punches), const Duration(hours: 8));

      // Pausa que nao passa da meia-noite fica toda na data.
      final morning = planBatchPunches(date, {
        'break_start': _t(2),
        'break_end': _t(3),
        'check_out': _t(7),
      });
      expect(morning.every((p) => !p.nextDay), isTrue);

      // Saida antes do inicio da pausa vai para o dia seguinte: 23h, erro.
      final typo = planBatchPunches(date, {
        'break_start': _t(2),
        'check_out': _t(1),
      });
      expect(_byType(typo)['check_out'], DateTime(2026, 10, 16, 1));
      expect(batchShiftSpan(typo), const Duration(hours: 23));
      expect(batchTooLong(typo), isTrue);
    });

    test('pausa igual a entrada fica no mesmo dia, saida vai para o seguinte',
        () {
      final punches = planBatchPunches(date, {
        'check_in': _t(19, 30),
        'break_start': _t(19, 30),
        'check_out': _t(19, 29),
      });
      expect(_byType(punches)['break_start'], DateTime(2026, 10, 15, 19, 30));
      expect(_byType(punches)['check_out'], DateTime(2026, 10, 16, 19, 29));

      // Saida igual a entrada (24h ou o 08:00 padrao do relogio nos dois):
      // nao e turno de 0h, e o erro das 16h.
      for (final time in [_t(7), _t(8)]) {
        final same =
            planBatchPunches(date, {'check_in': time, 'check_out': time});
        expect(_byType(same)['check_out'],
            DateTime(2026, 10, 16, time.hour, time.minute));
        expect(batchShiftSpan(same), const Duration(hours: 24));
        expect(batchTooLong(same), isTrue);
      }
      // Sem entrada, a saida igual a pausa fica na data: a pausa deixada
      // aberta no app e a saida, as duas 07:00, sao horarios comuns.
      for (final type in ['break_start', 'break_end', 'entry_3', 'exit_3']) {
        final pause = planBatchPunches(
            DateTime(2026, 10, 16), {type: _t(7), 'check_out': _t(7)});
        expect(_byType(pause), {
          type: DateTime(2026, 10, 16, 7),
          'check_out': DateTime(2026, 10, 16, 7),
        });
        expect(pause.every((p) => !p.nextDay), isTrue);
        expect(batchShiftSpan(pause), Duration.zero);
        expect(batchTooLong(pause), isFalse);
      }
    });

    test('virada de mes e de ano', () {
      final month = planBatchPunches(DateTime(2026, 10, 31), {
        'check_in': _t(22),
        'check_out': _t(6),
      });
      expect(_byType(month)['check_out'], DateTime(2026, 11, 1, 6));
      final year = planBatchPunches(DateTime(2026, 12, 31), {
        'check_in': _t(19),
        'check_out': _t(7),
      });
      expect(_byType(year)['check_out'], DateTime(2027, 1, 1, 7));
    });

    test('mais de 16h da entrada ao ultimo horario e erro', () {
      // Entrada 08:00 e saida 07:00: a saida iria para o dia seguinte, 23h.
      final typo = planBatchPunches(date, {
        'check_in': _t(8),
        'check_out': _t(7),
      });
      expect(batchShiftSpan(typo), const Duration(hours: 23));
      expect(batchTooLong(typo), isTrue);

      // A pausa da madrugada tambem conta como o ultimo horario.
      final latePause = planBatchPunches(date, {
        'check_in': _t(14),
        'break_start': _t(6, 1),
        'check_out': _t(5),
      });
      expect(batchTooLong(latePause), isTrue);

      // Exatamente 16h ainda e turno.
      final limit = planBatchPunches(date, {
        'check_in': _t(15),
        'check_out': _t(7),
      });
      expect(batchShiftSpan(limit), maxShiftSpan);
      expect(batchTooLong(limit), isFalse);
    });
  });

  group('lote novo gravado', () {
    // Como o _saveBatch grava: created_by_admin (outro usuario) e
    // batchRecordFields.
    List<Map<String, dynamic>> saved(List<BatchPunch> punches) => [
          for (final (i, punch) in punches.indexed)
            {
              'id': 'b$i',
              'record_type': punch.recordType,
              'timestamp': punch.at.toIso8601String(),
              'created_by_admin': true,
              ...batchRecordFields,
            },
        ];

    test('pontos do lote novo nao sao do lote antigo', () {
      final records = saved(planBatchPunches(date, {'check_in': _t(8)}));
      expect(records.single['batch_real_dates'], isTrue);
      expect(isLegacyBatchRecord(records.single), isFalse);
    });

    test('noite lancada no lote fecha e paga 10,5h no dia da entrada', () {
      final records = saved(planBatchPunches(date, {
        'check_in': _t(19, 30),
        'break_start': _t(2),
        'break_end': _t(3),
        'check_out': _t(7),
      }));
      expect(openShiftCheckIn(records), isNull);
      final grouped = groupRecordsByWorkDay(records);
      expect(grouped.keys, ['2026-10-15']);
      final day =
          computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
      expect(day['total_hours'], closeTo(10.5, 1e-9));
      expect(day['regular_hours'], closeTo(4.5, 1e-9));
      expect(day['extra_100'], closeTo(6, 1e-9));
    });

    test('so a pausa 23:00-01:00 de uma noite do app = 9,5h', () {
      final records = [
        {
          'id': 'in',
          'record_type': 'check_in',
          'timestamp': '2026-10-15T19:30:00.000',
        },
        ...saved(planBatchPunches(date, {
          'break_start': _t(23),
          'break_end': _t(1),
        })),
        {
          'id': 'out',
          'record_type': 'check_out',
          'timestamp': '2026-10-16T07:00:00.000',
        },
      ];
      final grouped = groupRecordsByWorkDay(records);
      expect(grouped.keys, ['2026-10-15']);
      final day =
          computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
      expect(day['total_hours'], closeTo(9.5, 1e-9));
      expect(day['regular_hours'], closeTo(4.5, 1e-9));
      expect(day['extra_100'], closeTo(5, 1e-9));
    });

    test('saida do lote no dia seguinte corrige a noite fechada errado', () {
      // Noite do app fechada por engano as 03:00 (ou 23:00); o gestor lanca
      // so a saida 07:00, na data real 16/10.
      for (final (wrongExit, wrong) in [
        ('2026-10-16T03:00:00.000', 6.5),
        ('2026-10-15T23:00:00.000', 2.5),
      ]) {
        final app = [
          {
            'id': 'in',
            'record_type': 'check_in',
            'timestamp': '2026-10-15T19:30:00.000',
          },
          {'id': 'wrong', 'record_type': 'check_out', 'timestamp': wrongExit},
        ];
        final before = groupRecordsByWorkDay(app);
        expect(
            computeWorkDay('2026-10-15', before['2026-10-15']!, 'employee')[
                'total_hours'],
            closeTo(wrong, 1e-9));

        final fix = saved(
            planBatchPunches(DateTime(2026, 10, 16), {'check_out': _t(7)}));
        final grouped = groupRecordsByWorkDay([...app, ...fix]);
        expect(grouped.keys, ['2026-10-15']);
        final day =
            computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
        // Colunas 19:30-20:00 e 21:00-07:00 (jantar automatico).
        expect(day['break_end'], '07:00');
        expect(day['total_hours'], closeTo(10.5, 1e-9));
        expect(day['regular_hours'], closeTo(3.5, 1e-9));
        expect(day['extra_100'], closeTo(7, 1e-9));
        expect(openShiftCheckIn([...app, ...fix]), isNull);
      }
    });

    test('pausas do lote que corrige a noite fechada errado contam nela', () {
      // A pessoa bateu Saida em vez de Pausa; o gestor lanca a pausa e a
      // saida 07:00. A pausa que cai no dia seguinte a entrada vai com a
      // saida para a noite: paga como se tivesse batido certo no app.
      Map<String, dynamic> app(String id, String type, String timestamp) =>
          {'id': id, 'record_type': type, 'timestamp': timestamp};
      for (final (name, punches, batchDate, batch, total, normal, extra100,
              columns) in [
        (
          'entrada 21:30, saida 03:00, lote 16/10 pausa 03:30-04:30',
          [
            app('in', 'check_in', '2026-10-15T21:30:12.000'),
            app('wrong', 'check_out', '2026-10-16T03:00:27.000'),
          ],
          DateTime(2026, 10, 16),
          {
            'break_start': _t(3, 30),
            'break_end': _t(4, 30),
            'check_out': _t(7),
          },
          8.5,
          2.5,
          6.0,
          ['21:30', '03:30', '04:30', '07:00'],
        ),
        (
          'entrada 19:30, saida 03:00, lote 16/10 pausa 03:00-04:00',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('wrong', 'check_out', '2026-10-16T03:00:27.000'),
          ],
          DateTime(2026, 10, 16),
          {'break_start': _t(3), 'break_end': _t(4), 'check_out': _t(7)},
          10.5,
          4.5,
          6.0,
          ['19:30', '03:00', '04:00', '07:00'],
        ),
        (
          'entrada 19:30, saida 03:00, lote 16/10 pausa 03:30-05:30',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('wrong', 'check_out', '2026-10-16T03:00:27.000'),
          ],
          DateTime(2026, 10, 16),
          {
            'break_start': _t(3, 30),
            'break_end': _t(5, 30),
            'check_out': _t(7),
          },
          9.5,
          4.0,
          5.5,
          ['19:30', '03:30', '05:30', '07:00'],
        ),
        (
          'entrada 19:30, saida 23:00, lote 15/10 pausa 23:00-00:30',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('wrong', 'check_out', '2026-10-15T23:00:20.000'),
          ],
          DateTime(2026, 10, 15),
          {'break_start': _t(23), 'break_end': _t(0, 30), 'check_out': _t(7)},
          10.0,
          4.5,
          5.5,
          ['19:30', '23:00', '00:30', '07:00'],
        ),
        (
          'entrada 19:30, saida 23:00, lote 15/10 pausa 23:00-01:00',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('wrong', 'check_out', '2026-10-15T23:00:20.000'),
          ],
          DateTime(2026, 10, 15),
          {'break_start': _t(23), 'break_end': _t(1), 'check_out': _t(7)},
          9.5,
          4.5,
          5.0,
          ['19:30', '23:00', '01:00', '07:00'],
        ),
        (
          'pausa 23:00-00:00 no app, saida 03:00, lote 16/10 pausa 2',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('p1', 'break_start', '2026-10-15T23:00:05.000'),
            app('p2', 'break_end', '2026-10-16T00:00:09.000'),
            app('wrong', 'check_out', '2026-10-16T03:00:27.000'),
          ],
          DateTime(2026, 10, 16),
          {'entry_3': _t(3), 'exit_3': _t(3, 30), 'check_out': _t(7)},
          10.0,
          4.5,
          5.5,
          null,
        ),
      ]) {
        final records = [
          ...punches,
          ...saved(planBatchPunches(batchDate, batch)),
        ];
        final grouped = groupRecordsByWorkDay(records);
        expect(grouped.keys, ['2026-10-15'], reason: name);
        final day =
            computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
        expect(day['total_hours'], closeTo(total, 1e-9), reason: name);
        expect(day['regular_hours'], closeTo(normal, 1e-9), reason: name);
        expect(day['extra_100'], closeTo(extra100, 1e-9), reason: name);
        if (columns != null) {
          expect(
              [
                day['check_in'],
                day['check_out'],
                day['break_start'],
                day['break_end'],
              ],
              columns,
              reason: name);
        }
        expect(openShiftCheckIn(records), isNull, reason: name);
      }
    });

    test('pausa do lote na Pausa 1 do turno que ja tem a Pausa 1 do app', () {
      // A pessoa bateu a Pausa 1 no app e Saida no lugar da Pausa 2; o
      // gestor lanca a pausa que faltou no primeiro campo, Pausa 1. Ela era
      // ignorada (so a primeira Pausa 1 contava) e paga como trabalhada.
      Map<String, dynamic> app(String id, String type, String timestamp) =>
          {'id': id, 'record_type': type, 'timestamp': timestamp};
      final night = [
        app('in', 'check_in', '2026-10-15T19:30:12.000'),
        app('p1', 'break_start', '2026-10-15T23:00:05.000'),
        app('p2', 'break_end', '2026-10-16T00:00:09.000'),
        app('wrong', 'check_out', '2026-10-16T03:00:27.000'),
        ...saved(planBatchPunches(DateTime(2026, 10, 16), {
          'break_start': _t(3),
          'break_end': _t(3, 30),
          'check_out': _t(7),
        })),
      ];
      final nightDays = groupRecordsByWorkDay(night);
      expect(nightDays.keys, ['2026-10-15']);
      final nightDay =
          computeWorkDay('2026-10-15', nightDays['2026-10-15']!, 'employee');
      expect(
          [
            nightDay['check_in'],
            nightDay['check_out'],
            nightDay['break_start'],
            nightDay['break_end'],
            nightDay['entry_3'],
            nightDay['exit_3'],
          ],
          ['19:30', '23:00', '00:00', '03:00', '03:30', '07:00']);
      expect(nightDay['total_hours'], closeTo(10, 1e-9));
      expect(nightDay['regular_hours'], closeTo(4.5, 1e-9));
      expect(nightDay['extra_100'], closeTo(5.5, 1e-9));

      // Turno do dia: 08:00, Pausa 1 12:00-13:00 no app, Saida 15:00 por
      // engano; lote com Pausa 1 15:00-15:30 e Saida 18:00 = 8,5h.
      final day = [
        app('in', 'check_in', '2026-10-15T08:00:10.000'),
        app('p1', 'break_start', '2026-10-15T12:00:05.000'),
        app('p2', 'break_end', '2026-10-15T13:00:08.000'),
        app('wrong', 'check_out', '2026-10-15T15:00:20.000'),
        ...saved(planBatchPunches(DateTime(2026, 10, 15), {
          'break_start': _t(15),
          'break_end': _t(15, 30),
          'check_out': _t(18),
        })),
      ];
      final dayDays = groupRecordsByWorkDay(day);
      expect(dayDays.keys, ['2026-10-15']);
      final dayRow =
          computeWorkDay('2026-10-15', dayDays['2026-10-15']!, 'employee');
      expect(dayRow['total_hours'], closeTo(8.5, 1e-9));
      expect(dayRow['regular_hours'], closeTo(8.5, 1e-9));

      // Noite fechada certo as 07:00 e uma segunda pausa esquecida,
      // 03:00-04:00, lancada como Pausa 1: 9,5h, nao 10,5h.
      final forgotten = [
        app('in', 'check_in', '2026-10-15T19:30:12.000'),
        app('p1', 'break_start', '2026-10-15T23:00:05.000'),
        app('p2', 'break_end', '2026-10-16T00:00:09.000'),
        app('out', 'check_out', '2026-10-16T07:00:15.000'),
        ...saved(planBatchPunches(DateTime(2026, 10, 16), {
          'break_start': _t(3),
          'break_end': _t(4),
        })),
      ];
      final forgottenDays = groupRecordsByWorkDay(forgotten);
      expect(forgottenDays.keys, ['2026-10-15']);
      final forgottenDay = computeWorkDay(
          '2026-10-15', forgottenDays['2026-10-15']!, 'employee');
      expect(forgottenDay['total_hours'], closeTo(9.5, 1e-9));
      expect(forgottenDay['extra_100'], closeTo(5, 1e-9));
    });

    test('fim da pausa igual a saida no lote: a mesma folha em qualquer ordem',
        () {
      // Os dois pontos saem com o mesmo timestamp (16/10 07:00:00.000); a
      // ordem deles vinha do id aleatorio do Firestore: 6,5h ou 10,5h.
      Map<String, dynamic> app(String id, String type, String timestamp) =>
          {'id': id, 'record_type': type, 'timestamp': timestamp};
      for (final (name, records) in [
        (
          'pausa aberta no app, lote com Pausa 1 fim e Saida 07:00',
          [
            app('in', 'check_in', '2026-10-15T19:30:12.000'),
            app('p1', 'break_start', '2026-10-16T03:00:05.000'),
            {
              ...app('autoclose_p1', 'break_end', '2026-10-16T04:00:05.000'),
              'auto_closed': true,
            },
            ...saved(planBatchPunches(DateTime(2026, 10, 16), {
              'break_end': _t(7),
              'check_out': _t(7),
            })),
          ],
        ),
        (
          'lote com Entrada 19:30, Pausa 2 03:00-07:00 e Saida 07:00',
          saved(planBatchPunches(date, {
            'check_in': _t(19, 30),
            'entry_3': _t(3),
            'exit_3': _t(7),
            'check_out': _t(7),
          })),
        ),
      ]) {
        for (final order in [records, records.reversed.toList()]) {
          final grouped = groupRecordsByWorkDay(order);
          expect(grouped.keys, ['2026-10-15'], reason: name);
          final day =
              computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
          expect(day['total_hours'], closeTo(6.5, 1e-9), reason: name);
          expect(day['regular_hours'], closeTo(1.5, 1e-9), reason: name);
          expect(day['extra_100'], closeTo(5, 1e-9), reason: name);
          expect(openShiftCheckIn(order), isNull, reason: name);
        }
      }
    });

    test('pausa do lote com a saida reservada da noite do lote antigo no meio',
        () {
      // Transicao: 16/10 ainda tem a noite do lote antigo (saida 07:00
      // reservada, entrada 19:30). A pausa 03:30-04:30 do lote novo vai com
      // a saida 07:30 que corrige 15/10: 9h, nao 10h.
      final records = [
        {
          'id': 'in',
          'record_type': 'check_in',
          'timestamp': '2026-10-15T21:30:12.000',
        },
        {
          'id': 'wrong',
          'record_type': 'check_out',
          'timestamp': '2026-10-16T03:00:27.000',
        },
        {
          'id': 'lout',
          'record_type': 'check_out',
          'timestamp': '2026-10-16T07:00:00.000',
          'created_by_admin': true,
        },
        {
          'id': 'lin',
          'record_type': 'check_in',
          'timestamp': '2026-10-16T19:30:00.000',
          'created_by_admin': true,
        },
        ...saved(planBatchPunches(DateTime(2026, 10, 16), {
          'break_start': _t(3, 30),
          'break_end': _t(4, 30),
          'check_out': _t(7, 30),
        })),
      ];
      final grouped = groupRecordsByWorkDay(records);
      final first =
          computeWorkDay('2026-10-15', grouped['2026-10-15']!, 'employee');
      expect([first['check_in'], first['check_out'], first['break_start']],
          ['21:30', '03:30', '04:30']);
      expect(first['total_hours'], closeTo(9, 1e-9));
      expect(first['regular_hours'], closeTo(3, 1e-9));
      expect(first['extra_100'], closeTo(6, 1e-9));
      final legacy =
          computeWorkDay('2026-10-16', grouped['2026-10-16']!, 'employee');
      expect(legacy['total_hours'], closeTo(10.5, 1e-9));
      expect(openShiftCheckIn(records), isNull);
    });
  });
}
