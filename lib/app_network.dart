import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Compile-time network selector: launching with
/// `--dart-define=ALX_TESTNET=true` runs Alexandria on an isolated
/// test network.
///
/// Under the flag every surface that can touch the main network is
/// namespaced: the application data dirs, the SQLite file, every
/// secure-storage key, the libp2p swarm (a fixed pnet pre-shared key
/// means a testnet node cannot even handshake with a mainnet peer),
/// the rendezvous gossipsub topic, the mesh handshake domain, and the
/// Moltbook submolt names. Mainnet bootstrap peers are not dialed.
/// Testnet actions therefore cannot affect main Alexandria state.
class AppNetwork {
  /// Read from `--dart-define=ALX_TESTNET`. A mutable static so tests
  /// can simulate the flag - restore `false` in tearDown.
  static bool testnet = const bool.fromEnvironment('ALX_TESTNET');

  /// Keychain/database prefix applied to every testnet key.
  static const String testnetKeyPrefix = 'testnet_';

  /// 'testnet' or 'mainnet' - for honest UI labeling.
  static String get name => testnet ? 'testnet' : 'mainnet';

  /// Secure-storage key for the active network.
  static String scopedKey(String key) =>
      testnet ? '$testnetKeyPrefix$key' : key;

  /// Gossipsub topic for the active network. Callers pass the full
  /// mainnet topic (`/alexandria/...`); testnet swaps the prefix for
  /// `/alexandria-testnet/...` so announcements never cross.
  static String topic(String mainnetTopic) => testnet
      ? mainnetTopic.replaceFirst('/alexandria/', '/alexandria-testnet/')
      : mainnetTopic;

  /// Moltbook submolt name for the active network.
  static String submolt(String name) => testnet ? '$name-testnet' : name;

  /// Mesh handshake channel domain - a distinct HKDF `info` string so
  /// a testnet handshake cannot derive a session a mainnet node
  /// accepts.
  static String get meshChannelDomain => testnet
      ? 'alexandria:testnet:mesh-channel:v1'
      : 'alexandria:mesh-channel:v1';

  /// Fixed 32-byte pnet pre-shared key shared by every testnet node.
  /// libp2p wraps each connection in this PSK, so a testnet node can
  /// never complete a handshake with a mainnet peer. Null on mainnet -
  /// the public swarm runs without a PSK.
  static Uint8List? get privateNetworkPsk => testnet
      ? Uint8List.fromList(
          sha256.convert(utf8.encode('alexandria-testnet-pnet-v1')).bytes)
      : null;
}
