//! Contact exchange codecs. Never uses wallet seeds or viewing keys.

use crate::wallet::contacts::validate_unified_address;
use vizor_contact_core as core;
use zeroize::Zeroizing;

pub struct ContactIdentityResult {
    pub identity: String,
    pub secret_key: Vec<u8>,
}

pub struct ContactRequestResult {
    pub request_json: String,
    pub audience: String,
    pub challenge: String,
    pub expires_at: u64,
    pub subject_identity: Option<String>,
}

pub struct ContactEndpointResult {
    pub identity: String,
    pub address: String,
    pub sequence: u64,
    pub expires_at: u64,
    pub network: String,
}

impl From<core::Request> for ContactRequestResult {
    fn from(request: core::Request) -> Self {
        Self {
            request_json: request.request_json,
            audience: request.audience,
            challenge: request.challenge,
            expires_at: request.expires_at,
            subject_identity: request.subject_identity,
        }
    }
}

pub fn contacts_create_identity() -> Result<ContactIdentityResult, String> {
    let identity = core::create_identity()?;
    Ok(ContactIdentityResult {
        identity: identity.identity,
        secret_key: identity.secret_key,
    })
}

pub fn contacts_validate_unified_address(network: String, address: String) -> Result<bool, String> {
    Ok(validate_unified_address(
        core::Network::from_api_name(&network)?,
        &address,
    ))
}

pub fn contacts_create_request(
    network: String,
    subject_identity: Option<String>,
    now: u64,
) -> Result<ContactRequestResult, String> {
    Ok(core::create_request(
        core::Network::from_api_name(&network)?,
        subject_identity.as_deref(),
        now,
    )?
    .into())
}

pub fn contacts_inspect_request(
    network: String,
    request_json: String,
    now: u64,
) -> Result<ContactRequestResult, String> {
    Ok(core::inspect_request(core::Network::from_api_name(&network)?, &request_json, now)?.into())
}

pub fn contacts_sign_response(
    network: String,
    request_json: String,
    secret_key: Vec<u8>,
    address: String,
    sequence: u64,
    now: u64,
) -> Result<String, String> {
    // Wrap before network/request validation, so failures also erase the FFI
    // input. Core's local seed and Dalek signing key have separate zeroization.
    let secret_key = Zeroizing::new(secret_key);
    core::sign_response(
        core::Network::from_api_name(&network)?,
        &request_json,
        &secret_key,
        &address,
        sequence,
        now,
        validate_unified_address,
    )
    .map_err(str::to_owned)
}

pub fn contacts_verify_response(
    network: String,
    request_json: String,
    exchange_json: String,
    now: u64,
) -> Result<ContactEndpointResult, String> {
    let result = core::verify_response(
        core::Network::from_api_name(&network)?,
        &request_json,
        &exchange_json,
        now,
        validate_unified_address,
    )?;
    Ok(ContactEndpointResult {
        identity: result.identity,
        address: result.address,
        sequence: result.sequence,
        expires_at: result.expires_at,
        network: result.network,
    })
}

