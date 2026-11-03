# PR title

Harden buyer presentation flows against malformed input and responses

# PR description

Home now handles malformed application and shipment metadata without crashing or showing invalid delivery links. Recovery and verification links reject ambiguous repeated parameters, incoming search links enforce query limits and normalize price whitespace, and multipart upload headers replace ASCII control characters.

Regression cases cover malformed Home responses, search and product interactions, Unicode and numeric boundaries, recovery links, contact input, and multipart headers. The branch also includes a signed-in Home-to-checkout journey test and avoids replacing unchanged chat messages during polling.

Chat still retrieves the full conversation; server pagination requires the separately documented backend contract. Device and live provider acceptance are outside this isolated test review.

Validation: `flutter test --concurrency=1 --reporter=compact` passed all 1,515 tests in 8 minutes 57 seconds. Full `flutter analyze`, formatting of the changed Dart files, and the branch diff check pass. The Unicode input fixtures use escaped code points to follow repository source conventions; their focused link and search tests were rerun after that equivalent representation change. This is a local PR draft, not a GitHub PR.
