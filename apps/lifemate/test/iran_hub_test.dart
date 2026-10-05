import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/iran_hub.dart';

void main() {
  test('grade 7 maps to first year of secondary first cycle', () {
    expect(iranStageLabel(7), 'دوره اول متوسطه');
    expect(iranLocalYear(7), 1);
  });

  test('Iranian stages cover grades 1 through 12', () {
    expect(iranStageLabel(1), 'دوره اول ابتدایی');
    expect(iranStageLabel(4), 'دوره دوم ابتدایی');
    expect(iranStageLabel(10), 'دوره دوم متوسطه');
  });
}
