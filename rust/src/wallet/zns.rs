//! ZNS account identity is derived inside Rust from the existing encrypted
//! software account envelope. Key export is explicit and never persisted.
#[cfg(test)]
use crate::wallet::keys;
use crate::wallet::{account_secret::with_account, network::WalletNetwork};
#[cfg(test)]
use secrecy::ExposeSecret;
use serde_json::{json, Value};
use zcash_keys::address::Address;
#[cfg(test)]
use zcash_keys::keys::UnifiedSpendingKey;
use zeroize::Zeroizing;
#[cfg(test)]
use zip32::fingerprint::SeedFingerprint;

pub fn account(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    secret: Vec<u8>,
) -> Result<Value, String> {
    with_account(db_path, network, account_uuid, secret, |seed, index| {
        let key = vizor_zns_core::derive_key(seed, index)?;
        Ok(
            json!({"address": vizor_zns_core::key_address(&key).to_checksum(None), "derivationPath": vizor_zns_core::derivation_path(index)?, "accountIndex": index}),
        )
    })
}

/// Called only by the explicit password-gated export UI. Verify the full
/// software account identity and expected public address before exporting.
pub fn export_key(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    secret: Vec<u8>,
    expected_owner: &str,
) -> Result<Vec<u8>, String> {
    with_account(db_path, network, account_uuid, secret, |seed, index| {
        let key = vizor_zns_core::derive_key(seed, index)?;
        if !vizor_zns_core::key_address(&key)
            .to_checksum(None)
            .eq_ignore_ascii_case(expected_owner)
        {
            return Err("Base account changed. Authenticate again.".into());
        }
        let bytes = Zeroizing::new(key.to_bytes());
        Ok(bytes.to_vec())
    })
}

pub fn validate_unified_address(network: WalletNetwork, address: &str) -> bool {
    if address.is_empty() || address.len() > 512 {
        return false;
    }
    matches!(
        Address::decode(&network, address),
        Some(Address::Unified(_))
    )
}

pub fn validate_operation(
    network: WalletNetwork,
    operation: &vizor_zns_core::Operation,
) -> Result<(), String> {
    use vizor_zns_core::Operation;
    let ua = match operation {
        Operation::Commit {
            unified_address, ..
        }
        | Operation::Register {
            unified_address, ..
        }
        | Operation::Update {
            unified_address, ..
        }
        | Operation::AtomicRegister {
            unified_address, ..
        } => Some(unified_address),
        _ => None,
    };
    if ua.is_some_and(|ua| !validate_unified_address(network, ua)) {
        return Err("Use a valid Unified Address for the selected Zcash network".into());
    }
    Ok(())
}

