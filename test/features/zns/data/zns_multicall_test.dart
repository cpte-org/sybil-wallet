import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_multicall.dart';

void main() {
  test('aggregate3 calldata matches the canonical request encoding', () {
    expect(
      znsAggregate3Calldata([
        ZnsReadRequest(
          '0x17ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5',
          '0x2e4f692a',
        ),
      ]),
      '0x82ad56cb'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '00000000000000000000000017ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000060'
      '0000000000000000000000000000000000000000000000000000000000000004'
      '2e4f692a00000000000000000000000000000000000000000000000000000000',
    );
  });

  test('later elements are laid out after the earlier element calldata', () {
    expect(
      znsAggregate3Calldata([
        ZnsReadRequest(
          '0x17ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5',
          '0x2e4f692a',
        ),
        ZnsReadRequest(
          '0xb2000000000000000000008501b13360000cb2ec',
          '0x313ce567',
        ),
      ]),
      '0x82ad56cb'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '0000000000000000000000000000000000000000000000000000000000000002'
      '0000000000000000000000000000000000000000000000000000000000000040'
      '00000000000000000000000000000000000000000000000000000000000000e0'
      '00000000000000000000000017ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000060'
      '0000000000000000000000000000000000000000000000000000000000000004'
      '2e4f692a00000000000000000000000000000000000000000000000000000000'
      '000000000000000000000000b2000000000000000000008501b13360000cb2ec'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000060'
      '0000000000000000000000000000000000000000000000000000000000000004'
      '313ce56700000000000000000000000000000000000000000000000000000000',
    );
  });

  test('calldata of different lengths pad independently', () {
    expect(
      znsAggregate3Calldata([
        ZnsReadRequest(
          '0x1111111111111111111111111111111111111111',
          '0x12345678',
        ),
        ZnsReadRequest(
          '0x2222222222222222222222222222222222222222',
          '0x1234567890abcdef',
        ),
      ]),
      '0x82ad56cb'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '0000000000000000000000000000000000000000000000000000000000000002'
      '0000000000000000000000000000000000000000000000000000000000000040'
      '00000000000000000000000000000000000000000000000000000000000000e0'
      '0000000000000000000000001111111111111111111111111111111111111111'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000060'
      '0000000000000000000000000000000000000000000000000000000000000004'
      '1234567800000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000002222222222222222222222222222222222222222'
      '0000000000000000000000000000000000000000000000000000000000000001'
      '0000000000000000000000000000000000000000000000000000000000000060'
      '0000000000000000000000000000000000000000000000000000000000000008'
      '1234567890abcdef000000000000000000000000000000000000000000000000',
    );
  });

  test('a single result decodes at its own smaller offset', () {
    // One element places its head directly after the single offset word.
    final single =
        '0x${_word(32)}${_word(1)}${_word(32)}'
        '${_word(1)}${_word(64)}${_word(32)}${'00' * 31}3c';
    final results = znsDecodeAggregate3(single);
    expect(results, hasLength(1));
    expect(results.single.success, isTrue);
    expect(results.single.returnData, '0x${'00' * 31}3c');
  });

  test('aggregate3 results decode successes and failures in order', () {
    final results = znsDecodeAggregate3(_response);
    expect(results, hasLength(2));
    expect(results[0].success, isTrue);
    expect(results[0].returnData, '0x${'00' * 31}3c');
    expect(results[1].success, isFalse);
    expect(results[1].returnData, '0xdeadbeef');
  });

  test('malformed batch responses are rejected rather than scanned', () {
    expect(() => znsDecodeAggregate3('0x'), throwsFormatException);
    expect(
      () => znsDecodeAggregate3(_response, maximum: 1),
      throwsFormatException,
    );
    // A status word other than zero or one is not a valid Multicall3 result.
    const status = 2 + 64 * 4;
    final flipped = _response.replaceRange(status, status + 64, '${'0' * 63}2');
    expect(() => znsDecodeAggregate3(flipped), throwsFormatException);
    // A payload that ends before the element offsets it declares is rejected.
    expect(
      () => znsDecodeAggregate3('0x${_response.substring(2, 2 + 64 * 2)}'),
      throwsFormatException,
    );
  });
}

/// (bool,bytes)[] holding one success with a word and one failure with a short
/// reason, using the same layout a Multicall3 aggregate3 response has.
final _response =
    '0x'
    '${_word(32)}'
    '${_word(2)}'
    '${_word(64)}'
    '${_word(192)}'
    '${_word(1)}'
    '${_word(64)}'
    '${_word(32)}'
    '${'00' * 31}3c'
    '${_word(0)}'
    '${_word(64)}'
    '${_word(4)}'
    'deadbeef${'00' * 28}';

String _word(int value) => value.toRadixString(16).padLeft(64, '0');
