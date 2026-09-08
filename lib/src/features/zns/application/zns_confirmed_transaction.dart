import 'dart:convert';
import 'dart:typed_data';

import '../data/zns_abi.dart';
import '../data/zns_network_config.dart';

/// Decode intent and accounting fields from an authoritative RPC transaction.
/// The caller must separately establish receipt success and canonical finality.
/// Imported recovery metadata must never be merged over these returned fields.
Map<String, dynamic> znsConfirmedTransaction({
  required Map<String, dynamic> transaction,
  required ZnsNetworkConfig config,
  required String owner,
  required String expectedHash,
  required String expectedBlockHash,
  required BigInt expectedBlockNumber,
}) {
  String text(String field) {
    final value = transaction[field];
    if (value is! String) {
      throw FormatException('Missing confirmed transaction $field');
    }
    return value;
  }

  final from = znsAddress(text('from'));
  final hash = znsHex(text('hash'), bytes: 32);
  final blockHash = znsHex(text('blockHash'), bytes: 32);
  final blockNumber = znsParseQuantity(transaction['blockNumber']);
  if (from != znsAddress(owner) ||
      hash != znsHex(expectedHash, bytes: 32) ||
      blockHash != znsHex(expectedBlockHash, bytes: 32) ||
      blockNumber != expectedBlockNumber) {
    throw const FormatException('Confirmed transaction identity mismatch');
  }
  if (transaction['chainId'] != null &&
      znsParseQuantity(transaction['chainId']) != BigInt.from(config.chainId)) {
    throw const FormatException('Confirmed transaction chain mismatch');
  }
  final to = znsAddress(text('to'));
  final data = znsHex(text('input'));
  if (transaction['data'] != null && transaction['data'] != data) {
    throw const FormatException('Conflicting transaction input fields');
  }
  final value = znsParseQuantity(transaction['value']);
  final nonce = znsParseQuantity(transaction['nonce']);
  final gas = znsParseQuantity(transaction['gas']);
  final fee = znsParseQuantity(
    transaction['maxFeePerGas'] ?? transaction['gasPrice'],
  );
  if (gas == BigInt.zero || (gas * fee).bitLength > 256) {
    throw const FormatException('Invalid confirmed transaction fee bound');
  }
  final decoder = _IntentDecoder(config, from);
  final intent = to == from
      ? decoder.atomic(data, value)
      : decoder.call(to, data, value);
  return {
    'hash': hash,
    'blockHash': blockHash,
    'blockNumber': blockNumber.toString(),
    'from': from,
    'to': to,
    'data': data,
    'nonce': nonce.toString(),
    'value': value.toString(),
    'gasLimit': gas.toString(),
    'maxFeePerGas': fee.toString(),
    'executionFeeCeiling': (gas * fee).toString(),
    ...intent,
    'verifiedIntent': true,
  };
}

class _IntentDecoder {
  const _IntentDecoder(this.config, this.owner);
  final ZnsNetworkConfig config;
  final String owner;

  Map<String, dynamic> call(String to, String data, BigInt value) {
    final encoded = _Encoding(data);
    if (to == config.kyberRouterAddress) {
      return swap(encoded, value);
    }
    if (value != BigInt.zero) {
      throw const FormatException('Unexpected ETH on a ZNS token operation');
    }
    if (to == config.tokenAddress && encoded.selector == '095ea7b3') {
      encoded.exact(64);
      if (encoded.abi.address(0) != config.registryAddress) {
        throw const FormatException('Unexpected token approval recipient');
      }
      return {'kind': 'approve', 'amount': encoded.abi.word(32).toString()};
    }
    if (to != config.registryAddress) {
      throw const FormatException('Unsupported confirmed transaction target');
    }
    switch (encoded.selector) {
      case 'f14fcbc8':
        encoded.exact(32);
        return {'kind': 'commit', 'commitment': encoded.hexAt(0, 32)};
      case 'f5de1230':
        final name = encoded.dynamicAt(0, 0, 96, maximum: 63);
        final ua = encoded.dynamicAt(0, 1, name.end, maximum: 512);
        encoded.exact(ua.end);
        final label = utf8.decode(name.bytes);
        final address = utf8.decode(ua.bytes);
        if (!RegExp(
              r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
            ).hasMatch(label) ||
            address.isEmpty) {
          throw const FormatException('Invalid confirmed registration text');
        }
        return {
          'kind': 'register',
          'name': label,
          'unifiedAddress': address,
          'secret': encoded.hexAt(64, 32),
        };
      case '0f421135':
        final ua = encoded.dynamicAt(0, 1, 64, maximum: 512);
        encoded.exact(ua.end);
        final address = utf8.decode(ua.bytes);
        if (address.isEmpty) {
          throw const FormatException('Empty confirmed Unified Address');
        }
        return {
          'kind': 'update',
          'positionId': _position(encoded.abi.word(0)),
          'unifiedAddress': address,
        };
      case '9c75dd35':
      case '0962ef79':
      case '37bdc99b':
        encoded.exact(32);
        return {
          'kind': switch (encoded.selector) {
            '9c75dd35' => 'refresh',
            '0962ef79' => 'claimRewards',
            _ => 'release',
          },
          'positionId': _position(encoded.abi.word(0)),
        };
      case 'b9728620':
        encoded.exact(0);
        return {'kind': 'withdrawClaims'};
      default:
        throw const FormatException('Unsupported confirmed registry selector');
    }
  }

