import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/contracts/enums.dart';

void main() {
  test('enums round-trip and throw on unknown', () {
    expect(Role.fromWire('miner'), Role.miner);
    expect(PpeKey.fromWire('HELMET'), PpeKey.helmet);
    expect(() => Role.fromWire('boss'), throwsArgumentError);
  });
}
