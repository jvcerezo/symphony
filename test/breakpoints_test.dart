import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/layout/breakpoints.dart';

void main() {
  Future<bool> isDesktopAt(WidgetTester tester, double width) async {
    late bool result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (context) {
            result = Breakpoints.isDesktop(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('desktop layout starts exactly at the 850px breakpoint',
      (tester) async {
    expect(Breakpoints.desktop, 850);
    expect(await isDesktopAt(tester, 849.9), isFalse);
    expect(await isDesktopAt(tester, 850), isTrue);
    expect(await isDesktopAt(tester, 1280), isTrue);
    expect(await isDesktopAt(tester, 400), isFalse);
  });
}
