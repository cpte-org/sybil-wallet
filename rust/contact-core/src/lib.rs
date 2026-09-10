//! Experimental, contact-only direct exchange. No wallet authority or storage.
//! Strict signature/encoding profile adapted from the research interop-rust
//! verifier; see README.md for provenance and caller responsibilities.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use curve25519_dalek::{edwards::CompressedEdwardsY, scalar::Scalar, traits::IsIdentity};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use rand_core::{OsRng, RngCore};
use serde_json::{json, Value};
use zeroize::Zeroizing;

pub mod introduction;

pub const MAX_INPUT_BYTES: usize = 32_768;
pub const MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;
const MAX_ENCODED_BYTES: usize = 12_000;
const REQUEST_DOMAIN: &str = "zcash-contact/request";
const ENDPOINT_DOMAIN: &str = "zcash-contact/endpoint";
const EXCHANGE_DOMAIN: &str = "zcash-contact/exchange";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Network {
    Test,
    Regtest,
}

impl Network {
    pub fn from_api_name(value: &str) -> Result<Self, &'static str> {
        match value {
            "test" => Ok(Self::Test),
            "regtest" => Ok(Self::Regtest),
            _ => Err("Contacts are available only on testnet and regtest."),
        }
    }

    pub fn wire_name(self) -> &'static str {
        match self {
            Self::Test => "zcash-testnet",
            Self::Regtest => "zcash-regtest",
        }
    }
}

pub struct Identity {
    pub identity: String,
    /// Dedicated relationship seed, to be encrypted by the unlocked caller.
    /// This is the only intentional secret export; never serialize or log it.
    pub secret_key: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Request {
    pub request_json: String,
    pub audience: String,
    pub challenge: String,
    pub expires_at: u64,
    pub subject_identity: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Endpoint {
    pub identity: String,
    pub address: String,
    pub sequence: u64,
    pub expires_at: u64,
    pub network: String,
}

fn new_seed() -> Result<Zeroizing<[u8; 32]>, &'static str> {
    let mut seed = Zeroizing::new([0u8; 32]);
    OsRng
        .try_fill_bytes(seed.as_mut())
        .map_err(|_| "Contact randomness is unavailable.")?;
    Ok(seed)
}

fn key_identity(key: &SigningKey) -> String {
    format!(
        "ed25519:{}",
        URL_SAFE_NO_PAD.encode(key.verifying_key().as_bytes())
    )
}

pub fn create_identity() -> Result<Identity, &'static str> {
    let seed = new_seed()?;
    let key = SigningKey::from_bytes(&seed);
    Ok(Identity {
        identity: key_identity(&key),
        secret_key: seed.to_vec(),
    })
}

pub fn create_request(
    network: Network,
    subject_identity: Option<&str>,
    now: u64,
) -> Result<Request, &'static str> {
    let expires_at = future_limit(now).ok_or("Invalid contact request time.")?;
    if let Some(subject) = subject_identity {
        identity(subject).ok_or("Invalid contact identity.")?;
    }
    // A request needs only its public audience. Its independent seed is dropped
    // here, and cannot become persistent signing authority or wallet authority.
    let seed = new_seed()?;
    let key = SigningKey::from_bytes(&seed);
    let audience = key_identity(&key);
    let mut nonce = [0u8; 32];
    OsRng
        .try_fill_bytes(&mut nonce)
        .map_err(|_| "Contact randomness is unavailable.")?;
    let challenge = URL_SAFE_NO_PAD.encode(nonce);
    let request_json = json!([
        REQUEST_DOMAIN,
        network.wire_name(),
        audience,
        challenge,
        expires_at,
        subject_identity,
    ])
    .to_string();
    inspect_request(network, &request_json, now)
}

pub fn inspect_request(
    network: Network,
    request_json: &str,
    now: u64,
) -> Result<Request, &'static str> {
    parse_request(network, request_json, now).ok_or("Invalid or expired contact request.")
}

fn parse_request(network: Network, input: &str, now: u64) -> Option<Request> {
    let fields = canonical_json(input.as_bytes())?;
    let request = array(&fields, 6)?;
    if request[0].as_str()? != REQUEST_DOMAIN || request[1].as_str()? != network.wire_name() {
        return None;
    }
    let audience = request[2].as_str()?;
    identity(audience)?;
    let challenge = request[3].as_str()?;
    fixed::<32>(challenge)?;
    let expires_at = integer(&request[4])?;
    if now >= expires_at || expires_at > future_limit(now)? {
        return None;
    }
    let subject_identity = if request[5].is_null() {
        None
    } else {
        let subject = request[5].as_str()?;
        identity(subject)?;
        Some(subject.to_owned())
    };
    Some(Request {
        request_json: input.to_owned(),
        audience: audience.to_owned(),
        challenge: challenge.to_owned(),
        expires_at,
        subject_identity,
    })
}

