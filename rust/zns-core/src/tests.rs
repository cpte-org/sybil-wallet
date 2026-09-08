use super::*;
use alloy_sol_types::{SolCall, SolValue};
use bip0039::{English, Mnemonic};
use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
use rlp::{Rlp, RlpStream};

const MNEMONIC: &str = "test test test test test test test test test test test junk";
fn key() -> SigningKey {
    derive_key(
        &Mnemonic::<English>::from_phrase(MNEMONIC)
            .unwrap()
            .to_seed(""),
        0,
    )
    .unwrap()
}
fn config() -> Config {
    Config {
        protocol_id: PROTOCOL_ID.into(),
        chain_id: 8453,
        registry: "0x1111111111111111111111111111111111111111".into(),
        token: CBZEC.into(),
        router: Some(KYBER.into()),
        delegate: Some("0x3333333333333333333333333333333333333333".into()),
        allow_test_chain: false,
        max_value_wei: "1000000000000000".into(),
        max_gas_limit: "2000000".into(),
        max_fee_per_gas_wei: "1000000000".into(),
        max_total_fee_wei: "3000000000000000".into(),
        max_token_amount: "1000000".into(),
    }
}
fn tx() -> Transaction {
    Transaction {
        nonce: "7".into(),
        gas_limit: "500000".into(),
        max_fee_per_gas: "100000000".into(),
        max_priority_fee_per_gas: "1000000".into(),
        l1_fee_wei: "10000000000".into(),
    }
}
fn register() -> Operation {
    Operation::Register {
        name: "alice".into(),
        unified_address: "u1-vector-not-valid-ua".into(),
        secret: format!("0x{}", "22".repeat(32)),
    }
}
fn atomic(swap: Option<Swap>) -> Operation {
    Operation::AtomicRegister {
        name: "alice".into(),
        unified_address: "u1-vector-not-valid-ua".into(),
        secret: format!("0x{}", "22".repeat(32)),
        amount: "500000".into(),
        swap,
        deadline: "2000000000".into(),
        existing_token_units: "0".into(),
    }
}

#[test]
fn protocol_and_old_economics_are_rejected_before_signing() {
    assert_eq!(
        alloy_primitives::keccak256(
            "ZNS:cbZEC:deposit365:refresh365:grace90:forfeitAll:reserveCarry:erc721:multiName:clearUA"
        )
        .to_string(),
        PROTOCOL_ID
    );
    let mut c = config();
    c.protocol_id = B256::ZERO.to_string();
    assert!(sign(&key(), &c, &register(), &tx())
        .unwrap_err()
        .contains("protocol"));
    let mut missing = serde_json::to_value(config()).unwrap();
    missing.as_object_mut().unwrap().remove("protocolId");
    assert!(serde_json::from_value::<Config>(missing).is_err());
    for legacy in [
        serde_json::json!({"kind":"renew","name":"alice","years":1}),
        serde_json::json!({"kind":"withdraw"}),
        serde_json::json!({"kind":"update","name":"alice","unifiedAddress":"u1test"}),
    ] {
        assert!(serde_json::from_value::<Operation>(legacy).is_err());
    }
    let mut old_register = serde_json::to_value(register()).unwrap();
    old_register["years"] = serde_json::json!(1);
    assert!(serde_json::from_value::<Operation>(old_register).is_err());
    for legacy in ["annualFee", "fixedBond", "claimableBond", "activeNameOf"] {
        assert!(abi::read_call(legacy, &serde_json::json!({"owner":config().registry})).is_err());
    }
}

