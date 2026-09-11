//! Validate software secret ownership before seed-scoped operations.
use crate::wallet::{
    db::{open_wallet_db_for_read_with_timeout, READ_DB_BUSY_TIMEOUT},
    keys,
    network::WalletNetwork,
};
use secrecy::ExposeSecret;
use zcash_client_backend::data_api::{Account, WalletRead};
use zcash_keys::keys::UnifiedSpendingKey;
use zeroize::Zeroizing;
use zip32::fingerprint::SeedFingerprint;

pub(crate) fn with_account<T>(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    secret: Vec<u8>,
    f: impl FnOnce(&[u8], u32) -> Result<T, String>,
) -> Result<T, String> {
    let secret = Zeroizing::new(secret);
    let seed = keys::mnemonic_bytes_to_seed(&secret)?;
    drop(secret);
    let db = open_wallet_db_for_read_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)?;
    let id = keys::parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(id)
        .map_err(|e| format!("Cannot read software account: {e}"))?
        .ok_or("Account not found")?;
    let derivation = account
        .source()
        .key_derivation()
        .ok_or("This operation requires a software account with seed derivation metadata")?;
    let seed_fp = SeedFingerprint::from_seed(seed.expose_secret()).ok_or("Invalid seed length")?;
    if derivation.seed_fingerprint() != &seed_fp {
        return Err("The software secret does not belong to this account".into());
    }
    // A matching fingerprint alone is insufficient: compare the complete
    // account UFVK, including the recorded account index and Zcash network.
    let usk =
        UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), derivation.account_index())
            .map_err(|_| "Cannot derive software account")?;
    let derived = usk.to_unified_full_viewing_key();
    let stored = account.ufvk().ok_or("Account has no viewing key")?;
    if derived.encode(&network) != stored.encode(&network) {
        return Err("Derived keys do not match the selected software account".into());
    }
    f(seed.expose_secret(), u32::from(derivation.account_index()))
}
