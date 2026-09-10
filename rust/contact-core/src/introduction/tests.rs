use super::*;

// Predictable public test seeds, unrelated to wallet authority.
fn id(byte: u8) -> String {
    key_identity(&SigningKey::from_bytes(&[byte; 32]))
}

const NOW: u64 = 1000;
const ADDRESS: &str = "public-test-address";

fn validate(_: Network, address: &str) -> bool {
    address == ADDRESS
}

fn exchange(network: Network) -> (Verified, Verified, Verified, Verified) {
    // Alice -> Carol 1; Carol -> Alice 2; Alice -> Bob 3;
    // Bob -> Alice 4; Bob -> Carol 5. All separate contact-only identities.
    let ask = create_ask(network, &id(1), &[2; 32], NOW).unwrap();
    let offer = create_offer(network, &ask.request_json, &id(4), &[3; 32], "Carol", NOW).unwrap();
    let consent = create_consent(
        network,
        &id(3),
        &[4; 32],
        &[5; 32],
        ADDRESS,
        &offer.packet_json,
        NOW,
        validate,
    )
    .unwrap();
    let delivery = create_delivery(
        network,
        &id(4),
        &id(3),
        &id(2),
        &[1; 32],
        &ask.request_json,
        offer.offer_json.as_deref().unwrap(),
        &consent.packet_json,
        "Bob",
        NOW,
        validate,
    )
    .unwrap();
    (ask, offer, consent, delivery)
}

#[test]
fn four_builders_round_trip_and_preserve_the_exact_transcript() {
    for network in [Network::Test, Network::Regtest] {
        let (ask, offer, consent, delivery) = exchange(network);
        let got = verify(
            Role::Delivery,
            network,
            &id(1),
            &id(2),
            Some(&ask.request_json),
            None,
            &delivery.packet_json,
            NOW,
            validate,
        )
        .unwrap();
        assert_eq!(got, delivery);
        assert_eq!(got.request_json, ask.request_json);
        assert_eq!(got.request_hash, ask.request_hash);
        assert_eq!(got.expires_at, NOW + 900);
        assert_eq!(consent.offer_json, offer.offer_json);
        assert_eq!(got.endpoint_json, consent.endpoint_json);
        assert_eq!(got.endpoint_hash, consent.endpoint_hash);
        assert_eq!(got.identity.as_deref(), Some(id(5).as_str()));
        assert_eq!(got.address.as_deref(), Some(ADDRESS));
        assert_eq!(got.sequence, Some(1));
        assert_eq!(got.suggestion.as_deref(), Some("Bob"));
        let packet: Value = canonical(&got.packet_json).unwrap();
        assert_eq!(got.endpoint_hash.as_deref(), digest(&packet[2]).as_str());
        assert_eq!(got.endorsement_hash.as_deref(), digest(&packet[3]).as_str());
        assert_eq!(offer.suggestion.as_deref(), Some("Carol"));
        assert!(ask.endpoint_hash.is_none());
        assert!(consent.endorsement_hash.is_none());
    }
}

