import 'package:client/core/services/receive_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a file past the declared count is refused', () {
    final budget = ReceiveBudget(maxFiles: 1, maxBytes: 100);
    expect(budget.canStartFile(fileOpen: false, declaredSize: 40), isTrue);
    budget.finishFile(40);
    expect(budget.canStartFile(fileOpen: false, declaredSize: 10), isFalse);
  });

  test('bytes past the declared total are refused before they are written', () {
    final budget = ReceiveBudget(maxFiles: 2, maxBytes: 50);
    expect(budget.canStartFile(fileOpen: false, declaredSize: 40), isTrue);
    expect(
      budget.canAcceptChunk(writtenInFile: 30, incoming: 20, declaredSize: 40),
      isFalse,
    );
    budget.finishFile(40);
    expect(budget.canStartFile(fileOpen: false, declaredSize: 20), isFalse);
  });

  test('a header while a file is open is refused', () {
    final budget = ReceiveBudget(maxFiles: 2, maxBytes: 100);
    expect(budget.canStartFile(fileOpen: true, declaredSize: 10), isFalse);
  });
}
