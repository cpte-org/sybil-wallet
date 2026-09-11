//! Reviewed introduction wire codec. Verification returns a candidate only;
//! accepted-contact lookup, consent, fresh allocation, cancellation, consumption,
//! retired-key checks and transactional persistence belong to the caller.
//! Adapted from research/2026-09-10/zcash-contacts/intro-protocol/WIRE.md.

use super::{array, canonical_json, fixed, identity, integer, key_identity, verify_signature};
use super::{Network, MAX_SAFE_INTEGER};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use ed25519_dalek::{Signer, SigningKey};
use rand_core::{OsRng, RngCore};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

const ERROR: &str = "Invalid or expired contact introduction.";
// Invitation lifetime is separate from the wallet's short-lived final address
// challenge. Legacy requests retain their original 15-minute lifetime.
const INVITATION_TTL: u64 = 30 * 24 * 60 * 60;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Verified {
    pub packet_json: String,
    pub request_json: String,
    pub request_hash: String,
    pub endpoint_hash: Option<String>,
    pub endorsement_hash: Option<String>,
    pub expires_at: u64,
    pub offer_json: Option<String>,
    pub endpoint_json: Option<String>,
    pub identity: Option<String>,
    pub address: Option<String>,
    pub sequence: Option<u64>,
    pub suggestion: Option<String>,
}

/// The key names are directional: K_AB is Alice's signing identity for Bob,
/// and K_BA is Bob's signing identity for Alice. Only E is self-signed.
#[derive(Clone, Copy)]
pub enum Role {
    Ask,
    Offer,
    Consent,
    Delivery,
}

fn canonical(input: &str) -> Option<Value> {
    input.is_ascii().then_some(())?;
    canonical_json(input.as_bytes())
}

fn digest(value: &Value) -> Value {
    json!(URL_SAFE_NO_PAD.encode(Sha256::digest(
        json!(["zcash-contact/intro-digest", value])
            .to_string()
            .as_bytes()
    )))
}

fn request(value: &Value, network: Network, now: u64) -> Option<Value> {
    let r = array(value, 5)?;
    fixed::<32>(r[2].as_str()?)?;
    let issued = integer(&r[3])?;
    let expires = integer(&r[4])?;
    let ttl = match r[0].as_str()? {
        "zcash-contact/intro-request" => 900,
        "zcash-contact/intro-invitation" => INVITATION_TTL,
        _ => return None,
    };
    (now <= MAX_SAFE_INTEGER
        && r[1] == network.wire_name()
        && expires == issued.checked_add(ttl)?
        && issued <= now
        && now < expires)
        .then_some(digest(value))
}

fn paired(peer: &str, own: &str) -> Option<()> {
    identity(peer)?;
    identity(own)?;
    (peer != own).then_some(())
}

fn suggestion(value: &Value) -> Option<&str> {
    let s = value.as_str()?;
    (!s.is_empty()
        && s.len() <= 20
        && !s.starts_with(' ')
        && !s.ends_with(' ')
        && s.bytes().all(|b| (0x20..=0x7e).contains(&b)))
    .then_some(s)
}

struct Envelope {
    payload: Vec<u8>,
    fields: Value,
    signature: [u8; 64],
}

impl Envelope {
    fn parse(value: &Value) -> Option<Self> {
        let a = array(value, 2)?;
        let payload = super::decode(a[0].as_str()?)?;
        let fields = canonical(std::str::from_utf8(&payload).ok()?)?;
        let signature = fixed(a[1].as_str()?)?;
        Some(Self {
            payload,
            fields,
            signature,
        })
    }

    fn verify(&self, signer: &str) -> Option<()> {
        verify_signature(&identity(signer)?, &self.payload, &self.signature)
    }
}

fn offer(value: &Value, hash: &Value, signer: &str, recipient: &str) -> Option<String> {
    let envelope = Envelope::parse(value)?;
    let o = array(&envelope.fields, 4)?;
    (o[0] == "zcash-contact/intro-offer" && &o[1] == hash && o[2] == recipient).then_some(())?;
    let suggestion = suggestion(&o[3])?.to_owned();
    envelope.verify(signer)?;
    Some(suggestion)
}

