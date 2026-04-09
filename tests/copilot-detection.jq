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
# Sync requirement: the inline `jq -e` expressions in commands/ship.md step 13 must
# stay equivalent to this filter. When you change one, change the other in the same
# commit. (CI does not currently diff them — that's a follow-up.)

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
