import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import 'ipfs_service.dart';
import 'network_overview_service.dart';
import 'secure_storage_service.dart';

final dataWipeServiceProvider = Provider((ref) => DataWipeService(ref));

/// Orchestrates the emergency data wipe (Settings → Emergency Data
/// Wipe) across every durable local store. The wipe is real, not a
/// view reset: after [wipe] the device holds the same bytes as a fresh
/// install, and `AlexandriaRoot.restart` rebuilds the provider tree so
/// in-memory state is reconstructed from that empty state.
class DataWipeService {
  DataWipeService(this._ref);

  final Ref _ref;

  /// Ordering matters:
  ///  1. `stopNode` releases the live IPFS engine before its repo is
  ///     deleted - removing a running repo leaves the engine writing to
  ///     unlinked paths.
  ///  2. `wipeAllData` empties every ledger/table in one transaction.
  ///  3. `wipeLocalData` deletes the on-disk IPFS repo (datastore,
  ///     keystore, blocks, local_blocks).
  ///  4. `deleteAll` clears the whole secure-storage keychain - identity
  ///     keypair, recovery-phrase backup, per-manifest DEKs, onboarding
  ///     flag, node id, attestation key and persisted settings.
  ///
  /// A step that throws aborts the sequence and propagates - the UI
  /// reports an incomplete wipe instead of claiming success on a
  /// partial one.
  Future<void> wipe() async {
    await _ref.read(networkOverviewServiceProvider).stopNode();
    // dart_ipfs's stop() returns before its Hive datastore has fully
    // released the on-disk locks - observed live as a
    // `blocks.lock: Resource temporarily unavailable` exception when
    // the restarted scope's engine re-opened the repo. Give the engine
    // a beat to release its handles before anything deletes or
    // re-opens the repo.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _ref.read(databaseProvider).wipeAllData();
    await _ref.read(ipfsServiceProvider).wipeLocalData();
    await _ref.read(secureStorageServiceProvider).deleteAll();
  }
}
