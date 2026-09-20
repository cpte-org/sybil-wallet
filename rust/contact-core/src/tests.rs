use super::*;
use curve25519_dalek::constants::{ED25519_BASEPOINT_POINT, EIGHT_TORSION};

// Public deterministic cryptographic test material; never wallet authority.
const NOW: u64 = 1000;
const TEST_ADDRESS: &str = "public-test-address";

fn id(byte: u8) -> String {
    key_identity(&SigningKey::from_bytes(&[byte; 32]))
}

fn request(network: Network, subject: Option<&str>) -> String {
    json!([
        REQUEST_DOMAIN,
        network.wire_name(),
        id(2),
        URL_SAFE_NO_PAD.encode([3; 32]),
        1300,
        subject,
    ])
    .to_string()
}

fn payload() -> Value {
    json!([
        ENDPOINT_DOMAIN,
        Network::Test.wire_name(),
        id(1),
        id(2),
        URL_SAFE_NO_PAD.encode([3; 32]),
        1,
        NOW,
        1200,
        TEST_ADDRESS,
    ])
}

fn signed_bytes(bytes: &[u8]) -> String {
    let signature = SigningKey::from_bytes(&[1; 32]).sign(bytes).to_bytes();
    json!([
        EXCHANGE_DOMAIN,
        [
            URL_SAFE_NO_PAD.encode(bytes),
            URL_SAFE_NO_PAD.encode(signature)
        ],
        null
    ])
    .to_string()
}

fn signed(payload: &Value) -> String {
    signed_bytes(payload.to_string().as_bytes())
}

fn validate(network: Network, address: &str) -> bool {
    network == Network::Test && address == TEST_ADDRESS
}

fn check(exchange: &str) -> Result<Endpoint, &'static str> {
    verify_response(
        Network::Test,
        &request(Network::Test, None),
        exchange,
        NOW,
        validate,
    )
}

#[test]
fn direct_signing_round_trip_and_subject_binding() {
    for network in [Network::Main, Network::Test, Network::Regtest] {
        for subject in [None, Some(id(1))] {
            let request = request(network, subject.as_deref());
            let exchange =
                sign_response(network, &request, &[1; 32], TEST_ADDRESS, 7, NOW, |_, a| {
                    a == TEST_ADDRESS
                })
                .unwrap();
            let endpoint =
                verify_response(network, &request, &exchange, NOW, |_, a| a == TEST_ADDRESS)
                    .unwrap();
            assert_eq!(endpoint.identity, id(1));
            assert_eq!(endpoint.address, TEST_ADDRESS);
            assert_eq!(endpoint.sequence, 7);
            assert_eq!(endpoint.expires_at, 1300);
            assert_eq!(endpoint.network, network.wire_name());
        }
    }
    let targeted = request(Network::Test, Some(&id(4)));
    assert!(sign_response(
        Network::Test,
        &targeted,
        &[1; 32],
        TEST_ADDRESS,
        1,
        NOW,
        validate
    )
    .is_err());
    assert!(verify_response(Network::Test, &targeted, &signed(&payload()), NOW, validate).is_err());
}

#[test]
fn identity_and_requests_are_fresh_and_requests_retain_no_secret() {
    let first = create_identity().unwrap();
    let second = create_identity().unwrap();
    assert_ne!(first.identity, second.identity);
    assert_eq!(first.secret_key.len(), 32);
    assert_eq!(
        first.identity,
        key_identity(&SigningKey::from_bytes(
            &first.secret_key.as_slice().try_into().unwrap()
        ))
    );
    let a = create_request(Network::Test, Some(&first.identity), NOW).unwrap();
    let b = create_request(Network::Test, None, NOW).unwrap();
    assert_ne!(a.audience, b.audience);
    assert_ne!(a.challenge, b.challenge);
    assert_eq!(a.expires_at, 1300);
    assert_eq!(a.subject_identity.as_deref(), Some(first.identity.as_str()));
    assert_eq!(
        inspect_request(Network::Test, &a.request_json, NOW).unwrap(),
        a
    );
    assert_eq!(
        serde_json::from_str::<Value>(&a.request_json)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        6
    );
}

#[test]
fn unknown_network_and_wrong_context_are_rejected() {
    for network in ["mainnet", "zcash-mainnet", "zcash-testnet", "test ", ""] {
        assert!(Network::from_api_name(network).is_err());
    }
    assert_eq!(Network::from_api_name("test"), Ok(Network::Test));
    assert_eq!(Network::from_api_name("main"), Ok(Network::Main));
    for network in [Network::Main, Network::Test, Network::Regtest] {
        let original = request(network, None);
        let response = sign_response(
            network,
            &original,
            &[1; 32],
            TEST_ADDRESS,
            1,
            NOW,
            |_, _| true,
        )
        .unwrap();
        for other in [Network::Main, Network::Test, Network::Regtest] {
            if other == network {
                continue;
            }
            assert!(inspect_request(other, &original, NOW).is_err());
            assert!(
                verify_response(other, &request(other, None), &response, NOW, |_, _| true).is_err()
            );
        }
    }
    assert!(inspect_request(Network::Regtest, &request(Network::Test, None), NOW).is_err());
    assert!(verify_response(
        Network::Regtest,
        &request(Network::Regtest, None),
        &signed(&payload()),
        NOW,
        |_, _| true
    )
    .is_err());
    for (field, value) in [
        (0, json!("zcash-contact-lab/endpoint")),
        (1, json!("zcash-mainnet")),
        (2, json!(id(4))),
        (3, json!(id(4))),
        (4, json!(URL_SAFE_NO_PAD.encode([9; 32]))),
    ] {
        let mut changed = payload();
        changed[field] = value;
        assert!(check(&signed(&changed)).is_err());
    }
}

