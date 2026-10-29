import 'package:avaremp/utils/user_manual.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual file name includes the release version', () {
    expect(UserManual.fileNameForVersion('0.0.137'), 'User Manual 0.0.137.pdf');
  });

  test('older manuals are the previous file names only', () {
    const String current = 'User Manual 0.0.137.pdf';
    expect(UserManual.isOlderManual(current, current), isFalse);
    expect(UserManual.isOlderManual('USER_MANUAL.pdf', current), isTrue);
    expect(UserManual.isOlderManual('USER_MANUAL.pdf.stamp', current), isTrue);
    expect(UserManual.isOlderManual('User Manual 0.0.136.pdf', current), isTrue);
    expect(UserManual.isOlderManual('checklist.pdf', current), isFalse);
    expect(UserManual.isOlderManual('User Manual notes.pdf', current), isFalse);
  });
}
