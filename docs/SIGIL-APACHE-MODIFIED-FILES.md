# Apache modified-file inventory

This snapshot is generated from the upstream base and the current tracked working tree for an owner-led
Apache License 2.0 section 4(b) review. It does not add headers or make
a copyright or redistribution decision. Re-run the tool after the fork
or target feature set changes.

- Base: `upstream/main`
- Head: `WORKTREE`
- Modified paths: 146
- Added paths: 166
- Source candidates among modified paths: 124

## Source modification-notice coverage

The table reports the exact Sigil modification marker in each source file.
Recheck the list after future upstream integration; files may be generated, vendored,
or excluded from a particular target, and every existing upstream notice
must be preserved. Inventory mode does not modify these files.

| Path | Sigil modification marker in first 40 lines |
| --- | --- |
| `android/app/src/main/kotlin/com/keplr/vizor/DeviceOwnerAuthHandler.kt` | yes |
| `android/app/src/main/kotlin/com/keplr/vizor/MainActivity.kt` | yes |
| `ios/Runner/BiometricUnlockHandler.swift` | yes |
| `ios/SyncWidget/SyncWidgetLiveActivity.swift` | yes |
| `lib/app.dart` | yes |
| `lib/src/app_bootstrap.dart` | yes |
| `lib/src/core/layout/app_desktop_shell.dart` | yes |
| `lib/src/core/layout/app_layout.dart` | yes |
| `lib/src/core/layout/app_main_sidebar.dart` | yes |
| `lib/src/core/layout/mobile/app_mobile_tab_bar.dart` | yes |
| `lib/src/core/navigation/app_back_resolver.dart` | yes |
| `lib/src/core/navigation/mobile_routes.dart` | yes |
| `lib/src/core/storage/app_secure_store.dart` | yes |
| `lib/src/core/storage/linux_keyring_coordinator.dart` | yes |
| `lib/src/core/theme/app_theme.dart` | yes |
| `lib/src/core/theme/colors/app_background_colors.dart` | yes |
| `lib/src/core/theme/colors/app_border_colors.dart` | yes |
| `lib/src/core/theme/colors/app_button_colors.dart` | yes |
| `lib/src/core/theme/colors/app_colors.dart` | yes |
| `lib/src/core/theme/colors/app_fade_colors.dart` | yes |
| `lib/src/core/theme/colors/app_icon_colors.dart` | yes |
| `lib/src/core/theme/colors/app_macos_utility_colors.dart` | yes |
| `lib/src/core/theme/colors/app_nav_panel_colors.dart` | yes |
| `lib/src/core/theme/colors/app_shadow_colors.dart` | yes |
| `lib/src/core/theme/colors/app_state_colors.dart` | yes |
| `lib/src/core/theme/colors/app_surface_colors.dart` | yes |
| `lib/src/core/theme/colors/app_sync_colors.dart` | yes |
| `lib/src/core/theme/colors/app_text_colors.dart` | yes |
| `lib/src/core/theme/legacy_material_theme.dart` | yes |
| `lib/src/core/theme/primitives.dart` | yes |
| `lib/src/core/widgets/app_button.dart` | yes |
| `lib/src/core/widgets/linux_keyring_gate.dart` | yes |
| `lib/src/features/about/about_content.dart` | yes |
| `lib/src/features/about/screens/about_screen.dart` | yes |
| `lib/src/features/about/screens/mobile/mobile_about_screens.dart` | yes |
| `lib/src/features/address_book/models/address_book_contact.dart` | yes |
| `lib/src/features/address_book/providers/address_book_provider.dart` | yes |
| `lib/src/features/address_book/screens/address_book_screen.dart` | yes |
| `lib/src/features/address_book/screens/mobile/mobile_address_book_screen.dart` | yes |
| `lib/src/features/home/screens/home_screen.dart` | yes |
| `lib/src/features/home/screens/mobile/mobile_home_screen.dart` | yes |
| `lib/src/features/onboarding/import/import_birthday_unknown_height_modal.dart` | yes |
| `lib/src/features/onboarding/keystone/keystone_how_to_connect_screen.dart` | yes |
| `lib/src/features/onboarding/lost_password_screen.dart` | yes |
| `lib/src/features/onboarding/mobile/forgot_passcode_sheet.dart` | yes |
| `lib/src/features/onboarding/mobile/mobile_import_birthday_unknown_height_sheet.dart` | yes |
| `lib/src/features/onboarding/mobile/mobile_keystone_screens.dart` | yes |
| `lib/src/features/onboarding/mobile/mobile_method_selection_screen.dart` | yes |
| `lib/src/features/onboarding/mobile/mobile_unlock_screen.dart` | yes |
| `lib/src/features/onboarding/mobile/mobile_wallet_link_screens.dart` | yes |
| `lib/src/features/onboarding/shared/onboarding_welcome_art.dart` | yes |
| `lib/src/features/onboarding/shared/set_password_screen.dart` | yes |
| `lib/src/features/onboarding/storage_unavailable_screen.dart` | yes |
| `lib/src/features/onboarding/unlock_screen.dart` | yes |
| `lib/src/features/onboarding/welcome.dart` | yes |
| `lib/src/features/receive/screens/receive_screen.dart` | yes |
| `lib/src/features/send/models/send_prefill_args.dart` | yes |
| `lib/src/features/send/screens/mobile/mobile_send_screen.dart` | yes |
| `lib/src/features/send/screens/send_review_screen.dart` | yes |
| `lib/src/features/send/screens/send_screen.dart` | yes |
| `lib/src/features/send/screens/send_status_screen.dart` | yes |
| `lib/src/features/send/services/send_flow.dart` | yes |
| `lib/src/features/send/widgets/send_compose_view.dart` | yes |
| `lib/src/features/send/widgets/send_recipient_resolver.dart` | yes |
| `lib/src/features/send/widgets/send_review_content_view.dart` | yes |
| `lib/src/features/send/widgets/send_review_layout.dart` | yes |
| `lib/src/features/send/widgets/send_status_content_view.dart` | yes |
| `lib/src/features/settings/screens/mobile/mobile_settings_screen.dart` | yes |
| `lib/src/features/settings/screens/settings_screen.dart` | yes |
| `lib/src/features/settings/screens/settings_uninstall_screen.dart` | yes |
| `lib/src/features/settings/widgets/confirm_access_card.dart` | yes |
| `lib/src/features/settings/widgets/settings_pane_backdrop.dart` | yes |
| `lib/src/features/settings/widgets/windows_update_download_flow.dart` | yes |
| `lib/src/features/swap/providers/swap_deposit_sender.dart` | yes |
| `lib/src/features/swap/screens/mobile/mobile_swap_screen.dart` | yes |
| `lib/src/features/wallet_link/screens/wallet_link_desktop_screen.dart` | yes |
| `lib/src/providers/account_provider.dart` | yes |
| `lib/src/providers/app_security_provider.dart` | yes |
| `lib/src/providers/device_owner_auth_provider.dart` | yes |
| `lib/src/providers/sync_failure.dart` | yes |
| `lib/widgetbook/send_review_status_use_cases.dart` | yes |
| `lib/widgetbook/typography_use_cases.dart` | yes |
| `macos/Runner/AppDelegate.swift` | yes |
| `macos/Runner/MainFlutterWindow.swift` | yes |
| `rust/src/api/mod.rs` | yes |
| `rust/src/wallet/mod.rs` | yes |
| `rust/src/wallet/sync_engine/mod.rs` | yes |
| `test/app_linux_update_notice_test.dart` | yes |
| `test/app_main_sidebar_test.dart` | yes |
| `test/app_windows_update_prompt_test.dart` | yes |
| `test/core/navigation/mobile_routes_test.dart` | yes |
| `test/core/storage/app_secure_store_test.dart` | yes |
| `test/core/storage/linux_keyring_coordinator_test.dart` | yes |
| `test/core/theme/android_system_bars_test.dart` | yes |
| `test/core/theme/design_tokens_test.dart` | yes |
| `test/core/widgets/linux_keyring_gate_test.dart` | yes |
| `test/features/about/about_legal_pages_test.dart` | yes |
| `test/features/home/home_desktop_screen_test.dart` | yes |
| `test/features/home/mobile_home_screen_test.dart` | yes |
| `test/features/migration/ironwood_migration_privacy_lock_host_test.dart` | yes |
| `test/features/onboarding/keystone_how_to_connect_screen_test.dart` | yes |
| `test/features/onboarding/lost_password_screen_test.dart` | yes |
| `test/features/onboarding/mobile_keystone_intro_screen_test.dart` | yes |
| `test/features/onboarding/mobile_unlock_screen_test.dart` | yes |
| `test/features/onboarding/mobile_welcome_screen_test.dart` | yes |
| `test/features/send/mobile_send_screen_test.dart` | yes |
| `test/features/send/payment_request_pane_layout_test.dart` | yes |
| `test/features/send/send_recipient_resolver_test.dart` | yes |
| `test/features/send/send_review_content_view_test.dart` | yes |
| `test/features/send/send_review_screen_test.dart` | yes |
| `test/features/send/send_screen_test.dart` | yes |
| `test/features/send/send_status_content_view_test.dart` | yes |
| `test/features/send/send_status_screen_test.dart` | yes |
| `test/features/settings/mobile_settings_screen_test.dart` | yes |
| `test/features/settings/settings_screen_test.dart` | yes |
| `test/features/settings/settings_uninstall_screen_test.dart` | yes |
| `test/sync_failure_test.dart` | yes |
| `test/widgetbook/accounts_use_cases_test.dart` | yes |
| `test/widgetbook/mobile_keystone_use_cases_test.dart` | yes |
| `test/widgetbook/mobile_lock_use_cases_test.dart` | yes |
| `test/widgetbook/send_review_status_use_cases_test.dart` | yes |
| `test/widgetbook/settings_use_cases_test.dart` | yes |
| `windows/runner/flutter_window.cpp` | yes |
| `windows/runner/main.cpp` | yes |

