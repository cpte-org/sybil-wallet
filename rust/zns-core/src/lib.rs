//! Offline, intent-bounded ZNS signing. This crate never opens a network
//! connection, persists secrets, or accepts a generic `to + calldata` signer.
pub mod abi;
#[cfg(test)]
mod tests;
mod transaction;

use alloy_primitives::{Address, Bytes, B256, U256};
use alloy_sol_types::SolCall;
use bip32::XPrv;
use k256::ecdsa::SigningKey;
use serde::{Deserialize, Serialize};
pub use transaction::{sign, SignedTransaction, Transaction};
pub type Result<T> = std::result::Result<T, String>;

pub const CBZEC: &str = "0xB2000000000000000000008501b13360000cb2EC";
pub const KYBER: &str = "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5";
pub const PROTOCOL_ID: &str = "0x341e17a38bbce04892f4e0d0ff4a570669fb9e5addb830fd0bee83cd44ce0520";

pub fn address(value: &str) -> Result<Address> {
    value.parse().map_err(|_| "Invalid EVM address".into())
}
pub fn number(value: &str) -> Result<U256> {
    if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
        return Err("Amounts must be unsigned decimal integer strings".into());
    }
    value.parse().map_err(|_| "Amount exceeds uint256".into())
}
pub fn bytes(value: &str) -> Result<Vec<u8>> {
    hex::decode(value.strip_prefix("0x").ok_or("Hex must start with 0x")?)
        .map_err(|_| "Invalid hex".into())
}