#[test]
fn management_intents_bind_stable_position_and_never_sweep_active_names() {
    let c = config();
    // Selector vectors independently calculated using viem toFunctionSelector.
    for (operation, selector) in [
        (
            Operation::Refresh {
                position_id: "42".into(),
            },
            "0x9c75dd35",
        ),
        (
            Operation::ClaimRewards {
                position_id: "42".into(),
            },
            "0x0962ef79",
        ),
        (
            Operation::Release {
                position_id: "42".into(),
            },
            "0x37bdc99b",
        ),
    ] {
        let p = prepare(&c, &key_address(&key()).to_string(), &operation).unwrap();
        assert_eq!(p.data, format!("{selector}{:064x}", 42));
        assert_eq!(p.value, "0");
        assert_eq!(p.to, c.registry);
    }
    let p = prepare(
        &c,
        &key_address(&key()).to_string(),
        &Operation::WithdrawClaims {},
    )
    .unwrap();
    assert_eq!(p.data, "0xb9728620");
    let p = prepare(
        &c,
        &key_address(&key()).to_string(),
        &Operation::Update {
            position_id: "42".into(),
            unified_address: "u1-vector-not-valid-ua".into(),
        },
    )
    .unwrap();
    assert!(p.data.starts_with("0x0f421135"));
    let decoded = abi::setUnifiedAddressCall::abi_decode(&bytes(&p.data).unwrap(), true).unwrap();
    assert_eq!(decoded.positionId, U256::from(42));
    assert!(prepare(
        &c,
        &key_address(&key()).to_string(),
        &Operation::Release {
            position_id: "0".into()
        }
    )
    .is_err());
}

#[test]
fn economic_read_abi_preserves_scaled_rewards_and_initial_maturity() {
    let scale = U256::from(10).pow(U256::from(24));
    let claims = (U256::from(25), scale + U256::from(1)).abi_encode_params();
    assert_eq!(
        abi::decode_result("claimableOf", &format!("0x{}", hex::encode(claims))).unwrap(),
        serde_json::json!({"principal":"25","rewardsScaled":(scale + U256::from(1)).to_string()})
    );
    let position = (
        address(&config().registry).unwrap(),
        "alice".to_owned(),
        "u1test".to_owned(),
        100u64,
        31536100u64,
        63072100u64,
        70848100u64,
        true,
        false,
        scale + U256::from(7),
    )
        .abi_encode_params();
    let result =
        abi::decode_result("positionInfo", &format!("0x{}", hex::encode(position))).unwrap();
    assert_eq!(result["maturityAt"], "31536100");
    assert_eq!(result["refreshDueAt"], "63072100");
    assert_eq!(
        result["rewardCreditScaled"],
        (scale + U256::from(7)).to_string()
    );
    let exit = (true, U256::ZERO, U256::ZERO, U256::from(25), scale).abi_encode_params();
    let result = abi::decode_result("exitPreview", &format!("0x{}", hex::encode(exit))).unwrap();
    assert_eq!(result["principalForfeited"], "25");
    assert_eq!(result["early"], true);
    assert!(abi::decode_result("positionInfo", "0x00").is_err());
}

#[test]
fn published_bip32_vector_one() {
    // https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#test-vector-1
    let seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
    let cases = [
        ("m", "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"),
        ("m/0'/1", "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs"),
    ];
    for (path, expected) in cases {
        assert_eq!(
            XPrv::derive_from_path(&seed, &path.parse().unwrap())
                .unwrap()
                .to_string(bip32::Prefix::XPRV)
                .as_str(),
            expected
        );
    }
}

#[test]
fn ethereum_account_vectors_and_account_separation() {
    // Hardhat's public test mnemonic; indices 1 and 2 independently generated
    // with viem mnemonicToAccount({accountIndex}) on 2026-09-08.
    let seed = Mnemonic::<English>::from_phrase(MNEMONIC)
        .unwrap()
        .to_seed("");
    for (index, expected) in [
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "0x8C8d35429F74ec245F8Ef2f4Fd1e551cFF97d650",
        "0x98e503f35D0a019cB0a251aD243a4cCFCF371F46",
    ]
    .iter()
    .enumerate()
    {
        assert_eq!(
            key_address(&derive_key(&seed, index as u32).unwrap()).to_checksum(None),
            *expected
        );
    }
    let passphrase_seed = Mnemonic::<English>::from_phrase(MNEMONIC)
        .unwrap()
        .to_seed("passphrase");
    assert_ne!(
        key_address(&derive_key(&seed, 0).unwrap()),
        key_address(&derive_key(&passphrase_seed, 0).unwrap())
    );
    assert_eq!(derivation_path(2).unwrap(), "m/44'/60'/2'/0/0");
    assert!(derive_key(&seed, 1 << 31).is_err());
}

