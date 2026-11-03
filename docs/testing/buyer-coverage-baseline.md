# Buyer branch-coverage baseline

Source baseline: merged main `c2c2342`. A fresh 1,515-test run passed in 11:48 before production changes. This is a starting inventory, not the final coverage result.

Flutter reported **4,307/5,942 branch counters hit (72.484%)**. Its installed collector merges counters by source line; this does not prove every condition outcome. The full machine-readable missing-counter inventory can be regenerated with the commands in the sweep plan.

## Initial runtime-source backlog

Counts below come from the untouched baseline LCOV. Source line keys must be refreshed after fixes rather than merged across shifted source revisions.

| Source | Hit | Found | Uncovered |
| --- | ---: | ---: | ---: |
| lib/features/home/home_page.dart | 94 | 205 | 111 |
| lib/features/profile/profile_page.dart | 83 | 168 | 85 |
| lib/features/products/product_page.dart | 184 | 266 | 82 |
| lib/features/checkout/checkout_page.dart | 224 | 303 | 79 |
| lib/features/profile/order_detail_page.dart | 138 | 207 | 69 |
| lib/features/profile/identity_section.dart | 118 | 185 | 67 |
| lib/features/engagement/buyer_destination_router.dart | 36 | 99 | 63 |
| lib/features/checkout/order_result_page.dart | 98 | 148 | 50 |
| lib/features/home/search_page.dart | 59 | 109 | 50 |
| lib/features/profile/returns_page.dart | 151 | 197 | 46 |
| lib/main.dart | 71 | 117 | 46 |
| lib/features/auth/register_page.dart | 86 | 130 | 44 |
| lib/features/checkout/bag_page.dart | 140 | 181 | 41 |
| lib/features/products/shop_page.dart | 84 | 125 | 41 |
| lib/core/buyer_repository.dart | 73 | 112 | 39 |
| lib/features/notifications/notifications_page.dart | 77 | 116 | 39 |
| lib/features/profile/sessions_section.dart | 80 | 114 | 34 |
| lib/features/products/chat_page.dart | 70 | 99 | 29 |
| lib/core/web_session.dart | 109 | 135 | 26 |
| lib/features/auth/password_link_page.dart | 55 | 78 | 23 |
| lib/features/collections/saved_products_page.dart | 45 | 67 | 22 |
| lib/features/collections/followed_shops_page.dart | 51 | 72 | 21 |
| lib/features/profile/profile_widgets.dart | 93 | 114 | 21 |
| lib/features/products/product_model.dart | 128 | 148 | 20 |
| lib/features/support/support_assistant_page.dart | 63 | 83 | 20 |
| lib/features/profile/email_section.dart | 59 | 77 | 18 |
| lib/features/profile/purchases_section.dart | 52 | 70 | 18 |
| lib/features/notifications/notification_preview.dart | 33 | 50 | 17 |
| lib/features/promotions/promotion_page.dart | 30 | 47 | 17 |
| lib/features/auth/google_registration_form.dart | 34 | 49 | 15 |
| lib/features/profile/account_status_page.dart | 35 | 50 | 15 |
| lib/features/profile/personal_section.dart | 28 | 43 | 15 |
| lib/features/auth/login_page.dart | 38 | 52 | 14 |
| lib/features/checkout/purchase_quote.dart | 36 | 50 | 14 |
| lib/features/checkout/voucher_picker.dart | 57 | 71 | 14 |
| lib/features/auth/email_verification_link_page.dart | 36 | 49 | 13 |
| lib/features/engagement/engagement_repository.dart | 35 | 48 | 13 |
| lib/features/profile/addresses_section.dart | 87 | 100 | 13 |
| lib/core/catalogue_cache.dart | 59 | 71 | 12 |
| lib/features/auth/native_google_identity.dart | 4 | 16 | 12 |
| lib/features/checkout/commerce_details.dart | 30 | 41 | 11 |
| lib/features/home/campaigns.dart | 16 | 27 | 11 |
| lib/features/profile/order_journey.dart | 33 | 44 | 11 |
| lib/features/auth/recovery_page.dart | 33 | 43 | 10 |
| lib/features/products/product_widgets.dart | 86 | 96 | 10 |
| lib/features/profile/inbox_page.dart | 45 | 55 | 10 |
| lib/features/profile/wallet_section.dart | 43 | 53 | 10 |
| lib/features/home/home_controller.dart | 49 | 58 | 9 |
| lib/features/profile/return_codes.dart | 10 | 19 | 9 |
| lib/features/tracking/tracking_controller.dart | 19 | 28 | 9 |
| lib/features/tracking/tracking_repository.dart | 27 | 36 | 9 |
| lib/features/auth/google_auth_page.dart | 37 | 45 | 8 |
| lib/features/checkout/bag_controller.dart | 85 | 93 | 8 |
| lib/features/checkout/location_picker.dart | 39 | 47 | 8 |
| lib/features/home/search_filters.dart | 20 | 28 | 8 |
| lib/features/home/about_page.dart | 7 | 14 | 7 |
| lib/features/home/search_controller.dart | 59 | 66 | 7 |
| lib/features/profile/vouchers_section.dart | 12 | 19 | 7 |
| lib/core/device_actions.dart | 2 | 8 | 6 |
| lib/features/auth/google_auth_repository.dart | 26 | 32 | 6 |
| lib/features/auth/policy_page.dart | 16 | 22 | 6 |
| lib/features/home/product_card.dart | 14 | 20 | 6 |
| lib/features/auth/google_auth_controller.dart | 59 | 64 | 5 |
| lib/features/profile/profile_repository.dart | 7 | 12 | 5 |
| lib/features/auth/verification_page.dart | 33 | 37 | 4 |
| lib/core/buyer_actions.dart | 8 | 11 | 3 |
| lib/core/foreground_refresh.dart | 30 | 33 | 3 |
| lib/core/native_session_vault.dart | 1 | 4 | 3 |
| lib/core/pagination_metadata.dart | 10 | 13 | 3 |
| lib/core/uploads.dart | 11 | 14 | 3 |
| lib/core/viewport_visibility.dart | 22 | 25 | 3 |
| lib/features/auth/registration_policy_contract.dart | 7 | 10 | 3 |
| lib/features/tracking/parcel_tracking_page.dart | 48 | 51 | 3 |
| lib/core/catalogue_pages.dart | 8 | 10 | 2 |
| lib/core/file_selection.dart | 26 | 28 | 2 |
| lib/core/form_metadata.dart | 8 | 10 | 2 |
| lib/features/home/advertisement_exposure.dart | 18 | 20 | 2 |
| lib/features/home/browse_controls.dart | 8 | 10 | 2 |
| lib/features/products/chat_history.dart | 15 | 17 | 2 |
| lib/features/products/sale_clock.dart | 19 | 21 | 2 |
| lib/app/theme.dart | 12 | 13 | 1 |
| lib/core/application_text_validation.dart | 24 | 25 | 1 |
| lib/core/retry_cooldown.dart | 14 | 15 | 1 |
| lib/core/strict_datetime.dart | 9 | 10 | 1 |
| lib/core/verification_prompt.dart | 3 | 4 | 1 |
| lib/features/auth/auth_shell.dart | 9 | 10 | 1 |
| lib/features/auth/google_auth_contract.dart | 8 | 9 | 1 |
| lib/features/auth/google_identity.dart | 5 | 6 | 1 |
| lib/features/engagement/buyer_link.dart | 9 | 10 | 1 |
| lib/core/auth_validation.dart | 13 | 13 | 0 |
| lib/core/buyer_account_scope.dart | 8 | 8 | 0 |
| lib/core/buyer_capabilities.dart | 7 | 7 | 0 |
| lib/core/cached_catalogue_notice.dart | 4 | 4 | 0 |
| lib/core/contact_input.dart | 7 | 7 | 0 |
| lib/core/count_metadata.dart | 1 | 1 | 0 |
| lib/core/numeric_input.dart | 6 | 6 | 0 |
| lib/core/request_id.dart | 3 | 3 | 0 |
| lib/core/resource_ids.dart | 9 | 9 | 0 |
| lib/core/verification_cooldown.dart | 5 | 5 | 0 |
| lib/core/widgets.dart | 22 | 22 | 0 |
| lib/features/checkout/checkout_widgets.dart | 2 | 2 | 0 |
| lib/features/checkout/voucher_selection.dart | 20 | 20 | 0 |
| lib/features/collections/collection_pagination.dart | 7 | 7 | 0 |
| lib/features/home/catalogue_loading.dart | 7 | 7 | 0 |
| lib/features/support/support_repository.dart | 14 | 14 | 0 |

## Unmeasured sources and platform work

- Default Flutter package coverage omits `tool/`, including build configuration already exercised by tests. Tooling needs a collector that retains file-URI libraries.
- `SessionVault` is an abstract interface without executable methods; classify declarations explicitly instead of adding artificial runtime code.
- The new native browser fixture lives in `e2e/` and needs journey coverage collection from its actual native VM.
- Native host code in Android, iOS, and Linux is not measured by Dart LCOV. Physical/provider acceptance and iOS/Xcode requirements remain separate evidence gaps.
- Database transaction, authorization, persistence and rollback behavior belongs to the read-only backend. Synthetic loopback replies cannot close that acceptance requirement.

## Commands

```sh
flutter test --no-pub --branch-coverage --coverage-path=coverage/lcov.info --concurrency=1
dart run tool/testing/coverage_report.dart coverage/lcov.info
dart run tool/testing/coverage_report.dart coverage/lcov.info --require-complete
```

The strict gate remains failing until the declared Dart inventory is complete. Passing test counts or improved emitted-counter percentages do not mark the workspace sweep complete.