#[test]
fn requests_reject_noncanonical_malformed_unsafe_and_expired_contexts() {
    let original: Value = serde_json::from_str(&request(Network::Test, None)).unwrap();
    for (field, value) in [
        (0, json!("zcash-contact-lab/request")),
        (1, json!("zcash-mainnet")),
        (2, json!("ed25519:AA")),
        (
            2,
            json!(format!("ed25519:{}", URL_SAFE_NO_PAD.encode([0u8; 32]))),
        ),
        (3, json!(URL_SAFE_NO_PAD.encode([3; 31]))),
        (3, json!(format!("{}=", URL_SAFE_NO_PAD.encode([3; 32])))),
        (4, json!(1000)),
        (4, json!(1301)),
        (4, json!(1300.0)),
        (4, json!(-1)),
        (4, json!(MAX_SAFE_INTEGER + 1)),
        (5, json!("ed25519:invalid")),
        (5, json!([])),
    ] {
        let mut changed = original.clone();
        changed[field] = value;
        assert!(inspect_request(Network::Test, &changed.to_string(), NOW).is_err());
    }
    let mut changed = original.clone();
    changed.as_array_mut().unwrap().push(Value::Null);
    assert!(inspect_request(Network::Test, &changed.to_string(), NOW).is_err());
    assert!(inspect_request(Network::Test, &format!(" {original}"), NOW).is_err());
    assert!(inspect_request(Network::Test, &format!("{original}\n"), NOW).is_err());
    assert!(inspect_request(
        Network::Test,
        &original
            .to_string()
            .replace("zcash-contact/request", "zcash-contact\\/request"),
        NOW
    )
    .is_err());
    assert!(create_request(Network::Test, Some("ed25519:invalid"), NOW).is_err());
}

#[test]
fn signatures_require_canonical_nonidentity_prime_subgroup_points_and_scalar() {
    let key = SigningKey::from_bytes(&[1; 32]);
    let message = b"contact core strict profile";
    let signature = key.sign(message).to_bytes();
    let public_key = key.verifying_key().to_bytes();
    assert!(verify_signature(&public_key, message, &signature).is_some());
    assert!(verify_signature(&public_key, b"changed", &signature).is_none());
    let mut bad_points: Vec<[u8; 32]> = EIGHT_TORSION
        .iter()
        .map(|p| p.compress().to_bytes())
        .collect();
    bad_points.extend(
        EIGHT_TORSION
            .iter()
            .skip(1)
            .map(|p| (ED25519_BASEPOINT_POINT + p).compress().to_bytes()),
    );
    let mut noncanonical_y = [0xff; 32];
    noncanonical_y[0] = 0xee;
    noncanonical_y[31] = 0x7f;
    bad_points.push(noncanonical_y);
    let mut negative_zero = [0u8; 32];
    negative_zero[0] = 1;
    negative_zero[31] = 0x80;
    bad_points.extend([negative_zero, [0xff; 32]]);
    for bad_point in bad_points {
        assert!(profile_point(&bad_point).is_none());
        assert!(identity(&format!("ed25519:{}", URL_SAFE_NO_PAD.encode(bad_point))).is_none());
        assert!(verify_signature(&bad_point, message, &signature).is_none());
        let mut changed = signature;
        changed[..32].copy_from_slice(&bad_point);
        assert!(verify_signature(&public_key, message, &changed).is_none());
    }
    let order = [
        0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde,
        0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10,
    ];
    let mut changed = signature;
    changed[32..].copy_from_slice(&order);
    assert!(verify_signature(&public_key, message, &changed).is_none());
    changed[32..].fill(0xff);
    assert!(verify_signature(&public_key, message, &changed).is_none());
}

#[test]
fn canonical_json_and_base64url_are_mandatory() {
    let valid = signed(&payload());
    assert!(check(&valid).is_ok());
    assert!(check(&format!(" {valid}")).is_err());
    assert!(check(&format!("{valid}\n")).is_err());
    assert!(check(&signed_bytes(format!(" {}", payload()).as_bytes())).is_err());
    assert!(check(&signed_bytes(
        payload().to_string().replace(",1,", ",1.0,").as_bytes()
    ))
    .is_err());
    assert!(check(&signed_bytes(
        payload()
            .to_string()
            .replace("zcash-contact/endpoint", "zcash-contact\\/endpoint")
            .as_bytes()
    ))
    .is_err());
    let parsed: Value = serde_json::from_str(&valid).unwrap();
    for index in [0, 1] {
        for replacement in [
            format!("{}=", parsed[1][index].as_str().unwrap()),
            "%%%".to_owned(),
            "AA".to_owned(),
        ] {
            let mut changed = parsed.clone();
            changed[1][index] = json!(replacement);
            assert!(check(&changed.to_string()).is_err());
        }
    }
    // Two encodings of one zero byte: nonzero trailing pad bits are forbidden.
    assert!(decode("AA").is_some());
    assert!(decode("AB").is_none());
    let mut changed = parsed;
    let mut signature = decode(changed[1][1].as_str().unwrap()).unwrap();
    signature[45] ^= 1;
    changed[1][1] = json!(URL_SAFE_NO_PAD.encode(signature));
    assert!(check(&changed.to_string()).is_err());
}