fn endpoint(
    value: &Value,
    hash: &Value,
    network: Network,
    peer: &str,
    own: &str,
    validate_ua: &impl Fn(Network, &str) -> bool,
) -> Option<(String, String)> {
    let envelope = Envelope::parse(value)?;
    let e = array(&envelope.fields, 6)?;
    (e[0] == "zcash-contact/intro-endpoint"
        && e[1] == network.wire_name()
        && &e[2] == hash
        && integer(&e[4])? == 1
        && e[3] != peer
        && e[3] != own)
        .then_some(())?;
    let subject = e[3].as_str()?;
    envelope.verify(subject)?;
    let address = e[5].as_str()?;
    // All wire strings, including this address, were already checked as ASCII.
    super::valid_address(network, address, validate_ua)?;
    Some((subject.to_owned(), address.to_owned()))
}

/// `accepted_peer` and `paired_own` must come from the current accepted contact,
/// never from the packet. For consent, saved R and O come from Alice's persisted
/// outstanding offer; for delivery, saved R comes from Carol's pending ask.
/// This pure function cannot establish that caller-owned state is current.
pub fn verify(
    role: Role,
    network: Network,
    accepted_peer: &str,
    paired_own: &str,
    saved_request_json: Option<&str>,
    saved_offer_json: Option<&str>,
    packet_json: &str,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Result<Verified, &'static str> {
    verify_inner(
        role,
        network,
        accepted_peer,
        paired_own,
        saved_request_json,
        saved_offer_json,
        packet_json,
        now,
        &validate_ua,
    )
    .ok_or(ERROR)
}

fn verify_inner(
    role: Role,
    network: Network,
    peer: &str,
    own: &str,
    saved_request_json: Option<&str>,
    saved_offer_json: Option<&str>,
    packet_json: &str,
    now: u64,
    validate_ua: &impl Fn(Network, &str) -> bool,
) -> Option<Verified> {
    paired(peer, own)?;
    let packet = canonical(packet_json)?;
    let (domain, count) = match role {
        Role::Ask => ("zcash-contact/intro-ask-package", 3),
        Role::Offer => ("zcash-contact/intro-offer-package", 3),
        Role::Consent => ("zcash-contact/intro-consent-package", 4),
        Role::Delivery => ("zcash-contact/intro-delivery", 4),
    };
    let p = array(&packet, count)?;
    (p[0] == domain).then_some(())?;
    let hash = request(&p[1], network, now)?;
    let mut result = Verified {
        packet_json: packet_json.to_owned(),
        request_json: p[1].to_string(),
        request_hash: hash.as_str()?.to_owned(),
        endpoint_hash: None,
        endorsement_hash: None,
        expires_at: integer(&p[1][4])?,
        offer_json: None,
        endpoint_json: None,
        identity: None,
        address: None,
        sequence: None,
        suggestion: None,
    };
    match role {
        Role::Ask => {
            (saved_request_json.is_none() && saved_offer_json.is_none()).then_some(())?;
            let envelope = Envelope::parse(&p[2])?;
            let c = array(&envelope.fields, 3)?;
            (c[0] == "zcash-contact/intro-ask" && c[1] == hash && c[2] == own).then_some(())?;
            envelope.verify(peer)?;
        }
        Role::Offer => {
            (saved_request_json.is_none() && saved_offer_json.is_none()).then_some(())?;
            result.suggestion = Some(offer(&p[2], &hash, peer, own)?);
            result.offer_json = Some(p[2].to_string());
        }
        Role::Consent | Role::Delivery => {
            (canonical(saved_request_json?)? == p[1]).then_some(())?;
            if let Role::Consent = role {
                let saved_offer = canonical(saved_offer_json?)?;
                offer(&saved_offer, &hash, own, peer)?;
                let envelope = Envelope::parse(&p[3])?;
                let b = array(&envelope.fields, 4)?;
                (b[0] == "zcash-contact/intro-consent"
                    && b[1] == hash
                    && b[2] == digest(&saved_offer)
                    && b[3] == digest(&p[2]))
                .then_some(())?;
                envelope.verify(peer)?;
                result.offer_json = Some(saved_offer.to_string());
            } else {
                saved_offer_json.is_none().then_some(())?;
                let envelope = Envelope::parse(&p[3])?;
                let a = array(&envelope.fields, 5)?;
                (a[0] == "zcash-contact/intro-endorsement"
                    && a[1] == network.wire_name()
                    && a[2] == hash
                    && a[3] == digest(&p[2]))
                .then_some(())?;
                result.suggestion = Some(suggestion(&a[4])?.to_owned());
                envelope.verify(peer)?;
                result.endorsement_hash = Some(digest(&p[3]).as_str()?.to_owned());
            }
            let (subject, address) = endpoint(&p[2], &hash, network, peer, own, validate_ua)?;
            result.identity = Some(subject);
            result.address = Some(address);
            result.sequence = Some(1);
            result.endpoint_json = Some(p[2].to_string());
            result.endpoint_hash = Some(digest(&p[2]).as_str()?.to_owned());
        }
    }
    Some(result)
}