pub fn sign(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    secret: Vec<u8>,
    config: &vizor_zns_core::Config,
    operation: &vizor_zns_core::Operation,
    transaction: &vizor_zns_core::Transaction,
) -> Result<Value, String> {
    let secret = Zeroizing::new(secret);
    validate_operation(network, operation)?;
    with_account(
        db_path,
        network,
        account_uuid,
        secret.to_vec(),
        |seed, index| {
            let key = vizor_zns_core::derive_key(seed, index)?;
            let signed = vizor_zns_core::sign(&key, config, operation, transaction)?;
            serde_json::to_value(signed)
                .map_err(|_| "Cannot serialize signed ZNS transaction".into())
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    const PHRASE: &str = "test test test test test test test test test test test junk";

    #[test]
    fn zns_restores_base_identity_across_database_uuids_and_account_indices() {
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let p1 = first.path().join("wallet.db");
        let p2 = second.path().join("wallet.db");
        let p1 = p1.to_str().unwrap();
        let p2 = p2.to_str().unwrap();
        let seed = keys::mnemonic_to_seed(PHRASE).unwrap();
        let (id1, ua) =
            keys::init_db_and_create_account(p1, WalletNetwork::Main, &seed, None, "first")
                .unwrap();
        let (id2, _) =
            keys::init_db_and_create_account(p2, WalletNetwork::Main, &seed, None, "restored")
                .unwrap();
        assert_ne!(id1, id2);
        let a1 = account(p1, WalletNetwork::Main, &id1, PHRASE.as_bytes().to_vec()).unwrap();
        let a2 = account(p2, WalletNetwork::Main, &id2, PHRASE.as_bytes().to_vec()).unwrap();
        assert_eq!(a1, a2);
        assert_eq!(a1["address"], "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
        let (id3, _) =
            keys::add_account_at_index(p1, WalletNetwork::Main, "index2", &seed, None, 2).unwrap();
        let a3 = account(p1, WalletNetwork::Main, &id3, PHRASE.as_bytes().to_vec()).unwrap();
        assert_eq!(a3["address"], "0x98e503f35D0a019cB0a251aD243a4cCFCF371F46");
        assert_eq!(a3["derivationPath"], "m/44'/60'/2'/0/0");
        assert!(validate_unified_address(WalletNetwork::Main, &ua));
        assert!(!validate_unified_address(WalletNetwork::Test, &ua));
        assert!(!validate_unified_address(WalletNetwork::Main, "u1invalid"));
        let transparent = keys::software_account_first_external_transparent_address(
            WalletNetwork::Main,
            &seed,
            0,
        )
        .unwrap();
        assert!(!validate_unified_address(WalletNetwork::Main, &transparent));
    }

    #[test]
    fn exported_key_matches_selected_account_and_rejects_wrong_owner() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let seed = keys::mnemonic_to_seed(PHRASE).unwrap();
        let (id, _) =
            keys::init_db_and_create_account(path, WalletNetwork::Main, &seed, None, "test")
                .unwrap();
        let identity = account(path, WalletNetwork::Main, &id, PHRASE.as_bytes().to_vec()).unwrap();
        let owner = identity["address"].as_str().unwrap();
        let bytes = Zeroizing::new(
            export_key(
                path,
                WalletNetwork::Main,
                &id,
                PHRASE.as_bytes().to_vec(),
                owner,
            )
            .unwrap(),
        );
        let expected = vizor_zns_core::derive_key(seed.expose_secret(), 0).unwrap();
        assert!(bytes.as_slice() == expected.to_bytes().as_slice());
        assert!(export_key(
            path,
            WalletNetwork::Main,
            &id,
            PHRASE.as_bytes().to_vec(),
            "0x0000000000000000000000000000000000000000"
        )
        .is_err());
        assert!(export_key(
            path,
            WalletNetwork::Main,
            &id,
            b"wrong mnemonic".to_vec(),
            owner
        )
        .is_err());
    }

    #[test]
    fn zns_rejects_wrong_mnemonic_passphrase_and_mismatched_ufvk() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let seed = keys::mnemonic_to_seed_with_passphrase(PHRASE, "correct passphrase").unwrap();
        let (id, _) =
            keys::init_db_and_create_account(path, WalletNetwork::Main, &seed, None, "passphrase")
                .unwrap();
        assert!(account(path, WalletNetwork::Main, &id, PHRASE.as_bytes().to_vec()).is_err());
        let envelope =
            json!({"version":1,"mnemonic":PHRASE,"bip39Passphrase":"correct passphrase"})
                .to_string()
                .into_bytes();
        assert!(account(path, WalletNetwork::Main, &id, envelope).is_ok());
        assert!(account(path,WalletNetwork::Main,&id,b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".to_vec()).is_err());

        // A hardware-shaped import can carry an arbitrary claimed fingerprint;
        // matching that metadata must not be enough to sign for the account.
        let other_seed = keys::mnemonic_to_seed(PHRASE).unwrap();
        let other = UnifiedSpendingKey::from_seed(
            &WalletNetwork::Main,
            other_seed.expose_secret(),
            zip32::AccountId::ZERO,
        )
        .unwrap()
        .to_unified_full_viewing_key();
        let fingerprint = SeedFingerprint::from_seed(seed.expose_secret())
            .unwrap()
            .to_bytes();
        let (mismatch, _) = keys::import_hardware_account(
            path,
            WalletNetwork::Main,
            "mismatch",
            &other.encode(&WalletNetwork::Main),
            &fingerprint,
            1,
            None,
            keys::HardwareSignerKind::Keystone,
        )
        .unwrap();
        let envelope =
            json!({"version":1,"mnemonic":PHRASE,"bip39Passphrase":"correct passphrase"})
                .to_string()
                .into_bytes();
        assert!(account(path, WalletNetwork::Main, &mismatch, envelope)
            .unwrap_err()
            .contains("Derived keys do not match"));
    }
}