#[test]
fn commitment_matches_viem_and_binds_every_field() {
    // Independently computed using viem encodeAbiParameters + keccak256.
    let c = config();
    let owner = key_address(&key());
    let secret = B256::repeat_byte(0x22);
    let make = |registry, chain, name: &str, ua: &str, owner, secret| {
        abi::commitment(registry, chain, name, ua, owner, secret)
    };
    let expected = make(
        address(&c.registry).unwrap(),
        8453,
        "alice",
        "u1-vector-not-valid-ua",
        owner,
        secret,
    );
    assert_eq!(
        expected.to_string(),
        "0x8d90ae2123bde5ae3e0214905c98cc263d09be57bfbb877ea490b9bf6b9dc476"
    );
    assert_ne!(
        expected,
        make(
            Address::repeat_byte(9),
            8453,
            "alice",
            "u1-vector-not-valid-ua",
            owner,
            secret
        )
    );
    assert_ne!(
        expected,
        make(
            address(&c.registry).unwrap(),
            84532,
            "alice",
            "u1-vector-not-valid-ua",
            owner,
            secret
        )
    );
    assert_ne!(
        expected,
        make(
            address(&c.registry).unwrap(),
            8453,
            "bob",
            "u1-vector-not-valid-ua",
            owner,
            secret
        )
    );
    assert_ne!(
        expected,
        make(
            address(&c.registry).unwrap(),
            8453,
            "alice",
            "different",
            owner,
            secret
        )
    );
    assert_ne!(
        expected,
        make(
            address(&c.registry).unwrap(),
            8453,
            "alice",
            "u1-vector-not-valid-ua",
            Address::repeat_byte(1),
            secret
        )
    );
    assert_ne!(
        expected,
        make(
            address(&c.registry).unwrap(),
            8453,
            "alice",
            "u1-vector-not-valid-ua",
            owner,
            B256::repeat_byte(4)
        )
    );
}

fn recover(raw: &[u8]) -> Address {
    let fields = Rlp::new(&raw[1..]);
    let count = fields.item_count().unwrap();
    let mut unsigned = RlpStream::new_list(count - 3);
    for i in 0..count - 3 {
        unsigned.append_raw(fields.at(i).unwrap().as_raw(), 1);
    }
    let mut input = vec![raw[0]];
    input.extend_from_slice(&unsigned.out());
    let r = U256::from_be_slice(fields.at(count - 2).unwrap().data().unwrap()).to_be_bytes::<32>();
    let s = U256::from_be_slice(fields.at(count - 1).unwrap().data().unwrap()).to_be_bytes::<32>();
    let signature = Signature::from_scalars(r, s).unwrap();
    assert!(signature.normalize_s().is_none());
    let parity = fields.val_at::<u8>(count - 3).unwrap();
    let public = VerifyingKey::recover_from_prehash(
        alloy_primitives::keccak256(input).as_slice(),
        &signature,
        RecoveryId::from_byte(parity).unwrap(),
    )
    .unwrap();
    let hash = alloy_primitives::keccak256(&public.to_encoded_point(false).as_bytes()[1..]);
    Address::from_slice(&hash[12..])
}

#[test]
fn eip1559_envelope_recovers_owner_and_changes_with_chain() {
    let c = config();
    let signed = sign(&key(), &c, &register(), &tx()).unwrap();
    let raw = bytes(&signed.raw_transaction).unwrap();
    // Independent viem mnemonicToAccount(...).signTransaction result.
    assert_eq!(signed.raw_transaction, "0x02f9015182210507830f42408405f5e1008307a12094111111111111111111111111111111111111111180b8e4f5de1230000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a022222222222222222222222222222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000000000005616c696365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001675312d766563746f722d6e6f742d76616c69642d756100000000000000000000c080a0970530e698174e98deb27855103efbda5952da4665dd636828e859021b520d72a016db7503dcc622fa8275e4f5338651905ef2a2505447968f5a61d4df10123521");
    assert_eq!(raw[0], 2);
    assert_eq!(recover(&raw), key_address(&key()));
    let rlp = Rlp::new(&raw[1..]);
    assert_eq!(rlp.item_count().unwrap(), 12);
    assert_eq!(rlp.val_at::<u64>(0).unwrap(), 8453);
    assert_eq!(rlp.val_at::<u64>(1).unwrap(), 7);
    assert_eq!(
        rlp.at(5).unwrap().data().unwrap(),
        address(&c.registry).unwrap().as_slice()
    );
    assert_eq!(
        abi::registerCall::abi_decode(rlp.at(7).unwrap().data().unwrap(), true)
            .unwrap()
            .name,
        "alice"
    );
    let mut test = c;
    test.chain_id = 84532;
    test.allow_test_chain = true;
    assert_ne!(
        signed.transaction_hash,
        sign(&key(), &test, &register(), &tx())
            .unwrap()
            .transaction_hash
    );
}

