use crate::{address, bytes, key_address, number, prepare, Config, Operation, Result};
use alloy_primitives::{keccak256, Address, U256};
use k256::ecdsa::{Signature, SigningKey};
use rlp::RlpStream;
use serde::{Deserialize, Serialize};

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Transaction {
    pub nonce: String,
    pub gas_limit: String,
    pub max_fee_per_gas: String,
    pub max_priority_fee_per_gas: String,
    /// Estimate only: Base L1 publication fees are not constrained by the
    /// EIP-1559 gasLimit or maxFeePerGas transaction fields.
    #[serde(default = "zero")]
    pub l1_fee_wei: String,
}
fn zero() -> String {
    "0".into()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SignedTransaction {
    pub raw_transaction: String,
    pub transaction_hash: String,
    pub from: String,
    pub transaction_type: u8,
    pub l1_fee_estimate_wei: String,
    pub maximum_execution_fee_wei: String,
    pub authorization_nonce: Option<String>,
}

pub(crate) fn append_number(stream: &mut RlpStream, number: U256) {
    let bytes = number.to_be_bytes::<32>();
    let first = bytes.iter().position(|b| *b != 0).unwrap_or(32);
    stream.append(&&bytes[first..]);
}

fn append_signature(stream: &mut RlpStream, signature: &Signature, parity: u8) {
    append_number(stream, U256::from(parity));
    append_number(stream, U256::from_be_slice(&signature.r().to_bytes()));
    append_number(stream, U256::from_be_slice(&signature.s().to_bytes()));
}

pub(crate) fn authorization(
    key: &SigningKey,
    chain_id: u64,
    delegate: Address,
    nonce: u64,
) -> Result<Vec<u8>> {
    let mut unsigned = RlpStream::new_list(3);
    append_number(&mut unsigned, U256::from(chain_id));
    unsigned.append(&delegate.as_slice());
    append_number(&mut unsigned, U256::from(nonce));
    let mut payload = vec![0x05];
    payload.extend_from_slice(&unsigned.out());
    let (signature, id) = key
        .sign_prehash_recoverable(keccak256(payload).as_slice())
        .map_err(|_| "Authorization signing failed")?;
    if id.to_byte() > 1 {
        return Err("Unsupported Ethereum recovery identifier".into());
    }
    let mut signed = RlpStream::new_list(6);
    append_number(&mut signed, U256::from(chain_id));
    signed.append(&delegate.as_slice());
    append_number(&mut signed, U256::from(nonce));
    append_signature(&mut signed, &signature, id.to_byte());
    Ok(signed.out().to_vec())
}

pub fn sign(
    key: &SigningKey,
    config: &Config,
    operation: &Operation,
    transaction: &Transaction,
) -> Result<SignedTransaction> {
    let owner = key_address(key);
    let prepared = prepare(config, &owner.to_checksum(None), operation)?;
    let nonce: u64 = transaction
        .nonce
        .parse()
        .map_err(|_| "Nonce must fit uint64")?;
    if nonce == u64::MAX {
        return Err("Nonce exhausted".into());
    }
    let gas = number(&transaction.gas_limit)?;
    let max_fee = number(&transaction.max_fee_per_gas)?;
    let priority = number(&transaction.max_priority_fee_per_gas)?;
    let l1_fee = number(&transaction.l1_fee_wei)?;
    if gas.is_zero()
        || gas > number(&config.max_gas_limit)?
        || max_fee.is_zero()
        || max_fee > number(&config.max_fee_per_gas_wei)?
        || priority > max_fee
    {
        return Err("Transaction gas or fee exceeds the reviewed limit".into());
    }
    let execution_fee = gas.checked_mul(max_fee).ok_or("Gas fee overflow")?;
    if execution_fee
        .checked_add(l1_fee)
        .ok_or("Total fee overflow")?
        > number(&config.max_total_fee_wei)?
    {
        return Err("Estimated total Base fee exceeds the reviewed limit".into());
    }
    let auth_nonce = if prepared.authorization_required {
        Some(
            nonce
                .checked_add(1)
                .filter(|n| *n < u64::MAX)
                .ok_or("Authorization nonce exhausted")?,
        )
    } else {
        None
    };
    let auth = auth_nonce
        .map(|nonce| {
            authorization(
                key,
                config.chain_id,
                address(config.delegate.as_deref().ok_or("Missing delegate")?)?,
                nonce,
            )
        })
        .transpose()?;
    let tx_type = if auth.is_some() { 4 } else { 2 };
    let to = address(&prepared.to)?;
    let value = number(&prepared.value)?;
    let data = bytes(&prepared.data)?;
    let fields = |stream: &mut RlpStream| {
        append_number(stream, U256::from(config.chain_id));
        append_number(stream, U256::from(nonce));
        append_number(stream, priority);
        append_number(stream, max_fee);
        append_number(stream, gas);
        stream.append(&to.as_slice());
        append_number(stream, value);
        stream.append(&data.as_slice());
        stream.begin_list(0); // No caller-controlled access list.
        if let Some(auth) = &auth {
            stream.begin_list(1);
            stream.append_raw(auth, 1);
        }
    };
    let count = if auth.is_some() { 10 } else { 9 };
    let mut unsigned = RlpStream::new_list(count);
    fields(&mut unsigned);
    let mut payload = vec![tx_type];
    payload.extend_from_slice(&unsigned.out());
    let digest = keccak256(payload);
    let (signature, recovery_id) = key
        .sign_prehash_recoverable(digest.as_slice())
        .map_err(|_| "Transaction signing failed")?;
    if recovery_id.to_byte() > 1 {
        return Err("Unsupported Ethereum recovery identifier".into());
    }
    let mut signed = RlpStream::new_list(count + 3);
    fields(&mut signed);
    append_signature(&mut signed, &signature, recovery_id.to_byte());
    let mut raw = vec![tx_type];
    raw.extend_from_slice(&signed.out());
    Ok(SignedTransaction {
        transaction_hash: keccak256(&raw).to_string(),
        raw_transaction: format!("0x{}", hex::encode(raw)),
        from: owner.to_checksum(None),
        transaction_type: tx_type,
        l1_fee_estimate_wei: l1_fee.to_string(),
        maximum_execution_fee_wei: execution_fee.to_string(),
        authorization_nonce: auth_nonce.map(|v| v.to_string()),
    })
}
