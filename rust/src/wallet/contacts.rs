//! Pure address validation for the testnet/regtest direct-contact experiment.

use super::network::WalletNetwork;
use vizor_contact_core::Network;
use zcash_keys::address::Address;

pub fn validate_unified_address(network: Network, address: &str) -> bool {
    if address.is_empty() || address.len() > 512 || address.trim() != address {
        return false;
    }
    let wallet_network = match network {
        Network::Test => WalletNetwork::Test,
        Network::Regtest => WalletNetwork::Regtest,
    };
    match Address::decode(&wallet_network, address) {
        Some(decoded @ Address::Unified(_)) => decoded.encode(&wallet_network) == address,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_address::ToAddress;
    use zcash_protocol::consensus::NetworkType;

    // Public deterministic fixture from rust/tests/regtest_import.rs. No DB or
    // wallet state is needed to exercise the real decoder and network encoding.
    fn fixture(network: NetworkType) -> String {
        const REGTEST_UA: &str = "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn";
        let network = match network {
            NetworkType::Main => WalletNetwork::Main,
            NetworkType::Test => WalletNetwork::Test,
            NetworkType::Regtest => WalletNetwork::Regtest,
        };
        Address::decode(&WalletNetwork::Regtest, REGTEST_UA)
            .unwrap()
            .encode(&network)
    }

    #[test]
    fn validates_real_canonical_unified_addresses_for_selected_network_only() {
        let test = fixture(NetworkType::Test);
        let regtest = fixture(NetworkType::Regtest);
        let main = fixture(NetworkType::Main);
        assert!(validate_unified_address(Network::Test, &test));
        assert!(validate_unified_address(Network::Regtest, &regtest));
        assert!(!validate_unified_address(Network::Regtest, &test));
        assert!(!validate_unified_address(Network::Test, &regtest));
        assert!(!validate_unified_address(Network::Test, &main));
        assert!(!validate_unified_address(
            Network::Test,
            &test.to_uppercase()
        ));
        assert!(!validate_unified_address(
            Network::Test,
            &format!(" {test}")
        ));
        assert!(!validate_unified_address(
            Network::Test,
            &format!("{test}\n")
        ));
        let mut bad_checksum = test.clone();
        bad_checksum.pop();
        bad_checksum.push(if test.ends_with('q') { 'p' } else { 'q' });
        assert!(!validate_unified_address(Network::Test, &bad_checksum));
        let transparent =
            zcash_address::ZcashAddress::from_transparent_p2pkh(NetworkType::Test, [7; 20])
                .to_string();
        assert!(!validate_unified_address(Network::Test, &transparent));
        assert!(!validate_unified_address(Network::Test, "demo-only:alice"));
        assert!(!validate_unified_address(Network::Test, "u1invalid"));
        assert!(!validate_unified_address(Network::Test, &"u".repeat(513)));
    }
}
