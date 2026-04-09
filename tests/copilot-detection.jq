# tests/copilot-detection.jq
#
# Canonical detection logic for "is Copilot review actually queued on this PR?"
# Used by tests/copilot-detection.sh against fixtures in tests/fixtures/copilot-detection/.
#
# Input shape (subset of `gh pr view --json reviewRequests,latestReviews` output):
#
#   {
#     "reviewRequests": [
#       { "login": "...", "name": "..." }
#     ],
#     "latestReviews": [
#       { "author": { "login": "..." }, "state": "COMMENTED|APPROVED|CHANGES_REQUESTED" }
#     ]
#   }
#
# Output shape:
#
#   { "queued": true|false, "detection_method": "requested_reviewers"|"latest_reviews"|"neither" }
#
# Sync requirement: the unified `jq -r` expression in commands/ship.md step 13
# (between `# JQ_DETECT_FILTER_BEGIN` and `# JQ_DETECT_FILTER_END` sentinels) must
# stay semantically equivalent to this `detect` function — both must produce identical
# output across every fixture in tests/fixtures/copilot-detection/. They are NOT
# source-identical: the inline form uses `any(test(...))` while this canonical form
# uses `map(test(...)) | any`. These are equivalent in jq but not byte-identical.
#
# CI enforces semantic equivalence: tests/jq-sync-check.sh extracts the inline
# filter via the sentinels, runs both filters against every fixture, and asserts
# identical output strings. When you change one, change the other in the same
# commit — CI will fail loud otherwise.

def detect:
  . as $pr
  | (
      ($pr.reviewRequests // [])
      | map(.login // .name // "")
      | map(test("[Cc]opilot"))
      | any
    ) as $req
  | (
      ($pr.latestReviews // [])
      | map(.author.login // "")
      | map(test("[Cc]opilot"))
      | any
    ) as $rev
  | if $req then
      { queued: true, detection_method: "requested_reviewers" }
    elif $rev then
      { queued: true, detection_method: "latest_reviews" }
    else
      { queued: false, detection_method: "neither" }
    end;

detect