/// Cryptographically verified introduction candidate. These fields do not
/// authorize consent, contact acceptance, transport or payment. The coordinator
/// must recheck current accepted associations and atomically consume sessions.
pub struct ContactIntroductionResult {
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

impl From<core::introduction::Verified> for ContactIntroductionResult {
    fn from(value: core::introduction::Verified) -> Self {
        Self {
            packet_json: value.packet_json,
            request_json: value.request_json,
            request_hash: value.request_hash,
            endpoint_hash: value.endpoint_hash,
            endorsement_hash: value.endorsement_hash,
            expires_at: value.expires_at,
            offer_json: value.offer_json,
            endpoint_json: value.endpoint_json,
            identity: value.identity,
            address: value.address,
            sequence: value.sequence,
            suggestion: value.suggestion,
        }
    }
}

pub fn contacts_validate_introduction_association(
    network: String,
    incoming_identity: String,
    own_identity: String,
    own_secret_key: Vec<u8>,
) -> Result<bool, String> {
    let own_secret_key = Zeroizing::new(own_secret_key);
    core::Network::from_api_name(&network)?;
    core::introduction::validate_association(&incoming_identity, &own_identity, &own_secret_key)
        .map_err(str::to_owned)
}

pub fn contacts_create_introduction_ask(
    network: String,
    peer_ac_identity: String,
    secret_ca_key: Vec<u8>,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    let secret_ca_key = Zeroizing::new(secret_ca_key);
    Ok(core::introduction::create_ask(
        core::Network::from_api_name(&network)?,
        &peer_ac_identity,
        &secret_ca_key,
        now,
    )?
    .into())
}

pub fn contacts_verify_introduction_ask(
    network: String,
    peer_ca_identity: String,
    own_ac_identity: String,
    packet_json: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    Ok(core::introduction::verify(
        core::introduction::Role::Ask,
        core::Network::from_api_name(&network)?,
        &peer_ca_identity,
        &own_ac_identity,
        None,
        None,
        &packet_json,
        now,
        validate_unified_address,
    )?
    .into())
}

pub fn contacts_create_introduction_offer(
    network: String,
    request_json: String,
    peer_ba_identity: String,
    secret_ab_key: Vec<u8>,
    suggested_recipient: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    let secret_ab_key = Zeroizing::new(secret_ab_key);
    Ok(core::introduction::create_offer(
        core::Network::from_api_name(&network)?,
        &request_json,
        &peer_ba_identity,
        &secret_ab_key,
        &suggested_recipient,
        now,
    )?
    .into())
}

pub fn contacts_verify_introduction_offer(
    network: String,
    peer_ab_identity: String,
    own_ba_identity: String,
    packet_json: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    Ok(core::introduction::verify(
        core::introduction::Role::Offer,
        core::Network::from_api_name(&network)?,
        &peer_ab_identity,
        &own_ba_identity,
        None,
        None,
        &packet_json,
        now,
        validate_unified_address,
    )?
    .into())
}

pub fn contacts_create_introduction_consent(
    network: String,
    peer_ab_identity: String,
    secret_ba_key: Vec<u8>,
    fresh_secret_bc_key: Vec<u8>,
    fresh_address: String,
    offer_packet_json: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    // Wrap every imported secret before any fallible operation, including the
    // network gate, so all FFI-owned copies are erased on success and error.
    let secret_ba_key = Zeroizing::new(secret_ba_key);
    let fresh_secret_bc_key = Zeroizing::new(fresh_secret_bc_key);
    Ok(core::introduction::create_consent(
        core::Network::from_api_name(&network)?,
        &peer_ab_identity,
        &secret_ba_key,
        &fresh_secret_bc_key,
        &fresh_address,
        &offer_packet_json,
        now,
        validate_unified_address,
    )?
    .into())
}

pub fn contacts_verify_introduction_consent(
    network: String,
    peer_ba_identity: String,
    own_ab_identity: String,
    saved_request_json: String,
    saved_offer_json: String,
    packet_json: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    Ok(core::introduction::verify(
        core::introduction::Role::Consent,
        core::Network::from_api_name(&network)?,
        &peer_ba_identity,
        &own_ab_identity,
        Some(&saved_request_json),
        Some(&saved_offer_json),
        &packet_json,
        now,
        validate_unified_address,
    )?
    .into())
}

pub fn contacts_create_introduction_delivery(
    network: String,
    peer_ba_identity: String,
    own_ab_identity: String,
    peer_ca_identity: String,
    secret_ac_key: Vec<u8>,
    saved_request_json: String,
    saved_offer_json: String,
    consent_packet_json: String,
    suggested_contact: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    let secret_ac_key = Zeroizing::new(secret_ac_key);
    Ok(core::introduction::create_delivery(
        core::Network::from_api_name(&network)?,
        &peer_ba_identity,
        &own_ab_identity,
        &peer_ca_identity,
        &secret_ac_key,
        &saved_request_json,
        &saved_offer_json,
        &consent_packet_json,
        &suggested_contact,
        now,
        validate_unified_address,
    )?
    .into())
}

pub fn contacts_verify_introduction_delivery(
    network: String,
    peer_ac_identity: String,
    own_ca_identity: String,
    saved_request_json: String,
    packet_json: String,
    now: u64,
) -> Result<ContactIntroductionResult, String> {
    Ok(core::introduction::verify(
        core::introduction::Role::Delivery,
        core::Network::from_api_name(&network)?,
        &peer_ac_identity,
        &own_ca_identity,
        Some(&saved_request_json),
        None,
        &packet_json,
        now,
        validate_unified_address,
    )?
    .into())
}

#[cfg(test)]
mod tests {
    use super::*;

