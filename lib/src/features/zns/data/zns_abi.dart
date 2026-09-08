import 'dart:convert';
import 'dart:typed_data';
import 'zns_network_config.dart';

/// Minimal bounded ABI codec for the fixed registry and audited router ABI.
/// Transaction signing independently validates operation calldata in Rust.
class ZnsAbi {
  ZnsAbi(String data)
    : bytes = Uint8List.fromList([
        for (var i = 2; i < znsHex(data, allowEmpty: true).length; i += 2)
          int.parse(data.substring(i, i + 2), radix: 16),
      ]);
  final Uint8List bytes;
  BigInt word(int byteOffset) {
    if (byteOffset < 0 || byteOffset + 32 > bytes.length) {
      throw const FormatException('Truncated ABI word');
    }
    var value = BigInt.zero;
    for (var i = byteOffset; i < byteOffset + 32; i++) {
      value = (value << 8) | BigInt.from(bytes[i]);
    }
    return value;
  }

  int offset(int base, int index, {int minimum = 0}) {
    final value = word(base + index * 32);
    if (value > BigInt.from(bytes.length) ||
        value % BigInt.from(32) != BigInt.zero ||
        value < BigInt.from(minimum)) {
      throw const FormatException('Invalid ABI offset');
    }
    final absolute = base + value.toInt();
    if (absolute + 32 > bytes.length) {
      throw const FormatException('ABI offset outside payload');
    }
    return absolute;
  }

  String address(int byteOffset) {
    final value = word(byteOffset);
    if (value.bitLength > 160) {
      throw const FormatException('Invalid ABI address padding');
    }
    return '0x${value.toRadixString(16).padLeft(40, '0')}';
  }

  Uint8List dynamicBytes(int lengthOffset, {int maximum = 65536}) {
    final length = word(lengthOffset);
    if (length > BigInt.from(maximum) ||
        lengthOffset + 32 + length.toInt() > bytes.length) {
      throw const FormatException('Invalid ABI byte length');
    }
    return Uint8List.sublistView(
      bytes,
      lengthOffset + 32,
      lengthOffset + 32 + length.toInt(),
    );
  }

  String stringAt(int base, int index, {int minimum = 0, int maximum = 512}) =>
      utf8.decode(
        dynamicBytes(offset(base, index, minimum: minimum), maximum: maximum),
      );
  static String uintWord(BigInt value) =>
      znsQuantity(value).substring(2).padLeft(64, '0');
  static String addressWord(String value) =>
      znsAddress(value).substring(2).padLeft(64, '0');
  static String stringCall(String selector, String value) {
    final encoded = utf8.encode(value);
    final raw = encoded.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '$selector${uintWord(BigInt.from(32))}${uintWord(BigInt.from(encoded.length))}${raw.padRight(((encoded.length + 31) ~/ 32) * 64, '0')}';
  }
}
