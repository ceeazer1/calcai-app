import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/widgets/ti84_screen.dart';

/// Page boundaries must match the firmware's `linesPerPage = 7` in sendPage().
/// The 8th LCD row is the BASIC program's "< | >  Pg:" nav footer.
void main() {
  test('short note is a single screen', () {
    final pages = paginateForTi84('AREA = B*H');
    expect(pages.length, 1);
    expect(pages.first, ['AREA = B*H']);
  });

  test('exactly 7 lines stays one screen', () {
    final pages = paginateForTi84(List.filled(7, 'X').join('\n'));
    expect(pages.length, 1);
    expect(pages.first.length, 7);
  });

  test('8 lines spills onto a second screen', () {
    final pages = paginateForTi84(List.filled(8, 'X').join('\n'));
    expect(pages.length, 2);
    expect(pages[0].length, 7);
    expect(pages[1].length, 1);
  });

  test('empty text still yields one blank screen', () {
    expect(paginateForTi84('').length, 1);
  });
}
