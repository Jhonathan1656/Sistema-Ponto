import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_app/utils/work_schedule_rules.dart';

void main() {
  const schedule = <String, dynamic>{
    'start_allowed_from': '13:25',
    'start_allowed_until': '19:25',
  };

  test('sexta dentro da janela permite entrada', () {
    final friday = DateTime(2026, 7, 17, 13, 25);
    expect(isInternStartWithinSchedule(friday, schedule), isTrue);
  });

  test('sabado exige liberacao mesmo dentro da janela', () {
    final saturday = DateTime(2026, 7, 18, 13, 30);
    expect(isInternStartWithinSchedule(saturday, schedule), isFalse);
  });

  test('domingo exige liberacao mesmo dentro da janela', () {
    final sunday = DateTime(2026, 7, 19, 13, 30);
    expect(isInternStartWithinSchedule(sunday, schedule), isFalse);
  });
}