/// The caller must zeroize its input buffer. This function zeroizes its local
/// seed copy and Dalek's signing key on every exit.
pub fn sign_response(
    network: Network,
    request_json: &str,
    secret_key: &[u8],
    address: &str,
    sequence: u64,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Result<String, &'static str> {
    let mut seed = Zeroizing::new([0u8; 32]);
    if secret_key.len() != seed.len() {
        return Err("Invalid contact signing key.");
    }
    seed.copy_from_slice(secret_key);
    let key = SigningKey::from_bytes(&seed);
    let request = inspect_request(network, request_json, now)?;
    let subject = key_identity(&key);
    if request
        .subject_identity
        .as_ref()
        .is_some_and(|expected| expected != &subject)
    {
        return Err("Contact request expects a different identity.");
    }
    if !(1..=MAX_SAFE_INTEGER).contains(&sequence) {
        return Err("Invalid contact revision.");
    }
    valid_address(network, address, &validate_ua).ok_or("Invalid contact receiving address.")?;
    let expiry = request
        .expires_at
        .min(future_limit(now).ok_or("Invalid contact time.")?);
    let payload = json!([
        ENDPOINT_DOMAIN,
        network.wire_name(),
        subject,
        request.audience,
        request.challenge,
        sequence,
        now,
        expiry,
        address,
    ])
    .to_string();
    let signature = key.sign(payload.as_bytes()).to_bytes();
    verify_signature(
        key.verifying_key().as_bytes(),
        payload.as_bytes(),
        &signature,
    )
    .ok_or("Unable to sign the contact response.")?;
    Ok(json!([
        EXCHANGE_DOMAIN,
        [
            URL_SAFE_NO_PAD.encode(payload.as_bytes()),
            URL_SAFE_NO_PAD.encode(signature)
        ],
        null,
    ])
    .to_string())
}

pub fn verify_response(
    network: Network,
    request_json: &str,
    exchange_json: &str,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Result<Endpoint, &'static str> {
    verify_endpoint(network, request_json, exchange_json, now, validate_ua)
        .ok_or("Invalid or expired contact response.")
}

fn verify_endpoint(
    network: Network,
    request_json: &str,
    exchange_json: &str,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Option<Endpoint> {
    let request = parse_request(network, request_json, now)?;
    let fields = canonical_json(exchange_json.as_bytes())?;
    let exchange = array(&fields, 3)?;
    if exchange[0].as_str()? != EXCHANGE_DOMAIN || !exchange[2].is_null() {
        return None;
    }
    let envelope = array(&exchange[1], 2)?;
    let payload = decode(envelope[0].as_str()?)?;
    let signature = fixed::<64>(envelope[1].as_str()?)?;
    let fields = canonical_json(&payload)?;
    let endpoint = array(&fields, 9)?;
    if endpoint[0].as_str()? != ENDPOINT_DOMAIN
        || endpoint[1].as_str()? != network.wire_name()
        || endpoint[3].as_str()? != request.audience
        || endpoint[4].as_str()? != request.challenge
    {
        return None;
    }
    let subject = endpoint[2].as_str()?;
    let subject_key = identity(subject)?;
    if request
        .subject_identity
        .as_deref()
        .is_some_and(|expected| expected != subject)
    {
        return None;
    }
    let sequence = integer(&endpoint[5])?;
    if sequence == 0 {
        return None;
    }
    let issued_at = integer(&endpoint[6])?;
    let expires_at = integer(&endpoint[7])?;
    if !(1..=300).contains(&expires_at.checked_sub(issued_at)?)
        || issued_at > now.checked_add(30)?
        || now >= expires_at
        || expires_at > request.expires_at
    {
        return None;
    }
    let address = endpoint[8].as_str()?;
    valid_address(network, address, &validate_ua)?;
    verify_signature(&subject_key, &payload, &signature)?;
    Some(Endpoint {
        identity: subject.to_owned(),
        address: address.to_owned(),
        sequence,
        expires_at,
        network: network.wire_name().to_owned(),
    })
}

fn valid_address(
    network: Network,
    address: &str,
    validate: impl Fn(Network, &str) -> bool,
) -> Option<()> {
    (!address.is_empty()
        && address.len() <= 512
        && address.trim() == address
        && validate(network, address))
    .then_some(())
}

fn future_limit(now: u64) -> Option<u64> {
    now.checked_add(300)
        .filter(|limit| *limit <= MAX_SAFE_INTEGER)
}

fn canonical_json(bytes: &[u8]) -> Option<Value> {
    if bytes.len() > MAX_INPUT_BYTES {
        return None;
    }
    let value: Value = serde_json::from_slice(bytes).ok()?;
    (serde_json::to_vec(&value).ok()? == bytes).then_some(value)
}

fn array(value: &Value, length: usize) -> Option<&[Value]> {
    let values = value.as_array()?;
    (values.len() == length).then_some(values.as_slice())
}

fn integer(value: &Value) -> Option<u64> {
    value.as_u64().filter(|n| *n <= MAX_SAFE_INTEGER)
}

fn decode(encoded: &str) -> Option<Vec<u8>> {
    if encoded.is_empty()
        || encoded.len() > MAX_ENCODED_BYTES
        || !encoded
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    {
        return None;
    }
    let bytes = URL_SAFE_NO_PAD.decode(encoded).ok()?;
    (URL_SAFE_NO_PAD.encode(&bytes) == encoded).then_some(bytes)
}

fn fixed<const N: usize>(encoded: &str) -> Option<[u8; N]> {
    decode(encoded)?.try_into().ok()
}

fn identity(value: &str) -> Option<[u8; 32]> {
    let key = fixed(value.strip_prefix("ed25519:")?)?;
    profile_point(&key)?;
    Some(key)
}

fn profile_point(bytes: &[u8; 32]) -> Option<()> {
    let point = CompressedEdwardsY(*bytes).decompress()?;
    if point.compress().as_bytes() != bytes || point.is_identity() || !point.is_torsion_free() {
        return None;
    }
    Some(())
}

fn verify_signature(key: &[u8; 32], message: &[u8], signature: &[u8; 64]) -> Option<()> {
    profile_point(key)?;
    profile_point(&signature[..32].try_into().ok()?)?;
    if !bool::from(Scalar::from_canonical_bytes(signature[32..].try_into().ok()?).is_some()) {
        return None;
    }
    VerifyingKey::from_bytes(key)
        .ok()?
        .verify_strict(message, &Signature::from_bytes(signature))
        .ok()
}

#[cfg(test)]
mod tests;
