//! Local qualification helper. Fixed public test seed; refuses all real chains.
//! No private key, mnemonic or seed input is accepted.
use serde::Deserialize;
use serde_json::json;
use std::io::Read;
use vizor_zns_core::{Config, Operation, Transaction};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    config: Option<Config>,
    operation: Option<Operation>,
    transaction: Option<Transaction>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    std::io::stdin().take(131072).read_to_string(&mut input)?;
    let request: Request = serde_json::from_str(&input)?;
    let key = vizor_zns_core::derive_key(&[7u8; 64], 0)?;
    let address = vizor_zns_core::key_address(&key).to_checksum(None);
    let mut output = json!({"address":address});
    if let Some(config) = request.config {
        if config.chain_id != 31337 || !config.allow_test_chain {
            return Err("Local helper requires chain 31337 and allowTestChain".into());
        }
        let operation = request.operation.ok_or("Missing operation")?;
        output["prepared"] =
            serde_json::to_value(vizor_zns_core::prepare(&config, &address, &operation)?)?;
        if let Some(tx) = request.transaction {
            output["signed"] =
                serde_json::to_value(vizor_zns_core::sign(&key, &config, &operation, &tx)?)?;
        }
    } else if request.operation.is_some() || request.transaction.is_some() {
        return Err("Missing local configuration".into());
    }
    println!("{output}");
    Ok(())
}