#[test]
fn eip7702_self_execution_and_authorization_recovery() {
    let c = config();
    let signed = sign(&key(), &c, &atomic(None), &tx()).unwrap();
    let raw = bytes(&signed.raw_transaction).unwrap();
    assert_eq!(raw[0], 4);
    assert_eq!(recover(&raw), key_address(&key()));
    assert_eq!(signed.authorization_nonce.as_deref(), Some("8"));
    let fields = Rlp::new(&raw[1..]);
    assert_eq!(fields.item_count().unwrap(), 13);
    assert_eq!(
        fields.at(5).unwrap().data().unwrap(),
        key_address(&key()).as_slice()
    );
    let auths = fields.at(9).unwrap();
    assert_eq!(auths.item_count().unwrap(), 1);
    let auth = auths.at(0).unwrap();
    assert_eq!(auth.val_at::<u64>(0).unwrap(), 8453);
    assert_eq!(auth.val_at::<u64>(2).unwrap(), 8);
    assert_eq!(
        auth.at(1).unwrap().data().unwrap(),
        address(c.delegate.as_deref().unwrap()).unwrap().as_slice()
    );
    let mut unsigned = RlpStream::new_list(3);
    for i in 0..3 {
        unsigned.append_raw(auth.at(i).unwrap().as_raw(), 1);
    }
    let mut input = vec![5u8];
    input.extend_from_slice(&unsigned.out());
    let signature = Signature::from_scalars(
        U256::from_be_slice(auth.at(4).unwrap().data().unwrap()).to_be_bytes::<32>(),
        U256::from_be_slice(auth.at(5).unwrap().data().unwrap()).to_be_bytes::<32>(),
    )
    .unwrap();
    let public = VerifyingKey::recover_from_prehash(
        alloy_primitives::keccak256(input).as_slice(),
        &signature,
        RecoveryId::from_byte(auth.val_at(3).unwrap()).unwrap(),
    )
    .unwrap();
    assert_eq!(&public, key().verifying_key());
    let call = abi::executeCall::abi_decode(fields.at(7).unwrap().data().unwrap(), true).unwrap();
    assert_eq!(call.deadline, U256::from(2_000_000_000));
    assert_eq!(call.calls.len(), 2);
    assert_eq!(call.calls[0].target, address(CBZEC).unwrap());
    assert_eq!(call.calls[1].target, address(&c.registry).unwrap());
    assert_eq!(
        abi::approveCall::abi_decode(&call.calls[0].data, true)
            .unwrap()
            .amount,
        U256::from(500000)
    );
}

#[test]
fn signer_rejects_policy_and_unknown_operation_escape_routes() {
    let mut c = config();
    c.chain_id = 1;
    assert!(sign(&key(), &c, &register(), &tx()).is_err());
    c = config();
    c.token = c.registry.clone();
    assert!(sign(&key(), &c, &register(), &tx()).is_err());
    c = config();
    c.max_gas_limit = "499999".into();
    assert!(sign(&key(), &c, &register(), &tx()).is_err());
    c = config();
    c.max_total_fee_wei = "50000000000000".into();
    assert!(sign(&key(), &c, &register(), &tx()).is_err());
    let mut fees = tx();
    fees.max_priority_fee_per_gas = "100000001".into();
    assert!(sign(&key(), &config(), &register(), &fees).is_err());
    assert!(prepare(
        &config(),
        &key_address(&key()).to_string(),
        &Operation::Approve {
            amount: "1000001".into()
        }
    )
    .is_err());
    assert!(serde_json::from_str::<Operation>(
        r#"{"kind":"transfer","to":"0x1111111111111111111111111111111111111111"}"#
    )
    .is_err());
    assert!(serde_json::from_str::<Operation>(
        r#"{"kind":"withdraw","to":"0x1111111111111111111111111111111111111111"}"#
    )
    .is_err());
}