## Excluded source paths

Generated and vendored source paths are shown separately so that an
owner can make an explicit target decision. They are never passed
to the opt-in header writer.

| Path | Reason |
| --- | --- |
| `lib/src/rust/api/network_privacy.dart` | generated |
| `lib/src/rust/api/voting.dart` | generated |
| `lib/src/rust/frb_generated.dart` | generated |
| `lib/src/rust/frb_generated.io.dart` | generated |
| `lib/src/rust/frb_generated.web.dart` | generated |
| `lib/src/rust/third_party/zcash_voting/wire.dart` | generated |
| `rust/src/frb_generated.rs` | generated |
| `rust_builder/cargokit/build_tool/lib/src/rustup.dart` | vendored |

## Modified non-source paths

These paths remain in the full inventory for review but are not
proposed for a source-language header by this tool.

| Path | Category |
| --- | --- |
| `.gitignore` | other |
| `README.md` | documentation-or-data |
| `android/app/build.gradle.kts` | build-or-metadata |
| `android/app/src/main/AndroidManifest.xml` | build-or-metadata |
| `dart_test.yaml` | build-or-metadata |
| `fastlane/metadata/android/en-US/full_description.txt` | documentation-or-data |
| `fastlane/metadata/android/en-US/title.txt` | documentation-or-data |
| `ios/Runner/Info.plist` | build-or-metadata |
| `lib/src/rust/api/network_privacy.dart` | source |
| `lib/src/rust/api/voting.dart` | source |
| `lib/src/rust/frb_generated.dart` | source |
| `lib/src/rust/frb_generated.io.dart` | source |
| `lib/src/rust/frb_generated.web.dart` | source |
| `lib/src/rust/third_party/zcash_voting/wire.dart` | source |
| `linux/CMakeLists.txt` | documentation-or-data |
| `macos/Runner/Info.plist` | build-or-metadata |
| `pubspec.lock` | other |
| `pubspec.yaml` | build-or-metadata |
| `rust/Cargo.lock` | other |
| `rust/Cargo.toml` | other |
| `rust/src/frb_generated.rs` | source |
| `rust_builder/cargokit/build_tool/lib/src/rustup.dart` | source |