#[test]
fn builders_reject_wrong_roles_saved_transcripts_old_keys_addresses_and_expiry() {
    let network = Network::Regtest;
    let (ask, offer, consent, delivery) = exchange(network);
    for secret in [&[3; 32][..], &[4; 32][..], &[5; 31][..]] {
        assert!(create_consent(
            network,
            &id(3),
            &[4; 32],
            secret,
            ADDRESS,
            &offer.packet_json,
            NOW,
            validate
        )
        .is_err());
    }
    assert!(create_consent(
        network,
        &id(1),
        &[4; 32],
        &[5; 32],
        ADDRESS,
        &offer.packet_json,
        NOW,
        validate
    )
    .is_err());
    assert!(create_consent(
        network,
        &id(3),
        &[2; 32],
        &[5; 32],
        ADDRESS,
        &offer.packet_json,
        NOW,
        validate
    )
    .is_err());
    assert!(create_consent(
        network,
        &id(3),
        &[4; 32],
        &[5; 32],
        "invalid",
        &offer.packet_json,
        NOW,
        validate
    )
    .is_err());
    assert!(create_consent(
        network,
        &id(3),
        &[4; 32],
        &[5; 32],
        ADDRESS,
        &offer.packet_json,
        NOW + 900,
        validate
    )
    .is_err());
    let other_ask = create_ask(network, &id(1), &[2; 32], NOW).unwrap();
    assert_ne!(ask.request_hash, other_ask.request_hash);
    let other_offer = create_offer(
        network,
        &ask.request_json,
        &id(4),
        &[3; 32],
        "Different",
        NOW,
    )
    .unwrap();
    for (r, o, peer, own, signer) in [
        (
            other_ask.request_json.as_str(),
            offer.offer_json.as_deref().unwrap(),
            id(4),
            id(3),
            1,
        ),
        (
            ask.request_json.as_str(),
            other_offer.offer_json.as_deref().unwrap(),
            id(4),
            id(3),
            1,
        ),
        (
            ask.request_json.as_str(),
            offer.offer_json.as_deref().unwrap(),
            id(5),
            id(3),
            1,
        ),
        (
            ask.request_json.as_str(),
            offer.offer_json.as_deref().unwrap(),
            id(4),
            id(1),
            1,
        ),
        (
            ask.request_json.as_str(),
            offer.offer_json.as_deref().unwrap(),
            id(4),
            id(3),
            5,
        ),
    ] {
        assert!(create_delivery(
            network,
            &peer,
            &own,
            &id(2),
            &[signer; 32],
            r,
            o,
            &consent.packet_json,
            "Bob",
            NOW,
            validate
        )
        .is_err());
    }
    assert!(create_delivery(
        network,
        &id(4),
        &id(3),
        &id(5),
        &[1; 32],
        &ask.request_json,
        offer.offer_json.as_deref().unwrap(),
        &consent.packet_json,
        "Bob",
        NOW,
        validate
    )
    .is_err());
    assert!(verify(
        Role::Delivery,
        network,
        &id(5),
        &id(2),
        Some(&ask.request_json),
        None,
        &delivery.packet_json,
        NOW,
        validate
    )
    .is_err());
}

#[test]
fn association_and_builder_argument_validation() {
    assert!(validate_association(&id(1), &id(2), &[2; 32]).unwrap());
    assert!(!validate_association(&id(1), &id(2), &[3; 32]).unwrap());
    assert!(!validate_association(&id(2), &id(2), &[2; 32]).unwrap());
    assert!(!validate_association("ed25519:bad", &id(2), &[2; 32]).unwrap());
    assert!(validate_association(&id(1), &id(2), &[2; 31]).is_err());
    assert!(create_ask(Network::Test, &id(2), &[2; 32], NOW).is_err());
    assert!(create_ask(Network::Test, &id(1), &[2; 32], MAX_SAFE_INTEGER - 899).is_err());
    assert!(create_ask(Network::Test, &id(1), &[2; 31], NOW).is_err());
    let ask = create_ask(Network::Test, &id(1), &[2; 32], NOW).unwrap();
    for suggestion in [
        "",
        " leading",
        "trailing ",
        "too-long-contact-name!",
        "Zoë",
        "new\nline",
    ] {
        assert!(create_offer(
            Network::Test,
            &ask.request_json,
            &id(4),
            &[3; 32],
            suggestion,
            NOW
        )
        .is_err());
    }
    assert!(create_offer(
        Network::Regtest,
        &ask.request_json,
        &id(4),
        &[3; 32],
        "Carol",
        NOW
    )
    .is_err());
    assert!(create_offer(
        Network::Test,
        &ask.request_json,
        &id(3),
        &[3; 32],
        "Carol",
        NOW
    )
    .is_err());
}