pub fn validate_name(name: &str) -> Result<()> {
    if name.is_empty()
        || name.len() > 63
        || name.starts_with('-')
        || name.ends_with('-')
        || !name
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
    {
        return Err(
            "Use a lowercase ASCII label of 1–63 letters, digits or internal hyphens".into(),
        );
    }
    Ok(())
}
fn validate_registration(name: &str, ua: &str) -> Result<()> {
    validate_name(name)?;
    if ua.is_empty() || ua.len() > 512 {
        return Err("Invalid Unified Address length".into());
    }
    Ok(())
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Config {
    pub protocol_id: String,
    pub chain_id: u64,
    pub registry: String,
    pub token: String,
    pub router: Option<String>,
    pub delegate: Option<String>,
    #[serde(default)]
    pub allow_test_chain: bool,
    pub max_value_wei: String,
    pub max_gas_limit: String,
    pub max_fee_per_gas_wei: String,
    pub max_total_fee_wei: String,
    pub max_token_amount: String,
}
impl Config {
    pub fn validate(&self) -> Result<()> {
        if self
            .protocol_id
            .parse::<B256>()
            .map_err(|_| "Invalid ZNS protocol identifier")?
            != PROTOCOL_ID
                .parse::<B256>()
                .expect("fixed protocol identifier")
        {
            return Err("Unsupported ZNS economics or protocol identifier".into());
        }
        if self.chain_id != 8453
            && !(self.allow_test_chain && [84532, 31337].contains(&self.chain_id))
        {
            return Err("Only Base, or explicitly enabled test chains, are supported".into());
        }
        if address(&self.registry)? == Address::ZERO || address(&self.token)? == Address::ZERO {
            return Err("Registry and token must be configured".into());
        }
        if self.chain_id == 8453 && address(&self.token)? != address(CBZEC)? {
            return Err("Base mainnet requires canonical cbZEC".into());
        }
        if let Some(router) = &self.router {
            if address(router)? == Address::ZERO
                || (self.chain_id == 8453 && address(router)? != address(KYBER)?)
            {
                return Err("Unsupported swap router".into());
            }
        }
        if let Some(delegate) = &self.delegate {
            if address(delegate)? == Address::ZERO {
                return Err("Delegate cannot be zero".into());
            }
        }
        number(&self.max_value_wei)?;
        for limit in [
            &self.max_gas_limit,
            &self.max_fee_per_gas_wei,
            &self.max_total_fee_wei,
            &self.max_token_amount,
        ] {
            if number(limit)?.is_zero() {
                return Err("Signing limits must be positive".into());
            }
        }
        Ok(())
    }
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Swap {
    pub data: String,
    pub value: String,
    pub minimum_output: String,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum Operation {
    Commit {
        name: String,
        #[serde(rename = "unifiedAddress")]
        unified_address: String,
        secret: String,
    },
    Approve {
        amount: String,
    },
    Register {
        name: String,
        #[serde(rename = "unifiedAddress")]
        unified_address: String,
        secret: String,
        #[serde(rename = "maxDeposit")]
        max_deposit: String,
        #[serde(rename = "extraDeposit")]
        extra_deposit: String,
        #[serde(rename = "expectedPricingMode")]
        expected_pricing_mode: u8,
        deadline: String,
    },
    Refresh {
        #[serde(rename = "positionId")]
        position_id: String,
    },
    ClaimRewards {
        #[serde(rename = "positionId")]
        position_id: String,
    },
    Release {
        #[serde(rename = "positionId")]
        position_id: String,
    },
    Update {
        #[serde(rename = "positionId")]
        position_id: String,
        #[serde(rename = "unifiedAddress")]
        unified_address: String,
    },
    Transfer {
        #[serde(rename = "positionId")]
        position_id: String,
        recipient: String,
    },
    WithdrawClaims {},
    Swap {
        data: String,
        value: String,
        #[serde(rename = "minimumOutput")]
        minimum_output: String,
    },
    AtomicRegister {
        name: String,
        #[serde(rename = "unifiedAddress")]
        unified_address: String,
        secret: String,
        #[serde(rename = "maxDeposit")]
        max_deposit: String,
        #[serde(rename = "extraDeposit")]
        extra_deposit: String,
        #[serde(rename = "expectedPricingMode")]
        expected_pricing_mode: u8,
        amount: String,
        swap: Option<Swap>,
        deadline: String,
        #[serde(rename = "existingTokenUnits", default = "zero")]
        existing_token_units: String,
    },
}
fn zero() -> String {
    "0".into()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Prepared {
    pub to: String,
    pub value: String,
    pub data: String,
    pub commitment: Option<String>,
    pub authorization_required: bool,
}

pub fn prepare(config: &Config, owner: &str, operation: &Operation) -> Result<Prepared> {
    config.validate()?;
    let owner = address(owner)?;
    if owner == Address::ZERO {
        return Err("Owner cannot be zero".into());
    }
    let registry = address(&config.registry)?;
    let token = address(&config.token)?;
    let mut to = registry;
    let mut value = U256::ZERO;
    let mut commitment = None;
    let mut authorization_required = false;
    let parse_secret = |s: &str| -> Result<B256> {
        let secret = s.parse::<B256>().map_err(|_| "Secret must be 32 bytes")?;
        if secret == B256::ZERO {
            return Err("Secret cannot be zero".into());
        }
        Ok(secret)
    };
    let approval = |amount: &str| -> Result<Vec<u8>> {
        let amount = number(amount)?;
        if amount > number(&config.max_token_amount)? {
            return Err("Token approval exceeds reviewed limit".into());
        }
        Ok(abi::approveCall {
            spender: registry,
            amount,
        }
        .abi_encode())
    };
    let position = |id: &str| -> Result<U256> {
        let id = number(id)?;
        if id.is_zero() {
            return Err("Position id must be positive".into());
        }
        Ok(id)
    };
    // The offline signer binds a reviewed ceiling and pricing mode. The
    // registry recomputes the live minimum and enforces both at inclusion.
    let registration_limits = |max: &str, extra: &str, mode: u8, deadline: &str| {
        let max = number(max)?;
        let extra = number(extra)?;
        let deadline = number(deadline)?;
        if max.is_zero() || max > number(&config.max_token_amount)? {
            return Err("Registration deposit exceeds reviewed limit".to_string());
        }
        if extra >= max {
            return Err("Extra deposit must leave room for the minimum deposit".to_string());
        }
        if mode > 1 {
            return Err("Unsupported registration pricing mode".to_string());
        }
        if deadline.is_zero() {
            return Err("Registration deadline must be positive".to_string());
        }
        Ok((max, extra, deadline))
    };
    let data = match operation {
        Operation::Commit {
            name,
            unified_address,
            secret,
        } => {
            validate_registration(name, unified_address)?;
            let hash = abi::commitment(
                registry,
                config.chain_id,
                name,
                unified_address,
                owner,
                parse_secret(secret)?,
            );
            commitment = Some(hash.to_string());
            abi::commitCall { commitment: hash }.abi_encode()
        }
        Operation::Approve { amount } => {
            to = token;
            approval(amount)?
        }
        Operation::Register {
            name,
            unified_address,
            secret,
            max_deposit,
            extra_deposit,
            expected_pricing_mode,
            deadline,
        } => {
            validate_registration(name, unified_address)?;
            let (max, extra, deadline) =
                registration_limits(max_deposit, extra_deposit, *expected_pricing_mode, deadline)?;
            abi::registerCall {
                name: name.clone(),
                unifiedAddress: unified_address.clone(),
                secret: parse_secret(secret)?,
                maxDeposit: max,
                extraDeposit: extra,
                expectedPricingMode: *expected_pricing_mode,
                deadline,
            }
            .abi_encode()
        }
        Operation::Refresh { position_id } => abi::refreshCall {
            positionId: position(position_id)?,
        }
        .abi_encode(),
        Operation::ClaimRewards { position_id } => abi::claimRewardsCall {
            positionId: position(position_id)?,
        }
        .abi_encode(),
        Operation::Release { position_id } => abi::releaseCall {
            positionId: position(position_id)?,
        }
        .abi_encode(),
        Operation::Update {
            position_id,
            unified_address,
        } => {
            if unified_address.is_empty() || unified_address.len() > 512 {
                return Err("Invalid Unified Address length".into());
            }
            abi::setUnifiedAddressCall {
                positionId: position(position_id)?,
                unifiedAddress: unified_address.clone(),
            }
            .abi_encode()
        }
        Operation::Transfer {
            position_id,
            recipient,
        } => {
            let recipient = address(recipient)?;
            if recipient == Address::ZERO || recipient == owner || recipient == registry {
                return Err("Invalid NFT transfer recipient".into());
            }
            abi::safeTransferFromCall {
                from: owner,
                to: recipient,
                tokenId: position(position_id)?,
            }
            .abi_encode()
        }
        Operation::WithdrawClaims {} => abi::withdrawClaimsCall {}.abi_encode(),
        Operation::Swap {
            data,
            value: amount,
            minimum_output,
        } => {
            to = address(
                config
                    .router
                    .as_deref()
                    .ok_or("Swap router is not configured")?,
            )?;
            let data = abi::validate_swap(
                data,
                amount,
                minimum_output,
                owner,
                token,
                number(&config.max_value_wei)?,
            )?;
            validate_mainnet_executor(config.chain_id, &data)?;
            value = number(amount)?;
            data.to_vec()
        }
        Operation::AtomicRegister {
            name,
            unified_address,
            secret,
            max_deposit,
            extra_deposit,
            expected_pricing_mode,
            amount,
            swap,
            deadline,
            existing_token_units,
        } => {
            validate_registration(name, unified_address)?;
            let (max, extra, deadline) =
                registration_limits(max_deposit, extra_deposit, *expected_pricing_mode, deadline)?;
            if number(amount)? != max {
                return Err("Atomic approval must equal the reviewed deposit ceiling".into());
            }
            config
                .delegate
                .as_ref()
                .ok_or("Atomic registration delegate is not configured")?;
            let mut calls = Vec::new();
            if let Some(swap) = swap {
                let target = address(
                    config
                        .router
                        .as_deref()
                        .ok_or("Swap router is not configured")?,
                )?;
                let data = abi::validate_swap(
                    &swap.data,
                    &swap.value,
                    &swap.minimum_output,
                    owner,
                    token,
                    number(&config.max_value_wei)?,
                )?;
                validate_mainnet_executor(config.chain_id, &data)?;
                // Underfunded atomic attempts must fail before signing.
                let existing = number(existing_token_units)?;
                let required = number(amount)?;
                if existing > required
                    || number(&swap.minimum_output)?
                        .checked_add(existing)
                        .ok_or("Token amount overflow")?
                        < required
                {
                    return Err("Swap minimum plus existing cbZEC must cover the exact registration approval".into());
                }
                value = number(&swap.value)?;
                calls.push(abi::Execution {
                    target,
                    value,
                    data,
                });
            }
            calls.push(abi::Execution {
                target: token,
                value: U256::ZERO,
                data: Bytes::from(approval(amount)?),
            });
            calls.push(abi::Execution {
                target: registry,
                value: U256::ZERO,
                data: abi::registerCall {
                    name: name.clone(),
                    unifiedAddress: unified_address.clone(),
                    secret: parse_secret(secret)?,
                    maxDeposit: max,
                    extraDeposit: extra,
                    expectedPricingMode: *expected_pricing_mode,
                    deadline,
                }
                .abi_encode()
                .into(),
            });
            to = owner;
            // Funds already belong to the self-executing account. Forwarding
            // value to itself is unnecessary; calls spend its existing ETH.
            value = U256::ZERO;
            authorization_required = true;
            abi::executeCall { calls, deadline }.abi_encode()
        }
    };
    Ok(Prepared {
        to: to.to_checksum(None),
        value: value.to_string(),
        data: format!("0x{}", hex::encode(data)),
        commitment,
        authorization_required,
    })
}

fn validate_mainnet_executor(chain: u64, data: &[u8]) -> Result<()> {
    if chain == 8453 {
        let call = abi::swapCall::abi_decode(data, true).map_err(|_| "Invalid swap")?;
        if call.execution.callTarget != address("0x8f10b468b06c6fd214b65f87778827f7d113f996")? {
            return Err("Unsupported Base swap executor".into());
        }
    }
    Ok(())
}

/// Standard Ethereum account path. The ZIP32 account index comes from verified
/// wallet derivation metadata, never a UUID or a position in the UI account list.
pub fn derivation_path(account_index: u32) -> Result<String> {
    if account_index >= (1 << 31) {
        return Err("Account index is outside the hardened BIP32 range".into());
    }
    Ok(format!("m/44'/60'/{account_index}'/0/0"))
}

pub fn derive_key(seed: &[u8], account_index: u32) -> Result<SigningKey> {
    let path = derivation_path(account_index)?
        .parse()
        .map_err(|_| "Invalid derivation path")?;
    let key = XPrv::derive_from_path(seed, &path).map_err(|_| "Base account derivation failed")?;
    Ok(key.private_key().clone())
}

pub fn key_address(key: &SigningKey) -> Address {
    let public = key.verifying_key().to_encoded_point(false);
    let hash = alloy_primitives::keccak256(&public.as_bytes()[1..]);
    Address::from_slice(&hash[12..])
}

pub fn random_secret() -> String {
    use rand::RngCore;
    let mut secret = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut secret);
    format!("0x{}", hex::encode(secret))
}