  Map<String, dynamic> atomic(String data, BigInt outerValue) {
    final encoded = _Encoding(data);
    if (encoded.selector != '3ab37ba0' || outerValue != BigInt.zero) {
      throw const FormatException('Unsupported self transaction');
    }
    final abi = encoded.abi;
    if (abi.word(0) != BigInt.from(64) || abi.word(32) == BigInt.zero) {
      throw const FormatException('Invalid atomic batch header');
    }
    final count = abi.word(64);
    if (count != BigInt.two && count != BigInt.from(3)) {
      throw const FormatException('Unexpected atomic call count');
    }
    final length = count.toInt(), arrayBase = 96;
    var cursor = arrayBase + length * 32;
    var spent = BigInt.zero;
    final calls = <Map<String, dynamic>>[];
    for (var i = 0; i < length; i++) {
      final tuple = abi.offset(arrayBase, i, minimum: length * 32);
      if (tuple != cursor) {
        throw const FormatException('Noncanonical atomic call offsets');
      }
      final target = abi.address(tuple), value = abi.word(tuple + 32);
      final bytes = encoded.dynamicAt(tuple, 2, tuple + 96);
      cursor = bytes.end;
      final nested = '0x${_hex(bytes.bytes)}';
      final intent = call(target, nested, value);
      final expected = i == length - 1
          ? 'register'
          : i == length - 2
          ? 'approve'
          : 'swap';
      if (intent['kind'] != expected) {
        throw const FormatException('Unexpected atomic operation order');
      }
      spent += value;
      calls.add(intent);
    }
    encoded.exact(cursor);
    if (spent.bitLength > 256 ||
        BigInt.parse(calls[length - 2]['amount'] as String) == BigInt.zero) {
      throw const FormatException('Invalid atomic transaction amount');
    }
    return {
      ...calls.last,
      'kind': 'atomicRegister',
      'amount': calls[length - 2]['amount'],
      'value': spent.toString(),
      'deadline': abi.word(32).toString(),
      if (length == 3) 'minimumOutput': calls.first['minimumOutput'],
    };
  }

  Map<String, dynamic> swap(_Encoding encoded, BigInt value) {
    if (encoded.selector != 'e21fd0e9' || value <= BigInt.zero) {
      throw const FormatException('Unsupported confirmed swap');
    }
    final abi = encoded.abi;
    if (abi.word(0) != BigInt.from(32)) {
      throw const FormatException('Noncanonical swap tuple');
    }
    const execution = 32;
    if (abi.address(execution) !=
            '0x8f10b468b06c6fd214b65f87778827f7d113f996' ||
        abi.address(execution + 32) != ZnsNetworkConfig.zeroAddress) {
      throw const FormatException('Unsupported confirmed swap executor');
    }
    final target = encoded.dynamicAt(execution, 2, execution + 160);
    if (target.bytes.isEmpty) {
      throw const FormatException('Empty swap execution data');
    }
    final desc = abi.offset(execution, 3, minimum: 160);
    if (desc != target.end ||
        abi.address(desc) != ZnsNetworkConfig.nativeEth ||
        abi.address(desc + 32) != config.tokenAddress ||
        abi.address(desc + 192) != owner ||
        abi.word(desc + 224) != value) {
      throw const FormatException('Swap token, recipient or amount mismatch');
    }
    var cursor = desc + 352;
    for (final index in [2, 3, 4, 5]) {
      final empty = encoded.dynamicAt(desc, index, cursor, maximum: 0);
      cursor = empty.end;
    }
    final flags = abi.word(desc + 288), minimum = abi.word(desc + 256);
    if ((flags != BigInt.zero && flags != BigInt.from(512)) ||
        minimum == BigInt.zero) {
      throw const FormatException('Invalid confirmed swap output bounds');
    }
    cursor = encoded.dynamicAt(desc, 10, cursor, maximum: 0).end;
    cursor = encoded.dynamicAt(execution, 4, cursor).end;
    encoded.exact(cursor);
    return {'kind': 'swap', 'minimumOutput': minimum.toString()};
  }
}

String _position(BigInt value) {
  if (value == BigInt.zero) {
    throw const FormatException('Invalid confirmed position identity');
  }
  return value.toString();
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

class _Encoding {
  _Encoding(String data)
    : selector = _selector(data),
      abi = ZnsAbi('0x${data.substring(10)}');
  final String selector;
  final ZnsAbi abi;

  static String _selector(String data) {
    znsHex(data);
    if (data.length < 10 || data.length > 262154) {
      throw const FormatException('Invalid confirmed calldata size');
    }
    return data.substring(2, 10);
  }

  String hexAt(int start, int length) {
    if (start < 0 || start + length > abi.bytes.length) {
      throw const FormatException('Truncated confirmed calldata');
    }
    return '0x${_hex(abi.bytes.sublist(start, start + length))}';
  }

  ({Uint8List bytes, int end}) dynamicAt(
    int base,
    int index,
    int expected, {
    int maximum = 65536,
  }) {
    final offset = abi.offset(base, index);
    if (offset != expected) {
      throw const FormatException('Noncanonical dynamic ABI offset');
    }
    final bytes = abi.dynamicBytes(offset, maximum: maximum);
    final end = offset + 32 + ((bytes.length + 31) ~/ 32) * 32;
    if (end > abi.bytes.length ||
        abi.bytes
            .sublist(offset + 32 + bytes.length, end)
            .any((byte) => byte != 0)) {
      throw const FormatException('Invalid dynamic ABI padding');
    }
    return (bytes: bytes, end: end);
  }

  void exact(int length) {
    if (abi.bytes.length != length) {
      throw const FormatException('Truncated or trailing confirmed calldata');
    }
  }
}