fn swap_data(owner: Address) -> abi::swapCall {
    abi::swapCall {
        execution: abi::SwapExecutionParams {
            callTarget: Address::repeat_byte(8),
            approveTarget: Address::ZERO,
            targetData: Bytes::from(vec![1, 2, 3, 4]),
            clientData: Bytes::new(),
            desc: abi::SwapDescription {
                srcToken: address("0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee").unwrap(),
                dstToken: address(CBZEC).unwrap(),
                srcReceivers: vec![],
                srcAmounts: vec![],
                feeReceivers: vec![],
                feeAmounts: vec![],
                dstReceiver: owner,
                amount: U256::from(10000),
                minReturnAmount: U256::from(500000),
                flags: U256::from(512),
                permit: Bytes::new(),
            },
        },
    }
}

#[test]
fn router_validation_rejects_modified_asset_recipient_value_and_flags() {
    let owner = key_address(&key());
    let c = config();
    let original = swap_data(owner);
    let validate = |call: &abi::swapCall| {
        abi::validate_swap(
            &format!("0x{}", hex::encode(call.abi_encode())),
            "10000",
            "500000",
            owner,
            address(CBZEC).unwrap(),
            number(&c.max_value_wei).unwrap(),
        )
    };
    assert!(validate(&original).is_ok());
    let mut call = swap_data(owner);
    call.execution.desc.dstReceiver = Address::repeat_byte(9);
    assert!(validate(&call).is_err());
    let mut call = swap_data(owner);
    call.execution.desc.minReturnAmount = U256::from(499999);
    assert!(validate(&call).is_err());
    let mut call = swap_data(owner);
    call.execution.desc.amount = U256::from(10001);
    assert!(validate(&call).is_err());
    let mut call = swap_data(owner);
    call.execution.desc.flags = U256::from(1);
    assert!(validate(&call).is_err());
    let mut call = swap_data(owner);
    call.execution.desc.permit = Bytes::from(vec![1]);
    assert!(validate(&call).is_err());
    let mut call = swap_data(owner);
    call.execution.desc.dstToken = Address::repeat_byte(9);
    assert!(validate(&call).is_err());
    let mut data = original.abi_encode();
    data.push(0);
    assert!(abi::validate_swap(
        &format!("0x{}", hex::encode(data)),
        "10000",
        "500000",
        owner,
        address(CBZEC).unwrap(),
        number(&c.max_value_wei).unwrap()
    )
    .is_err());
}

#[test]
fn read_abi_vectors_and_name_validation() {
    assert_eq!(
        abi::read_call("decimals", &serde_json::json!({})).unwrap(),
        "0x313ce567"
    );
    assert_eq!(
        abi::read_call("withdrawBond", &serde_json::json!({})).unwrap_err(),
        "Unsupported ZNS read method"
    );
    assert_eq!(
        abi::decode_result(
            "fixedDeposit",
            &format!("0x{}", hex::encode(U256::from(42).abi_encode()))
        )
        .unwrap(),
        serde_json::json!("42")
    );
    let text_result = format!(
        "0x{:064x}{:064x}{}",
        32, 5, "616c696365000000000000000000000000000000000000000000000000000000"
    );
    assert_eq!(
        abi::decode_result("resolve", &text_result).unwrap(),
        serde_json::json!("alice")
    );
    assert_eq!(
        abi::decode_result("decimals", &format!("0x{:064x}", 8)).unwrap(),
        serde_json::json!(8)
    );
    let record_result = format!("0x0000000000000000000000001111111111111111111111111111111111111111{:064x}{:064x}{:064x}{:064x}{}",128,2000000000,1,5,"616c696365000000000000000000000000000000000000000000000000000000");
    assert_eq!(
        abi::decode_result("recordOf", &record_result).unwrap(),
        serde_json::json!({"registrant":"0x1111111111111111111111111111111111111111","unifiedAddress":"alice","expiry":"2000000000","active":true})
    );
    for bad in ["", "ALICE", "alice.zec", "-alice", "alice-", "alíce"] {
        assert!(validate_name(bad).is_err());
    }
    assert!(validate_name("a-1").is_ok());
}