fn signing_key(secret: &[u8]) -> Result<SigningKey, &'static str> {
    let mut seed = Zeroizing::new([0; 32]);
    if secret.len() != seed.len() {
        return Err("Invalid contact signing key.");
    }
    seed.copy_from_slice(secret);
    // Dalek's enabled zeroize feature erases the returned key on all exits.
    Ok(SigningKey::from_bytes(&seed))
}

/// Confirms a caller-pinned accepted pair and its locally stored dedicated seed.
/// No packet, signature creation, wallet key or address is involved.
pub fn validate_association(
    incoming_identity: &str,
    own_identity: &str,
    own_secret_key: &[u8],
) -> Result<bool, &'static str> {
    let key = signing_key(own_secret_key)?;
    Ok(paired(incoming_identity, own_identity).is_some() && key_identity(&key) == own_identity)
}

fn signed(payload: Value, key: &SigningKey) -> Value {
    let bytes = payload.to_string();
    json!([
        URL_SAFE_NO_PAD.encode(bytes.as_bytes()),
        URL_SAFE_NO_PAD.encode(key.sign(bytes.as_bytes()).to_bytes())
    ])
}

/// All builders zeroize local key copies. The caller must erase input buffers.
pub fn create_ask(
    network: Network,
    peer_ac_identity: &str,
    secret_ca_key: &[u8],
    now: u64,
) -> Result<Verified, &'static str> {
    let key = signing_key(secret_ca_key)?;
    let own_ca_identity = key_identity(&key);
    paired(peer_ac_identity, &own_ca_identity).ok_or(ERROR)?;
    let expires = now
        .checked_add(INVITATION_TTL)
        .filter(|v| *v <= MAX_SAFE_INTEGER)
        .ok_or(ERROR)?;
    let mut sid = [0; 32];
    OsRng
        .try_fill_bytes(&mut sid)
        .map_err(|_| "Contact randomness is unavailable.")?;
    let r = json!([
        "zcash-contact/intro-invitation",
        network.wire_name(),
        URL_SAFE_NO_PAD.encode(sid),
        now,
        expires
    ]);
    let c = signed(
        json!(["zcash-contact/intro-ask", digest(&r), peer_ac_identity]),
        &key,
    );
    let packet = json!(["zcash-contact/intro-ask-package", r, c]).to_string();
    verify(
        Role::Ask,
        network,
        &own_ca_identity,
        peer_ac_identity,
        None,
        None,
        &packet,
        now,
        |_, _| false,
    )
}

/// Call only after the coordinator validates the ask, checks current accepted
/// contacts and records the exact request/role associations for this session.
pub fn create_offer(
    network: Network,
    request_json: &str,
    peer_ba_identity: &str,
    secret_ab_key: &[u8],
    suggested_recipient: &str,
    now: u64,
) -> Result<Verified, &'static str> {
    let key = signing_key(secret_ab_key)?;
    let own_ab_identity = key_identity(&key);
    paired(peer_ba_identity, &own_ab_identity).ok_or(ERROR)?;
    let r = canonical(request_json).ok_or(ERROR)?;
    let hash = request(&r, network, now).ok_or(ERROR)?;
    suggestion(&json!(suggested_recipient)).ok_or(ERROR)?;
    let o = signed(
        json!([
            "zcash-contact/intro-offer",
            hash,
            peer_ba_identity,
            suggested_recipient
        ]),
        &key,
    );
    let packet = json!(["zcash-contact/intro-offer-package", r, o]).to_string();
    verify(
        Role::Offer,
        network,
        &own_ab_identity,
        peer_ba_identity,
        None,
        None,
        &packet,
        now,
        |_, _| false,
    )
}

