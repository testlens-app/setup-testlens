#!/usr/bin/env bash

SCRIPT="${TESTLENS_SCRIPT:-$BATS_TEST_DIRNAME/../setup-testlens.sh}"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

_common_setup() {
  # avoid leaking env vars into tests
  unset GRADLE_USER_HOME SESSION_TIMEOUT_SECONDS INSTRUMENTATION_VERSION JOB_CHECK_RUN_ID \
    TESTLENS_GITHUB_TOKEN TESTLENS_PROJECT_ID WRITE_LOG_FILES USE_OIDC TOKEN_EXCHANGE_URL \
    PULL_REQUEST_HEAD_REPO ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN

  TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/setup-testlens-test-XXXXXX")"
  WORKDIR="$TEST_TMP/workspace"
  mkdir -p "$WORKDIR"

  # For `GRADLE_USER_HOME`
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"

  export RUNNER_OS="Linux"

  cd "$WORKDIR"
}

teardown() {
  cd /
  rm -rf "$TEST_TMP"
}

copy_fixture() {
  cp -R "$FIXTURES/$1/." "$WORKDIR/"
}

assert_file() {
  [ -f "$1" ] || { echo "expected file to exist: $1"; return 1; }
}

assert_no_file() {
  [ ! -e "$1" ] || { echo "expected path NOT to exist: $1"; return 1; }
}

# assert_contains <file> <substring>
assert_contains() {
  grep -qF -- "$2" "$1" || {
    echo "expected file '$1' to contain: $2"
    echo "--- actual content ---"
    cat "$1"
    return 1
  }
}

# assert_not_contains <file> <substring>
assert_not_contains() {
  ! grep -qF -- "$2" "$1" || {
    echo "expected file '$1' NOT to contain: $2"
    echo "--- actual content ---"
    cat "$1"
    return 1
  }
}
