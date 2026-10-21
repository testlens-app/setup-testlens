#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
  unset "${!GITHUB_@}"
  export GITHUB_REPOSITORY="octo/demo"
  GRADLE_ENV_PROPS="$WORKDIR/.gradle/testlens-env.properties"
  echo "rootProject.name = 'demo'" > settings.gradle

  export TESTLENS_PROJECT_ID="octo/demo"
  export TESTLENS_GITHUB_TOKEN="ghs_secret"
  export JOB_CHECK_RUN_ID="12345"
  export TOKEN_EXCHANGE_URL="https://testlens.example/oauth/token"
  export USE_OIDC="true"
  export EXCHANGE_RESPONSE='{"access_token":"testlens_abc","token_type":"Bearer"}'

  # stub curl: records its arguments and answers ID token and token exchange requests
  export CURL_LOG="$TEST_TMP/curl.log"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/curl" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CURL_LOG"
printf 'stdin: %s\n' "$(cat)" >> "$CURL_LOG"
if [[ "$*" == *id-token-request* ]]; then
  echo '{"value":"the-id-token"}'
else
  echo "$EXCHANGE_RESPONSE"
  exit "${EXCHANGE_EXIT:-0}"
fi
EOF
  chmod +x "$TEST_TMP/bin/curl"
  export PATH="$TEST_TMP/bin:$PATH"
}

with_id_token() {
  export ACTIONS_ID_TOKEN_REQUEST_URL="https://github.example/id-token-request?x=1"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="request-token"
}

@test "exchanges ID token for TestLens token and does not pass GitHub token" {
  with_id_token
  run "$SCRIPT"
  assert_success
  assert_output --partial "::add-mask::testlens_abc"
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_TOKEN=testlens_abc"
  assert_not_contains "$GRADLE_ENV_PROPS" "ghs_secret"
  assert_contains "$CURL_LOG" "audience=https://api.testlens.app"
  assert_contains "$CURL_LOG" "stdin: Authorization: Bearer request-token"
  assert_contains "$CURL_LOG" "subject_token@-"
  assert_contains "$CURL_LOG" "stdin: the-id-token"
  assert_contains "$CURL_LOG" "job_id=12345"
  assert_contains "$CURL_LOG" "$TOKEN_EXCHANGE_URL"
}

@test "fails with server error when token exchange fails" {
  with_id_token
  export EXCHANGE_RESPONSE='{"error":"invalid_grant","error_description":"job not running"}'
  export EXCHANGE_EXIT=22
  run "$SCRIPT"
  assert_failure
  assert_output --partial "job not running"
  assert_no_file "$GRADLE_ENV_PROPS"
}

@test "falls back to GitHub token with warning when no ID token is available" {
  run "$SCRIPT"
  assert_success
  assert_output --partial "::warning::No OIDC token available"
  assert_output --partial "id-token: write"
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_GITHUB_TOKEN=ghs_secret"
  assert_not_contains "$GRADLE_ENV_PROPS" "TESTLENS_TOKEN="
  assert_no_file "$CURL_LOG"
}

@test "falls back to GitHub token with warning for same-repository pull requests" {
  export GITHUB_EVENT_NAME="pull_request"
  export PULL_REQUEST_HEAD_REPO="octo/demo"
  export TESTLENS_PROJECT_ID="unrelated-project-id"
  run "$SCRIPT"
  assert_success
  assert_output --partial "::warning::No OIDC token available"
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_GITHUB_TOKEN=ghs_secret"
}

@test "falls back to GitHub token without warning for fork pull requests" {
  export GITHUB_EVENT_NAME="pull_request"
  export PULL_REQUEST_HEAD_REPO="fork/demo"
  run "$SCRIPT"
  assert_success
  refute_output --partial "::warning::"
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_GITHUB_TOKEN=ghs_secret"
  assert_not_contains "$GRADLE_ENV_PROPS" "TESTLENS_TOKEN="
  assert_no_file "$CURL_LOG"
}

@test "warns for fork pull requests when fallback is disabled" {
  export GITHUB_EVENT_NAME="pull_request"
  export PULL_REQUEST_HEAD_REPO="fork/demo"
  export TESTLENS_GITHUB_TOKEN=""
  run "$SCRIPT"
  assert_success
  assert_output --partial "::warning::"
}

@test "ignores available ID token when use-oidc is not set" {
  with_id_token
  unset USE_OIDC
  run "$SCRIPT"
  assert_success
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_GITHUB_TOKEN=ghs_secret"
  assert_not_contains "$GRADLE_ENV_PROPS" "TESTLENS_TOKEN="
  assert_no_file "$CURL_LOG"
  refute_output --partial "::warning::"
}

@test "fails when token exchange response lacks access token" {
  with_id_token
  export EXCHANGE_RESPONSE='{"token_type":"Bearer"}'
  run "$SCRIPT"
  assert_failure
  assert_output --partial "::error::Unexpected response from TestLens token exchange"
  assert_no_file "$GRADLE_ENV_PROPS"
}

@test "fails with error naming jq when it isn't installed" {
  with_id_token
  PATH="$TEST_TMP/bin" run "$BASH" "$SCRIPT"
  assert_failure
  assert_output --partial "::error::'use-oidc: true' requires 'jq'"
  assert_no_file "$CURL_LOG"
}
