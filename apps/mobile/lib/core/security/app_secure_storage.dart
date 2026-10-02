// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one secure-storage configuration of this app.
///
/// Every credential the app holds — the optional central university identity,
/// the mail password, the exam-portal password, the Moodle web-service token —
/// and the key of every encrypted
/// local cache goes through here. It is a single definition on purpose: the
/// same options spelled out at four call sites is how three of them ended up
/// on a backup-able keychain class without anyone noticing.
///
/// ## Why `first_unlock_this_device`
///
/// `kSecAttrAccessibleAfterFirstUnlock` (without `ThisDeviceOnly`) puts the
/// item into iCloud Keychain and encrypted device backups, from where it is
/// restored onto **another** device. A Moodle token is a bearer credential and
/// the portal password opens the exam records; neither may travel that way
/// (AGENTS.md §2: credentials live in the keychain/keystore and nowhere else).
///
/// `AfterFirstUnlock` rather than `WhenUnlocked` because background work — a
/// mail or grade refresh after a reboot the user has already unlocked once —
/// has to be able to read them.
///
/// The trade is deliberate: moving to a new phone means signing the accounts
/// in again. That is the correct price for credentials that never leave the
/// device they were entered on.
const KeychainAccessibility appKeychainAccessibility =
    KeychainAccessibility.first_unlock_this_device;

const IOSOptions _appIosOptions = IOSOptions(
  accessibility: appKeychainAccessibility,
);

/// The keychain/keystore every store and cache key of this app uses.
///
/// Android needs no counterpart option: the plugin's default there is an
/// AES key held by the Android Keystore, which is already device bound.
FlutterSecureStorage appSecureStorage() =>
    const FlutterSecureStorage(iOptions: _appIosOptions);
