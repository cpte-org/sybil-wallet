import 'dart:typed_data';

import 'zns_abi.dart';
import 'zns_network_config.dart';

/// Multicall3 is deployed at the canonical address on Base and Base Sepolia.
/// Public endpoints throttle bursts, and one batch costs a single request where
/// a fan-out costs one per read.
const znsMulticall3Address = '0xca11bde05977b3631167028862be2a173976ca11';
const znsAggregate3Selector = '0x82ad56cb';

/// One contract read that can be batched with others at the same block.
class ZnsReadRequest {
  ZnsReadRequest(String to, this.data) : to = znsAddress(to);
  final String to;
  final String data;
}

class ZnsMulticallResult {
  const ZnsMulticallResult({required this.success, required this.returnData});
  final bool success;
  final String returnData;
}

/// Encodes aggregate3((address,bool,bytes)[]) with allowFailure set for every
/// call, so one failing read cannot hide the others.
String znsAggregate3Calldata(List<ZnsReadRequest> calls) {
  final count = calls.length;
  if (count == 0) throw const FormatException('Empty batch read');
  // [offset to array][length][element offsets][elements]. Element offsets are
  // relative to the first offset word, and each element is its own head of
  // three words followed by its length-prefixed calldata. All lengths below are
  // bytes, while the calldata tails are hex.
  const offsetsStart = 64;
  const headBytes = 96, lengthWordBytes = 32;
  final elementsStart = offsetsStart + 32 * count;
  final starts = <int>[];
  final tails = <String>[];
  var start = elementsStart;
  for (final call in calls) {
    final data = znsHex(call.data, allowEmpty: true).substring(2);
    final padded = data.padRight(((data.length + 63) ~/ 64) * 64, '0');
    starts.add(start);
    tails.add('${ZnsAbi.uintWord(BigInt.from(data.length ~/ 2))}$padded');
    start += headBytes + lengthWordBytes + padded.length ~/ 2;
  }
  final buffer = StringBuffer(znsAggregate3Selector)
    ..write(ZnsAbi.uintWord(BigInt.from(32)))
    ..write(ZnsAbi.uintWord(BigInt.from(count)));
  for (final elementStart in starts) {
    buffer.write(ZnsAbi.uintWord(BigInt.from(elementStart - offsetsStart)));
  }
  for (var i = 0; i < count; i++) {
    buffer
      ..write(ZnsAbi.addressWord(calls[i].to))
      ..write(ZnsAbi.uintWord(BigInt.one))
      ..write(ZnsAbi.uintWord(BigInt.from(headBytes)))
      ..write(tails[i]);
  }
  return buffer.toString();
}

/// Decodes the aggregate3 result. Bounded: a malformed, oversized or
/// non-canonical payload is rejected rather than scanned.
List<ZnsMulticallResult> znsDecodeAggregate3(
  String payload, {
  int maximum = 64,
  int maximumBytes = 65536,
}) {
  final abi = ZnsAbi(payload);
  final array = abi.offset(0, 0, minimum: 32);
  final count = abi.word(array);
  if (count > BigInt.from(maximum)) {
    throw const FormatException('Batch read response is too large');
  }
  final results = <ZnsMulticallResult>[];
  for (var i = 0; i < count.toInt(); i++) {
    // Offsets are relative to the first offset word, so the earliest element
    // sits one word of offsets into the payload.
    final element = abi.offset(array + 32, i, minimum: 32);
    final success = abi.word(element);
    if (success > BigInt.one) {
      throw const FormatException('Invalid batch read status');
    }
    final bytesAt = abi.offset(element, 1, minimum: 64);
    results.add(
      ZnsMulticallResult(
        success: success == BigInt.one,
        returnData: znsHexBytes(
          abi.dynamicBytes(bytesAt, maximum: maximumBytes),
        ),
      ),
    );
  }
  return results;
}

String znsHexBytes(Uint8List value) {
  final buffer = StringBuffer('0x');
  for (final byte in value) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