#[test]
fn strict_schema_rejects_introductions_extra_fields_and_oversized_input() {
    let mut exchange: Value = serde_json::from_str(&signed(&payload())).unwrap();
    exchange[2] = json!(["introduction"]);
    assert!(check(&exchange.to_string()).is_err());
    exchange[2] = Value::Null;
    exchange.as_array_mut().unwrap().push(Value::Null);
    assert!(check(&exchange.to_string()).is_err());
    let mut endpoint = payload();
    endpoint.as_array_mut().unwrap().push(json!("extra"));
    assert!(check(&signed(&endpoint)).is_err());
    assert!(check(&" ".repeat(MAX_INPUT_BYTES + 1)).is_err());
    assert!(inspect_request(Network::Test, &" ".repeat(MAX_INPUT_BYTES + 1), NOW).is_err());
    assert!(
        check("{\"secret\":\"do not include in error\"}")
            .unwrap_err()
            .len()
            < 100
    );
}

#[test]
fn time_revision_bounds_and_request_expiry_are_rechecked() {
    for (field, value) in [
        (5, json!(0)),
        (5, json!(-1)),
        (5, json!(1.5)),
        (5, json!(MAX_SAFE_INTEGER + 1)),
        (6, json!(1031)),
        (6, json!(1200)),
        (6, json!(899)),
        (7, json!(1000)),
        (7, json!(1301)),
        (7, json!(MAX_SAFE_INTEGER + 1)),
    ] {
        let mut changed = payload();
        changed[field] = value;
        assert!(check(&signed(&changed)).is_err(), "field {field}");
    }
    let mut boundary = payload();
    boundary[6] = json!(1030);
    assert!(check(&signed(&boundary)).is_ok());
    boundary[5] = json!(MAX_SAFE_INTEGER);
    assert!(check(&signed(&boundary)).is_ok());
    assert!(verify_response(
        Network::Test,
        &request(Network::Test, None),
        &signed(&payload()),
        1200,
        validate
    )
    .is_err());
    assert!(inspect_request(Network::Test, &request(Network::Test, None), 1300).is_err());
    assert!(inspect_request(Network::Test, &request(Network::Test, None), 999).is_err());
    assert!(create_request(Network::Test, None, MAX_SAFE_INTEGER).is_err());
    assert!(create_request(Network::Test, None, u64::MAX).is_err());
    let mut short_request: Value = serde_json::from_str(&request(Network::Test, None)).unwrap();
    short_request[4] = json!(1100);
    let signed = sign_response(
        Network::Test,
        &short_request.to_string(),
        &[1; 32],
        TEST_ADDRESS,
        1,
        NOW,
        validate,
    )
    .unwrap();
    assert_eq!(
        verify_response(
            Network::Test,
            &short_request.to_string(),
            &signed,
            NOW,
            validate
        )
        .unwrap()
        .expires_at,
        1100
    );
}

#[test]
fn signing_and_verification_use_the_address_validator_and_defend_byte_bounds() {
    for address in [
        "",
        "demo-only:alice",
        "public-test-address ",
        " public-test-address",
        "different",
    ] {
        let mut changed = payload();
        changed[8] = json!(address);
        assert!(check(&signed(&changed)).is_err());
        assert!(sign_response(
            Network::Test,
            &request(Network::Test, None),
            &[1; 32],
            address,
            1,
            NOW,
            validate
        )
        .is_err());
    }
    assert!(sign_response(
        Network::Test,
        &request(Network::Test, None),
        &[1; 31],
        TEST_ADDRESS,
        1,
        NOW,
        validate
    )
    .is_err());
    assert!(sign_response(
        Network::Test,
        &request(Network::Test, None),
        &[1; 32],
        &"a".repeat(513),
        1,
        NOW,
        |_, _| true
    )
    .is_err());
    assert!(sign_response(
        Network::Test,
        &request(Network::Test, None),
        &[1; 32],
        TEST_ADDRESS,
        0,
        NOW,
        validate
    )
    .is_err());
    assert!(sign_response(
        Network::Test,
        &request(Network::Test, None),
        &[1; 32],
        TEST_ADDRESS,
        MAX_SAFE_INTEGER + 1,
        NOW,
        validate
    )
    .is_err());
    assert!(verify_response(
        Network::Test,
        &request(Network::Test, None),
        &signed(&payload()),
        NOW,
        |_, _| false
    )
    .is_err());
}