#[test]
fn independent_kyber_mainnet_dry_calldata_is_accepted_and_executor_is_pinned() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../tests/fixtures/kyber-native-cbzec.json")).unwrap();
    let op = Operation::Swap {
        data: fixture["data"].as_str().unwrap().into(),
        value: fixture["value"].as_str().unwrap().into(),
        minimum_output: fixture["minimumOutput"].as_str().unwrap().into(),
    };
    let owner = fixture["owner"].as_str().unwrap();
    let prepared = prepare(&config(), owner, &op).unwrap();
    assert_eq!(prepared.to, address(KYBER).unwrap().to_checksum(None));
    assert_eq!(prepared.value, "1000000000000000");
    let mut call = abi::swapCall::abi_decode(&bytes(&prepared.data).unwrap(), true).unwrap();
    call.execution.callTarget = Address::repeat_byte(7);
    let op = Operation::Swap {
        data: format!("0x{}", hex::encode(call.abi_encode())),
        value: prepared.value,
        minimum_output: "210000".into(),
    };
    assert!(prepare(&config(), owner, &op)
        .unwrap_err()
        .contains("executor"));
}

#[test]
fn atomic_swap_uses_existing_partial_balance_and_binds_deadline() {
    let mut c = config();
    c.chain_id = 31337;
    c.allow_test_chain = true;
    let mut call = swap_data(key_address(&key()));
    call.execution.desc.minReturnAmount = U256::from(300000);
    let swap = Swap {
        data: format!("0x{}", hex::encode(call.abi_encode())),
        value: "10000".into(),
        minimum_output: "300000".into(),
    };
    let mut operation = atomic(Some(swap));
    assert!(prepare(&c, &key_address(&key()).to_string(), &operation).is_err());
    if let Operation::AtomicRegister {
        existing_token_units,
        ..
    } = &mut operation
    {
        *existing_token_units = "200000".into();
    }
    let prepared = prepare(&c, &key_address(&key()).to_string(), &operation).unwrap();
    let call = abi::executeCall::abi_decode(&bytes(&prepared.data).unwrap(), true).unwrap();
    assert_eq!(call.calls.len(), 3);
    assert_eq!(call.calls[0].value, U256::from(10000));
    assert_eq!(prepared.value, "0");
    if let Operation::AtomicRegister { deadline, .. } = &mut operation {
        *deadline = "0".into();
    }
    assert!(prepare(&c, &key_address(&key()).to_string(), &operation).is_err());
}

#[test]
fn nft_transfer_binds_owner_recipient_and_position_without_spending_cbzec() {
    let c = config();
    let owner = key_address(&key()).to_string();
    let recipient = "0x4444444444444444444444444444444444444444";
    let operation = Operation::Transfer {
        position_id: "42".into(),
        recipient: recipient.into(),
    };
    let prepared = prepare(&c, &owner, &operation).unwrap();
    assert_eq!(prepared.to, c.registry);
    assert_eq!(prepared.value, "0");
    assert!(prepared.data.starts_with("0x42842e0e"));
    let decoded =
        abi::safeTransferFromCall::abi_decode(&bytes(&prepared.data).unwrap(), true).unwrap();
    assert_eq!(decoded.from, address(&owner).unwrap());
    assert_eq!(decoded.to, address(recipient).unwrap());
    assert_eq!(decoded.tokenId, U256::from(42));
    assert!(sign(&key(), &c, &operation, &tx()).is_ok());
    for invalid in [
        owner.as_str(),
        c.registry.as_str(),
        "0x0000000000000000000000000000000000000000",
        "invalid",
    ] {
        assert!(prepare(
            &c,
            &owner,
            &Operation::Transfer {
                position_id: "42".into(),
                recipient: invalid.into()
            }
        )
        .is_err());
    }
    assert!(prepare(
        &c,
        &owner,
        &Operation::Transfer {
            position_id: "0".into(),
            recipient: recipient.into()
        }
    )
    .is_err());
    assert!(serde_json::from_value::<Operation>(serde_json::json!({"kind":"transfer","positionId":"42","recipient":recipient,"from":recipient})).is_err());
}
