mod corpus_support;

#[test]
fn reviewed_315_vectors_match_with_explicit_fixture_address_oracle() {
    // Codec-only harness: native wallet tests rerun the same corpus with the
    // pinned real UA decoder. No prefix/checksum approximation is used here.
    const UA: &str = "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn";
    corpus_support::check_introduction_corpus(|network, address| {
        network == vizor_contact_core::Network::Regtest && address == UA
    });
}