/// The fresh key/address must be independently allocated and checked against
/// all caller-known current and retired relationships before explicit consent.
pub fn create_consent(
    network: Network,
    peer_ab_identity: &str,
    secret_ba_key: &[u8],
    fresh_secret_bc_key: &[u8],
    fresh_address: &str,
    offer_packet_json: &str,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Result<Verified, &'static str> {
    let ba = signing_key(secret_ba_key)?;
    let bc = signing_key(fresh_secret_bc_key)?;
    let own_ba_identity = key_identity(&ba);
    let verified = verify(
        Role::Offer,
        network,
        peer_ab_identity,
        &own_ba_identity,
        None,
        None,
        offer_packet_json,
        now,
        &validate_ua,
    )?;
    let r = canonical(&verified.request_json).ok_or(ERROR)?;
    let offer_json = verified.offer_json.as_deref().ok_or(ERROR)?;
    let o = canonical(offer_json).ok_or(ERROR)?;
    let e = signed(
        json!([
            "zcash-contact/intro-endpoint",
            network.wire_name(),
            verified.request_hash,
            key_identity(&bc),
            1,
            fresh_address
        ]),
        &bc,
    );
    // Validate E before signing B so malformed/reused endpoints get no consent.
    endpoint(
        &e,
        &digest(&r),
        network,
        peer_ab_identity,
        &own_ba_identity,
        &validate_ua,
    )
    .ok_or(ERROR)?;
    let b = signed(
        json!([
            "zcash-contact/intro-consent",
            digest(&r),
            digest(&o),
            digest(&e)
        ]),
        &ba,
    );
    let packet = json!(["zcash-contact/intro-consent-package", r, e, b]).to_string();
    verify(
        Role::Consent,
        network,
        &own_ba_identity,
        peer_ab_identity,
        Some(&verified.request_json),
        Some(offer_json),
        &packet,
        now,
        validate_ua,
    )
}

pub fn create_delivery(
    network: Network,
    peer_ba_identity: &str,
    own_ab_identity: &str,
    peer_ca_identity: &str,
    secret_ac_key: &[u8],
    saved_request_json: &str,
    saved_offer_json: &str,
    consent_packet_json: &str,
    suggested_contact: &str,
    now: u64,
    validate_ua: impl Fn(Network, &str) -> bool,
) -> Result<Verified, &'static str> {
    let ac = signing_key(secret_ac_key)?;
    let own_ac_identity = key_identity(&ac);
    paired(peer_ca_identity, &own_ac_identity).ok_or(ERROR)?;
    let verified = verify(
        Role::Consent,
        network,
        peer_ba_identity,
        own_ab_identity,
        Some(saved_request_json),
        Some(saved_offer_json),
        consent_packet_json,
        now,
        &validate_ua,
    )?;
    suggestion(&json!(suggested_contact)).ok_or(ERROR)?;
    let r = canonical(&verified.request_json).ok_or(ERROR)?;
    let e = canonical(verified.endpoint_json.as_deref().ok_or(ERROR)?).ok_or(ERROR)?;
    endpoint(
        &e,
        &digest(&r),
        network,
        peer_ca_identity,
        &own_ac_identity,
        &validate_ua,
    )
    .ok_or(ERROR)?;
    let a = signed(
        json!([
            "zcash-contact/intro-endorsement",
            network.wire_name(),
            digest(&r),
            digest(&e),
            suggested_contact
        ]),
        &ac,
    );
    let packet = json!(["zcash-contact/intro-delivery", r, e, a]).to_string();
    verify(
        Role::Delivery,
        network,
        &own_ac_identity,
        peer_ca_identity,
        Some(saved_request_json),
        None,
        &packet,
        now,
        validate_ua,
    )
}

#[cfg(test)]
mod tests;
