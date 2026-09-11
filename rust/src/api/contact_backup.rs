//! Seed-unlocked contact archives. Frontend clears plaintext buffers after use.
use crate::wallet::{contact_backup, keys::parse_network};

pub fn contact_backup_encrypt(
    db_path: String,
    network: String,
    account_uuid: String,
    secret_bytes: Vec<u8>,
    plain_bytes: Vec<u8>,
) -> Result<String, String> {
    let secret = zeroize::Zeroizing::new(secret_bytes);
    let plain = zeroize::Zeroizing::new(plain_bytes);
    contact_backup::encrypt(
        &db_path,
        parse_network(&network)?,
        &account_uuid,
        secret.to_vec(),
        plain.to_vec(),
    )
}

pub fn contact_backup_decrypt(
    db_path: String,
    network: String,
    account_uuid: String,
    secret_bytes: Vec<u8>,
    archive: String,
) -> Result<Vec<u8>, String> {
    let secret = zeroize::Zeroizing::new(secret_bytes);
    Ok(contact_backup::decrypt(
        &db_path,
        parse_network(&network)?,
        &account_uuid,
        secret.to_vec(),
        &archive,
    )?
    .to_vec())
}
