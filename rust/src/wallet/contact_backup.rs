//! Portable archives use a separate seed/network/account-index encryption scope.
//! Database UUIDs and the app password are deliberately not recovery inputs.
use super::{account_secret::with_account, network::WalletNetwork, secret_payload};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

const DOMAIN: &str = "zcash-contact/portable-backup";
const LIMIT: usize = 1_048_576;

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Archive {
    domain: String,
    network: String,
    account_index: u32,
    payload: String,
}

fn network_name(network: WalletNetwork) -> &'static str {
    match network {
        WalletNetwork::Main => "main",
        WalletNetwork::Test => "test",
        WalletNetwork::Regtest => "regtest",
    }
}

// Reuse the wallet's PBKDF2-HMAC-SHA256 + random-nonce AES-256-GCM envelope.
// The input is the BIP39 seed (including its passphrase), not a human password.
// Domain, network and index are part of the KDF scope, so metadata substitution
// cannot authenticate. No Base key or contact signing key is reused.
fn salt(network: WalletNetwork, index: u32) -> Vec<u8> {
    format!("{DOMAIN}\0{}\0{index}", network_name(network)).into_bytes()
}

fn seal(
    seed: &[u8],
    index: u32,
    network: WalletNetwork,
    plain: Zeroizing<Vec<u8>>,
) -> Result<String, String> {
    if plain.is_empty() || plain.len() > LIMIT {
        return Err("Contact archive exceeds its size limit".into());
    }
    let payload = secret_payload::encrypt_payload(plain, seed, &salt(network, index))?;
    serde_json::to_string(&Archive {
        domain: DOMAIN.into(),
        network: network_name(network).into(),
        account_index: index,
        payload,
    })
    .map_err(|_| "Cannot encode contact archive".into())
}

fn open(
    seed: &[u8],
    index: u32,
    network: WalletNetwork,
    archive: &str,
) -> Result<Zeroizing<Vec<u8>>, String> {
    if archive.len() > LIMIT * 2 {
        return Err("Contact archive exceeds its size limit".into());
    }
    let a: Archive = serde_json::from_str(archive).map_err(|_| "Invalid contact archive")?;
    if a.domain != DOMAIN || a.network != network_name(network) || a.account_index != index {
        return Err("Contact archive belongs to another network or account index".into());
    }
    let plain = secret_payload::decrypt_payload(a.payload.as_bytes(), seed, &salt(network, index))
        .map_err(|_| "Cannot authenticate contact archive with this wallet".to_string())?;
    if plain.is_empty() || plain.len() > LIMIT {
        return Err("Contact archive exceeds its size limit".into());
    }
    Ok(plain)
}

pub fn encrypt(
    db: &str,
    network: WalletNetwork,
    account: &str,
    secret: Vec<u8>,
    plain: Vec<u8>,
) -> Result<String, String> {
    let plain = Zeroizing::new(plain);
    with_account(db, network, account, secret, |seed, index| {
        seal(seed, index, network, plain)
    })
}

pub fn decrypt(
    db: &str,
    network: WalletNetwork,
    account: &str,
    secret: Vec<u8>,
    archive: &str,
) -> Result<Zeroizing<Vec<u8>>, String> {
    with_account(db, network, account, secret, |seed, index| {
        open(seed, index, network, archive)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restored_database_uuid_can_decrypt_but_wrong_wallet_cannot() {
        use crate::wallet::keys;
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let seed = keys::mnemonic_to_seed(phrase).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a.db");
        let b = dir.path().join("b.db");
        let a = a.to_str().unwrap();
        let b = b.to_str().unwrap();
        let (first, _) =
            keys::init_db_and_create_account(a, WalletNetwork::Main, &seed, None, "original")
                .unwrap();
        let (second, _) =
            keys::init_db_and_create_account(b, WalletNetwork::Main, &seed, None, "restored")
                .unwrap();
        assert_ne!(first, second);
        let archive = encrypt(
            a,
            WalletNetwork::Main,
            &first,
            phrase.as_bytes().to_vec(),
            b"contact-only fixture".to_vec(),
        )
        .unwrap();
        assert_eq!(
            &*decrypt(
                b,
                WalletNetwork::Main,
                &second,
                phrase.as_bytes().to_vec(),
                &archive
            )
            .unwrap(),
            b"contact-only fixture"
        );
        let wrong = "legal winner thank year wave sausage worth useful legal winner thank yellow";
        assert!(decrypt(
            b,
            WalletNetwork::Main,
            &second,
            wrong.as_bytes().to_vec(),
            &archive
        )
        .is_err());
    }
    #[test]
    fn authenticates_seed_network_index_and_ciphertext() {
        let seed = [17; 64];
        let a = seal(
            &seed,
            2,
            WalletNetwork::Test,
            Zeroizing::new(b"private contact fixture".to_vec()),
        )
        .unwrap();
        let b = seal(
            &seed,
            2,
            WalletNetwork::Test,
            Zeroizing::new(b"private contact fixture".to_vec()),
        )
        .unwrap();
        assert_ne!(a, b);
        assert_eq!(
            &*open(&seed, 2, WalletNetwork::Test, &a).unwrap(),
            b"private contact fixture"
        );
        assert!(open(&[18; 64], 2, WalletNetwork::Test, &a).is_err());
        assert!(open(&seed, 3, WalletNetwork::Test, &a).is_err());
        assert!(open(&seed, 2, WalletNetwork::Main, &a).is_err());
        let mut changed: Archive = serde_json::from_str(&a).unwrap();
        changed.account_index = 3;
        assert!(open(
            &seed,
            3,
            WalletNetwork::Test,
            &serde_json::to_string(&changed).unwrap()
        )
        .is_err());
        let mut payload: serde_json::Value = serde_json::from_str(&changed.payload).unwrap();
        payload["c"] = "AAAA".into();
        changed.account_index = 2;
        changed.payload = payload.to_string();
        assert!(open(
            &seed,
            2,
            WalletNetwork::Test,
            &serde_json::to_string(&changed).unwrap()
        )
        .is_err());
        assert!(seal(
            &seed,
            0,
            WalletNetwork::Test,
            Zeroizing::new(vec![0; LIMIT + 1])
        )
        .is_err());
    }
}
