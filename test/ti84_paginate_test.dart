import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/widgets/ti84_screen.dart';

/// Page boundaries must match the firmware's `linesPerPage = 7` in sendPage().
/// The 8th LCD row is the BASIC program's "< | >  Pg:" nav footer.
void main() {
  testWidgets('preview pages expose named buttons and disabled boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Ti84Pager(
            text: List.generate(8, (i) => 'Line ${i + 1}').join('\n'),
          ),
        ),
      ),
    );
    final next = find.byTooltip('Next page');
    final previous = find.byTooltip('Previous page');
    final nextData = tester.getSemantics(next).getSemanticsData();
    expect(nextData.tooltip, 'Next page');
    expect(nextData.flagsCollection.isButton, isTrue);
    expect(nextData.hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester
          .getSemantics(previous)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(next);
    await tester.pump();
    expect(find.text('Screen 2 of 2  ·  1/7 lines'), findsOneWidget);
    expect(
      tester
          .getSemantics(next)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    expect(
      tester.getSemantics(previous).getSemanticsData().tooltip,
      'Previous page',
    );
    await tester.tap(previous);
    await tester.pump();
    expect(find.text('Screen 1 of 2  ·  7/7 lines'), findsOneWidget);
  });
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
