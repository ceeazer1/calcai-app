import 'package:calcai_app/screens/auth_screen.dart';
import 'package:calcai_app/screens/reset_password_screen.dart';
import 'package:calcai_app/screens/verify_email_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/code_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';

const _accepted =
    'Request accepted. If applicable, check your email and spam folder.';
const _failure =
    'Could not reach CalcAI. Check your internet connection and try again.';

class _AuthAccessibilityFixture extends FakeAuthService {
  bool acceptRequest = true;
  int requestCalls = 0;
  int verificationCalls = 0;

  @override
  String get error => _failure;

  @override
  Future<bool> requestPasswordReset(String email) async {
    requestCalls++;
    return acceptRequest;
  }

  @override
  Future<bool> resendVerificationCode(String email) async {
    requestCalls++;
    return acceptRequest;
  }

  @override
  Future<bool> verifyEmailCode(String email, String code) async {
    verificationCalls++;
    return false;
  }
}

Future<_AuthAccessibilityFixture> _show(
  WidgetTester tester,
  Widget screen, {
  double textScale = 1,
  bool keyboardOpen = false,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardOpen ? 216 : 0);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final auth = _AuthAccessibilityFixture();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _checkPasswordToggle(WidgetTester tester, Finder field) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.ensureVisible(field);
    await tester.enterText(field, 'fixture password');
    await tester.showKeyboard(field);
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    final selection = editable.controller.selection;
    expect(editable.focusNode.hasFocus, isTrue);

    for (final label in ['Show password', 'Hide password']) {
      final button = find.byTooltip(label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.tooltip, label);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(
        tester.widget<TextField>(field).obscureText,
        label == 'Show password',
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).obscureText,
        label != 'Show password',
      );
      expect(editable.controller.text, 'fixture password');
      expect(editable.controller.selection, selection);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    }
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  } finally {
    semantics.dispose();
  }
}

Future<void> _checkFullMessage(
  WidgetTester tester,
  String message,
  String nextAction,
) async {
  final text = find.text(message);
  expect(text, findsOneWidget);
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(text);
  // A fixed-height status slot can clip multiple lines without a layout error.
  expect(
    paragraph.size.height + 0.01,
    greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(paragraph.size.width)),
  );
  final viewport = find.ancestor(of: text, matching: find.byType(Scrollable));
  final messageRect = tester.getRect(text);
  final viewportRect = tester.getRect(viewport);
  expect(messageRect.top, greaterThanOrEqualTo(viewportRect.top - 0.01));
  expect(messageRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 0.01));
  await tester.ensureVisible(find.text(nextAction));
  await tester.pumpAndSettle();
  expect(find.text(nextAction).hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('sign-in password toggle is named and keeps typing focus', (
    tester,
  ) async {
    await _show(tester, const AuthScreen(), keyboardOpen: true);
    await _checkPasswordToggle(tester, find.byType(TextField).at(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reset password toggle is named and keeps typing focus', (
    tester,
  ) async {
    await _show(
      tester,
      const ResetPasswordScreen(initialEmail: 'fixture@example.com'),
      keyboardOpen: true,
    );
    await tester.ensureVisible(find.text('Send code'));
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CodeInput>(find.byType(CodeInput)).semanticLabel,
      'Password reset code',
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    expect(find.text('Set a new password'), findsOneWidget);
    await _checkPasswordToggle(tester, find.byType(TextField));
    await tester.pumpWidget(const SizedBox());
  });

  for (final verify in [true, false]) {
    for (final accepted in [true, false]) {
      testWidgets(
        '${verify ? 'verification' : 'reset'} ${accepted ? 'accepted' : 'error'} '
        'message fits narrow large text with the keyboard open',
        (tester) async {
          final auth = await _show(
            tester,
            verify
                ? const VerifyEmailScreen(email: 'fixture@example.com')
                : const ResetPasswordScreen(
                    initialEmail: 'fixture@example.com',
                  ),
            textScale: 2,
            keyboardOpen: true,
          );
          auth.acceptRequest = accepted;
          if (verify) {
            expect(
              tester.widget<CodeInput>(find.byType(CodeInput)).semanticLabel,
              'Email verification code',
            );
          }
          if (verify && accepted) {
            await tester.pump(const Duration(seconds: 46));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Resend code'));
            await tester.tap(find.text('Resend code'));
          } else if (verify) {
            await tester.enterText(find.byType(TextField), '123456');
          } else {
            await tester.ensureVisible(find.text('Send code'));
            await tester.tap(find.text('Send code'));
          }
          await tester.pumpAndSettle();
          if (!verify && accepted) {
            expect(
              tester.widget<CodeInput>(find.byType(CodeInput)).semanticLabel,
              'Password reset code',
            );
          }
          expect(
            verify && !accepted ? auth.verificationCalls : auth.requestCalls,
            1,
          );
          await _checkFullMessage(
            tester,
            accepted ? _accepted : _failure,
            verify
                ? 'Confirm'
                : accepted
                ? 'Continue'
                : 'Send code',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
