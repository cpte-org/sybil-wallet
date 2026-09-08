//! Flat JSON FRB boundary keeps EVM integers as decimal strings. The frontend
//! must discard plaintext secret bytes after each call as in the Zcash signer.
use crate::wallet::{keys::parse_network, zns};
use serde_json::Value;

fn encode(value: impl serde::Serialize) -> Result<String, String> {
    serde_json::to_string(&value).map_err(|_| "Cannot encode ZNS result".into())
}

/// Derive a public Base identity after checking the seed against the wallet DB.
pub fn zns_account(
    db_path: String,
    network: String,
    account_uuid: String,
    secret_bytes: Vec<u8>,
) -> Result<String, String> {
    let secret = zeroize::Zeroizing::new(secret_bytes);
    encode(zns::account(
        &db_path,
        parse_network(&network)?,
        &account_uuid,
        secret.to_vec(),
    )?)
}

/// Build only a supported, policy-bounded ZNS operation. No arbitrary call API.
pub fn zns_prepare(
    network: String,
    config_json: String,
    owner: String,
    operation_json: String,
) -> Result<String, String> {
    let config = serde_json::from_str(&config_json).map_err(|_| "Invalid ZNS configuration")?;
    let operation = serde_json::from_str(&operation_json).map_err(|_| "Invalid ZNS operation")?;
    zns::validate_operation(parse_network(&network)?, &operation)?;
    encode(vizor_zns_core::prepare(&config, &owner, &operation)?)
}

/// Sign a supported ZNS intent using this software account's restored Base key.
pub fn zns_sign(
    db_path: String,
    network: String,
    account_uuid: String,
    secret_bytes: Vec<u8>,
    config_json: String,
    operation_json: String,
    transaction_json: String,
) -> Result<String, String> {
    let secret = zeroize::Zeroizing::new(secret_bytes);
    let config = serde_json::from_str(&config_json).map_err(|_| "Invalid ZNS configuration")?;
    let operation = serde_json::from_str(&operation_json).map_err(|_| "Invalid ZNS operation")?;
    let transaction =
        serde_json::from_str(&transaction_json).map_err(|_| "Invalid ZNS transaction")?;
    encode(zns::sign(
        &db_path,
        parse_network(&network)?,
        &account_uuid,
        secret.to_vec(),
        &config,
        &operation,
        &transaction,
    )?)
}

/// ZIP-316 decoding plus selected-network validation; transparent addresses fail.
pub fn zns_validate_unified_address(network: String, address: String) -> Result<bool, String> {
    Ok(zns::validate_unified_address(
        parse_network(&network)?,
        &address,
    ))
}

pub fn zns_read_call(method: String, args_json: String) -> Result<String, String> {
    let args: Value = serde_json::from_str(&args_json).map_err(|_| "Invalid ZNS read arguments")?;
    vizor_zns_core::abi::read_call(&method, &args)
}

pub fn zns_decode_result(method: String, data: String) -> Result<String, String> {
    encode(vizor_zns_core::abi::decode_result(&method, &data)?)
}

pub fn zns_random_secret() -> String {
    vizor_zns_core::random_secret()
}