    mod corpus {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/contact-core/tests/corpus_support.rs"
        ));
    }

    #[test]
    fn introduction_315_reviewed_vectors_use_the_real_wallet_ua_decoder() {
        corpus::check_introduction_corpus(validate_unified_address);
    }

    #[test]
    fn introduction_api_round_trip_gates_mainnet_and_rejects_invalid_receivers() {
        use zcash_address::unified::{self, Container, Encoding};
        use zcash_protocol::consensus::NetworkType;

        const REGTEST_UA: &str = "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn";
        let (_, ua) = unified::Address::decode(REGTEST_UA).unwrap();
        let orchard = ua
            .items_as_parsed()
            .iter()
            .find(|r| matches!(r, unified::Receiver::Orchard(_)))
            .unwrap()
            .clone();
        let malformed =
            unified::Address::try_from_items(vec![orchard, unified::Receiver::Sapling([0; 43])])
                .unwrap();
        let ac = contacts_create_identity().unwrap();
        let ca = contacts_create_identity().unwrap();
        let ab = contacts_create_identity().unwrap();
        let ba = contacts_create_identity().unwrap();
        let bc = contacts_create_identity().unwrap();
        let secret_ac = Zeroizing::new(ac.secret_key);
        let secret_ca = Zeroizing::new(ca.secret_key);
        let secret_ab = Zeroizing::new(ab.secret_key);
        let secret_ba = Zeroizing::new(ba.secret_key);
        let secret_bc = Zeroizing::new(bc.secret_key);
        for (network, wire_network) in [
            ("test", NetworkType::Test),
            ("regtest", NetworkType::Regtest),
        ] {
            let address = ua.encode(&wire_network);
            let ask = contacts_create_introduction_ask(
                network.into(),
                ac.identity.clone(),
                secret_ca.to_vec(),
                1000,
            )
            .unwrap();
            let checked_ask = contacts_verify_introduction_ask(
                network.into(),
                ca.identity.clone(),
                ac.identity.clone(),
                ask.packet_json.clone(),
                1000,
            )
            .unwrap();
            assert_eq!(checked_ask.request_json, ask.request_json);
            let offer = contacts_create_introduction_offer(
                network.into(),
                ask.request_json.clone(),
                ba.identity.clone(),
                secret_ab.to_vec(),
                "Carol".into(),
                1000,
            )
            .unwrap();
            assert!(contacts_verify_introduction_offer(
                network.into(),
                ab.identity.clone(),
                ba.identity.clone(),
                offer.packet_json.clone(),
                1000
            )
            .is_ok());
            assert!(contacts_create_introduction_consent(
                network.into(),
                ab.identity.clone(),
                secret_ba.to_vec(),
                secret_bc.to_vec(),
                malformed.encode(&wire_network),
                offer.packet_json.clone(),
                1000
            )
            .is_err());
            let consent = contacts_create_introduction_consent(
                network.into(),
                ab.identity.clone(),
                secret_ba.to_vec(),
                secret_bc.to_vec(),
                address.clone(),
                offer.packet_json.clone(),
                1000,
            )
            .unwrap();
            assert!(contacts_verify_introduction_consent(
                network.into(),
                ba.identity.clone(),
                ab.identity.clone(),
                ask.request_json.clone(),
                offer.offer_json.clone().unwrap(),
                consent.packet_json.clone(),
                1000
            )
            .is_ok());
            let delivery = contacts_create_introduction_delivery(
                network.into(),
                ba.identity.clone(),
                ab.identity.clone(),
                ca.identity.clone(),
                secret_ac.to_vec(),
                ask.request_json.clone(),
                offer.offer_json.clone().unwrap(),
                consent.packet_json.clone(),
                "Bob".into(),
                1000,
            )
            .unwrap();
            let verified = contacts_verify_introduction_delivery(
                network.into(),
                ac.identity.clone(),
                ca.identity.clone(),
                ask.request_json.clone(),
                delivery.packet_json.clone(),
                1000,
            )
            .unwrap();
            assert_eq!(verified.identity.as_deref(), Some(bc.identity.as_str()));
            assert_eq!(verified.address, Some(address));
            assert_eq!(verified.request_hash, ask.request_hash);
            assert_eq!(verified.endpoint_hash, consent.endpoint_hash);
            assert_eq!(
                verified.endorsement_hash.as_ref().map(String::len),
                Some(43)
            );
            assert!(contacts_validate_introduction_association(
                network.into(),
                ac.identity.clone(),
                ca.identity.clone(),
                secret_ca.to_vec()
            )
            .unwrap());
            assert!(!contacts_validate_introduction_association(
                network.into(),
                ac.identity.clone(),
                ca.identity.clone(),
                secret_ba.to_vec()
            )
            .unwrap());
            assert!(contacts_verify_introduction_delivery(
                network.into(),
                ac.identity.clone(),
                ca.identity.clone(),
                ask.request_json.clone(),
                delivery.packet_json.clone(),
                1900
            )
            .is_err());

            // Every public entry point rejects mainnet before wire processing.
            assert!(contacts_validate_introduction_association(
                "main".into(),
                ac.identity.clone(),
                ca.identity.clone(),
                secret_ca.to_vec()
            )
            .is_err());
            assert!(contacts_create_introduction_ask(
                "main".into(),
                ac.identity.clone(),
                secret_ca.to_vec(),
                1000
            )
            .is_err());
            assert!(contacts_verify_introduction_ask(
                "main".into(),
                ca.identity.clone(),
                ac.identity.clone(),
                ask.packet_json.clone(),
                1000
            )
            .is_err());
            assert!(contacts_create_introduction_offer(
                "main".into(),
                ask.request_json.clone(),
                ba.identity.clone(),
                secret_ab.to_vec(),
                "Carol".into(),
                1000
            )
            .is_err());
            assert!(contacts_verify_introduction_offer(
                "main".into(),
                ab.identity.clone(),
                ba.identity.clone(),
                offer.packet_json.clone(),
                1000
            )
            .is_err());
            assert!(contacts_create_introduction_consent(
                "main".into(),
                ab.identity.clone(),
                secret_ba.to_vec(),
                secret_bc.to_vec(),
                REGTEST_UA.into(),
                offer.packet_json.clone(),
                1000
            )
            .is_err());
            assert!(contacts_verify_introduction_consent(
                "main".into(),
                ba.identity.clone(),
                ab.identity.clone(),
                ask.request_json.clone(),
                offer.offer_json.clone().unwrap(),
                consent.packet_json.clone(),
                1000
            )
            .is_err());
            assert!(contacts_create_introduction_delivery(
                "main".into(),
                ba.identity.clone(),
                ab.identity.clone(),
                ca.identity.clone(),
                secret_ac.to_vec(),
                ask.request_json.clone(),
                offer.offer_json.clone().unwrap(),
                consent.packet_json.clone(),
                "Bob".into(),
                1000
            )
            .is_err());
            assert!(contacts_verify_introduction_delivery(
                "main".into(),
                ac.identity.clone(),
                ca.identity.clone(),
                ask.request_json.clone(),
                delivery.packet_json.clone(),
                1000
            )
            .is_err());
        }
    }

    #[test]
    fn direct_api_round_trip_uses_real_ua_and_rejects_mainnet() {
        // Public fixture from rust/tests/regtest_import.rs; no wallet DB access.
        let address = "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn";
        let identity = contacts_create_identity().unwrap();
        let secret = Zeroizing::new(identity.secret_key);
        let request =
            contacts_create_request("regtest".into(), Some(identity.identity.clone()), 1000)
                .unwrap();
        let inspected =
            contacts_inspect_request("regtest".into(), request.request_json.clone(), 1000).unwrap();
        assert_eq!(inspected.audience, request.audience);
        assert_eq!(inspected.challenge, request.challenge);
        let response = contacts_sign_response(
            "regtest".into(),
            request.request_json.clone(),
            secret.to_vec(),
            address.into(),
            1,
            1000,
        )
        .unwrap();
        let verified = contacts_verify_response(
            "regtest".into(),
            request.request_json.clone(),
            response.clone(),
            1000,
        )
        .unwrap();
        assert_eq!(verified.identity, identity.identity);
        assert_eq!(verified.address, address);
        assert_eq!(verified.sequence, 1);
        assert_eq!(verified.expires_at, 1300);
        assert_eq!(verified.network, "zcash-regtest");
        assert!(contacts_validate_unified_address("regtest".into(), address.into()).unwrap());
        assert!(!contacts_validate_unified_address("test".into(), address.into()).unwrap());
        assert!(contacts_validate_unified_address("main".into(), address.into()).is_err());
        assert!(contacts_create_request("main".into(), None, 1000).is_err());
        assert!(contacts_sign_response(
            "main".into(),
            request.request_json.clone(),
            secret.to_vec(),
            address.into(),
            1,
            1000
        )
        .is_err());
        assert!(contacts_verify_response(
            "main".into(),
            request.request_json.clone(),
            response.clone(),
            1000
        )
        .is_err());
        assert!(contacts_verify_response(
            "regtest".into(),
            request.request_json.clone(),
            response,
            1300
        )
        .is_err());
        assert!(contacts_sign_response(
            "regtest".into(),
            request.request_json,
            secret.to_vec(),
            "demo-only:alice".into(),
            1,
            1000
        )
        .is_err());
    }
}
