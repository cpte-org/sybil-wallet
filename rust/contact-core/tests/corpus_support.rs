// Test-only adapter for the reviewed public runner rows. This is deliberately
// excluded from the library and app runtime. The native API test passes the
// wallet's actual UA decoder; the standalone core test passes its fixture oracle.
use serde_json::{json, Value};
use vizor_contact_core::{introduction, Network, MAX_SAFE_INTEGER};

pub fn check_introduction_corpus(validate_ua: impl Fn(Network, &str) -> bool) {
    let cases: Vec<Value> =
        serde_json::from_str(include_str!("fixtures/introduction-vectors.json")).unwrap();
    assert_eq!(cases.len(), 315);
    let mut ids = std::collections::HashSet::new();
    for case in cases {
        assert!(ids.insert(case["id"].as_str().unwrap().to_owned()));
        let actual = verify_row(&case["input"], &validate_ua).unwrap_or(json!({"ok":false}));
        assert_eq!(actual, case["expected"], "case {}", case["id"]);
    }
}

fn verify_row(row: &Value, validate_ua: &impl Fn(Network, &str) -> bool) -> Option<Value> {
    let row = row.as_array()?;
    (row.len() == 7).then_some(())?;
    let now = row[1].as_u64().filter(|v| *v <= MAX_SAFE_INTEGER)?;
    let network = match row[2].as_str()? {
        "zcash-testnet" => Network::Test,
        "zcash-regtest" => Network::Regtest,
        _ => return None,
    };
    let (role, saved_request, saved_offer) = match row[0].as_str()? {
        "ask" | "offer" => {
            row[5].is_null().then_some(())?;
            (
                if row[0] == "ask" {
                    introduction::Role::Ask
                } else {
                    introduction::Role::Offer
                },
                None,
                None,
            )
        }
        "consent" => {
            let saved = row[5].as_array()?;
            (saved.len() == 2).then_some(())?;
            (
                introduction::Role::Consent,
                Some(saved[0].to_string()),
                Some(saved[1].to_string()),
            )
        }
        "delivery" => (introduction::Role::Delivery, Some(row[5].to_string()), None),
        _ => return None,
    };
    let result = introduction::verify(
        role,
        network,
        row[3].as_str()?,
        row[4].as_str()?,
        saved_request.as_deref(),
        saved_offer.as_deref(),
        row[6].as_str()?,
        now,
        validate_ua,
    )
    .ok()?;
    // The public corpus runner returns a deliberately smaller candidate object.
    let mut output = json!({"ok":true,"requestHash":result.request_hash});
    if let Some(identity) = result.identity {
        output["identity"] = json!(identity);
    }
    if let Some(address) = result.address {
        output["address"] = json!(address);
    }
    if let Some(sequence) = result.sequence {
        output["sequence"] = json!(sequence);
    }
    if let Some(suggestion) = result.suggestion {
        output["suggestion"] = json!(suggestion);
    }
    Some(output)
}