## Added paths

Added files do not replace the section 4(b) review of modified
upstream files. They still need an explicit rights-holder and license
decision before distribution.

| Path | Category |
| --- | --- |
| `CONTACT-EXPERIMENT.md` | documentation-or-data |
| `FAMILIAR-UI.md` | documentation-or-data |
| `README-ZNS.md` | documentation-or-data |
| `UI-FOLLOWUPS.md` | documentation-or-data |
| `UPSTREAM-INTEGRATION.md` | documentation-or-data |
| `docs/zns-testnet-build.md` | documentation-or-data |
| `lib/src/core/theme/familiar_palette.dart` | source |
| `lib/src/core/widgets/familiar_widgets.dart` | source |
| `lib/src/features/contacts/application/contact_backup_coordinator.dart` | source |
| `lib/src/features/contacts/application/contact_backup_providers.dart` | source |
| `lib/src/features/contacts/application/contact_binding_coordinator.dart` | source |
| `lib/src/features/contacts/application/contact_delivery_coordinator.dart` | source |
| `lib/src/features/contacts/application/contact_delivery_providers.dart` | source |
| `lib/src/features/contacts/application/contact_exchange_controller.dart` | source |
| `lib/src/features/contacts/application/contact_introduction_coordinator.dart` | source |
| `lib/src/features/contacts/application/contact_introduction_providers.dart` | source |
| `lib/src/features/contacts/application/contact_lifecycle.dart` | source |
| `lib/src/features/contacts/application/contact_mutation_gate.dart` | source |
| `lib/src/features/contacts/application/contact_ui_preferences.dart` | source |
| `lib/src/features/contacts/application/familiar_people_metadata_provider.dart` | source |
| `lib/src/features/contacts/data/contact_backup_store.dart` | source |
| `lib/src/features/contacts/data/contact_binding_repository.dart` | source |
| `lib/src/features/contacts/data/contact_delivery_repository.dart` | source |
| `lib/src/features/contacts/data/contact_gateway.dart` | source |
| `lib/src/features/contacts/data/contact_introduction_gateway.dart` | source |
| `lib/src/features/contacts/data/contact_introduction_repository.dart` | source |
| `lib/src/features/contacts/data/contact_repository.dart` | source |
| `lib/src/features/contacts/data/familiar_people_metadata_repository.dart` | source |
| `lib/src/features/contacts/data/simplex_native_transport.dart` | source |
| `lib/src/features/contacts/domain/contact_connection_binding.dart` | source |
| `lib/src/features/contacts/domain/contact_delivery.dart` | source |
| `lib/src/features/contacts/domain/contact_introduction_models.dart` | source |
| `lib/src/features/contacts/domain/contact_models.dart` | source |
| `lib/src/features/contacts/domain/contact_packet_kind.dart` | source |
| `lib/src/features/contacts/domain/familiar_person.dart` | source |
| `lib/src/features/contacts/presentation/contact_backup_screen.dart` | source |
| `lib/src/features/contacts/presentation/contact_code_widgets.dart` | source |
| `lib/src/features/contacts/presentation/contact_connection_binding_panel.dart` | source |
| `lib/src/features/contacts/presentation/contact_delivery_screen.dart` | source |
| `lib/src/features/contacts/presentation/contact_exchange_screen.dart` | source |
| `lib/src/features/contacts/presentation/contact_introduction_screen.dart` | source |
| `lib/src/features/contacts/presentation/contact_packet_delivery_controls.dart` | source |
| `lib/src/features/contacts/presentation/familiar_add_person_screen.dart` | source |
| `lib/src/features/contacts/presentation/familiar_choose_recipient_screen.dart` | source |
| `lib/src/features/contacts/presentation/familiar_people_screen.dart` | source |
| `lib/src/features/contacts/presentation/familiar_saved_person_detail.dart` | source |
| `lib/src/features/home/widgets/familiar_home_dashboard.dart` | source |
| `lib/src/features/settings/base_key_export.dart` | source |
| `lib/src/features/settings/contact_settings.dart` | source |
| `lib/src/features/settings/names_settings.dart` | source |
| `lib/src/features/settings/screens/settings_base_key_screen.dart` | source |
| `lib/src/features/zns/README.md` | documentation-or-data |
| `lib/src/features/zns/application/public_name_lookup.dart` | source |
| `lib/src/features/zns/application/zns_batch_bytecode.dart` | source |
| `lib/src/features/zns/application/zns_confirmed_transaction.dart` | source |
| `lib/src/features/zns/application/zns_controller.dart` | source |
| `lib/src/features/zns/application/zns_engine.dart` | source |
| `lib/src/features/zns/application/zns_journal.dart` | source |
| `lib/src/features/zns/application/zns_lifecycle_guard.dart` | source |
| `lib/src/features/zns/application/zns_wallet_gateway.dart` | source |
| `lib/src/features/zns/data/zns_abi.dart` | source |
| `lib/src/features/zns/data/zns_build_defaults.dart` | source |
| `lib/src/features/zns/data/zns_funding_gateway.dart` | source |
| `lib/src/features/zns/data/zns_http_transport.dart` | source |
| `lib/src/features/zns/data/zns_kyber_gateway.dart` | source |
| `lib/src/features/zns/data/zns_network_config.dart` | source |
| `lib/src/features/zns/data/zns_rpc_client.dart` | source |
| `lib/src/features/zns/domain/zns_operation.dart` | source |
| `lib/src/features/zns/presentation/public_name_lookup_card.dart` | source |
| `lib/src/features/zns/presentation/zns_screen.dart` | source |
| `lib/src/features/zns/presentation/zns_view_data.dart` | source |
| `lib/src/features/zns/presentation/zns_wallet_screen.dart` | source |
| `lib/src/rust/api/contact_backup.dart` | source (generated) |
| `lib/src/rust/api/contacts.dart` | source (generated) |
| `lib/src/rust/api/zns.dart` | source (generated) |
| `lib/zns_preview.dart` | source |
| `rust/contact-core/Cargo.lock` | other |
| `rust/contact-core/Cargo.toml` | other |
| `rust/contact-core/README.md` | documentation-or-data |
| `rust/contact-core/src/introduction.rs` | source |
| `rust/contact-core/src/introduction/tests.rs` | source |
| `rust/contact-core/src/lib.rs` | source |
| `rust/contact-core/src/tests.rs` | source |
| `rust/contact-core/tests/corpus_support.rs` | source |
| `rust/contact-core/tests/fixtures/introduction-vectors.json` | documentation-or-data |
| `rust/contact-core/tests/introduction_corpus.rs` | source |
| `rust/src/api/contact_backup.rs` | source |
| `rust/src/api/contacts.rs` | source |
| `rust/src/api/zns.rs` | source |
| `rust/src/wallet/account_secret.rs` | source |
| `rust/src/wallet/contact_backup.rs` | source |
| `rust/src/wallet/contacts.rs` | source |
| `rust/src/wallet/zns.rs` | source |
| `rust/zns-core/.gitignore` | other |
| `rust/zns-core/Cargo.lock` | other |
| `rust/zns-core/Cargo.toml` | other |
| `rust/zns-core/README.md` | documentation-or-data |
| `rust/zns-core/examples/local_sign.rs` | source |
| `rust/zns-core/src/abi.rs` | source |
| `rust/zns-core/src/lib.rs` | source |
| `rust/zns-core/src/tests.rs` | source |
| `rust/zns-core/src/transaction.rs` | source |
| `rust/zns-core/tests/fixtures/kyber-native-cbzec.json` | documentation-or-data |
| `rust/zns-core/tests/fixtures/tiered-registration.json` | documentation-or-data |
| `scripts/build-sigil-testnet.sh` | source |
| `scripts/contact-check/linux_wallet.py` | source |
| `scripts/zns/output/qualification.json` | documentation-or-data |
| `scripts/zns/package-lock.json` | documentation-or-data |
| `scripts/zns/package.json` | documentation-or-data |
| `scripts/zns/qualify.mjs` | other |
| `test/features/contacts/application/contact_ui_preferences_test.dart` | source |
| `test/features/contacts/contact_backup_test.dart` | source |
| `test/features/contacts/contact_binding_coordinator_test.dart` | source |
| `test/features/contacts/contact_delivery_test.dart` | source |
| `test/features/contacts/contact_exchange_controller_test.dart` | source |
| `test/features/contacts/contact_introduction_coordinator_test.dart` | source |
| `test/features/contacts/contact_introduction_repository_test.dart` | source |
| `test/features/contacts/contact_introduction_test_fixtures.dart` | source |
| `test/features/contacts/contact_lifecycle_test.dart` | source |
| `test/features/contacts/contact_models_test.dart` | source |
| `test/features/contacts/contact_native_exchange_test.dart` | source |
| `test/features/contacts/contact_native_introduction_test.dart` | source |
| `test/features/contacts/contact_packet_kind_test.dart` | source |
| `test/features/contacts/contact_repository_test.dart` | source |
| `test/features/contacts/contact_signer_persistence_test.dart` | source |
| `test/features/contacts/contact_test_fakes.dart` | source |
| `test/features/contacts/contact_test_fixtures.dart` | source |
| `test/features/contacts/familiar_people_metadata_test.dart` | source |
| `test/features/contacts/familiar_people_rename_test.dart` | source |
| `test/features/contacts/presentation/contact_backup_screen_test.dart` | source |
| `test/features/contacts/presentation/contact_delivery_screen_test.dart` | source |
| `test/features/contacts/presentation/contact_exchange_behavior_support.dart` | source |
| `test/features/contacts/presentation/contact_exchange_capture_support.dart` | source |
| `test/features/contacts/presentation/contact_exchange_desktop_layout_test.dart` | source |
| `test/features/contacts/presentation/contact_exchange_fixtures.dart` | source |
| `test/features/contacts/presentation/contact_exchange_mobile_layout_test.dart` | source |
| `test/features/contacts/presentation/contact_exchange_test_support.dart` | source |
| `test/features/contacts/presentation/contact_exchange_view_test.dart` | source |
| `test/features/contacts/presentation/contact_guided_exchange_test.dart` | source |
| `test/features/contacts/presentation/contact_introduction_behavior_support.dart` | source |
| `test/features/contacts/presentation/contact_introduction_mobile_test.dart` | source |
| `test/features/contacts/presentation/contact_introduction_view_test.dart` | source |
| `test/features/contacts/presentation/contact_packet_delivery_controls_test.dart` | source |
| `test/features/contacts/presentation/familiar_manual_person_mobile_test.dart` | source |
| `test/features/contacts/presentation/familiar_manual_person_test.dart` | source |
| `test/features/contacts/presentation/familiar_people_mobile_test.dart` | source |
| `test/features/contacts/presentation/familiar_people_view_test.dart` | source |
| `test/features/contacts/simplex_native_transport_test.dart` | source |
| `test/features/contacts/support/file_contact_storage.dart` | source |
| `test/features/home/familiar_home_dashboard_test.dart` | source |
| `test/features/send/contact_send_continuity_test.dart` | source |
| `test/features/settings/settings_base_key_screen_test.dart` | source |
| `test/features/zns/application/zns_confirmed_transaction_test.dart` | source |
| `test/features/zns/application/zns_engine_test.dart` | source |
| `test/features/zns/application/zns_recovery_test.dart` | source |
| `test/features/zns/data/zns_funding_gateway_test.dart` | source |
| `test/features/zns/data/zns_kyber_gateway_test.dart` | source |
| `test/features/zns/data/zns_rpc_client_test.dart` | source |
| `test/features/zns/presentation/public_name_lookup_card_test.dart` | source |
| `test/features/zns/presentation/zns_capture_support.dart` | source |
| `test/features/zns/presentation/zns_desktop_layout_test.dart` | source |
| `test/features/zns/presentation/zns_mobile_layout_test.dart` | source |
| `test/features/zns/presentation/zns_screen_test.dart` | source |
| `test/features/zns/zns_build_defaults_test.dart` | source |
| `tools/simplex/README.md` | documentation-or-data |
| `tools/simplex/native_host.c` | source |
