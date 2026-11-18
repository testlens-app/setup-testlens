#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
}

@test "profile is inserted into an existing <profiles> block" {
  copy_fixture maven-with-profiles
  run "$SCRIPT"
  assert_success
  assert_output --partial "Detected Maven build"
  assert_contains pom.xml "<id>testlens</id>"
  assert_contains pom.xml "<id>existing</id>"
  assert_equal "$(grep -c "<profiles>" pom.xml)" 1
}

@test "a <profiles> wrapper is created when the POM has none" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_success
  assert_contains pom.xml "<profiles>"
  assert_contains pom.xml "<id>testlens</id>"
}

@test "patched POM is well-formed XML" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_success
  run env NODE_PATH="$BATS_TEST_DIRNAME/node_modules" node -e '
    const { XMLValidator } = require("fast-xml-parser");
    const r = XMLValidator.validate(require("fs").readFileSync("pom.xml", "utf8"));
    if (r !== true) { console.error(r.err.msg); process.exit(1); }'
  assert_success
}

@test "both surefire and failsafe plugins are configured" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_contains pom.xml "maven-surefire-plugin"
  assert_contains pom.xml "maven-failsafe-plugin"
}

@test "surefire/failsafe pass the project id" {
  copy_fixture maven-single
  export TESTLENS_PROJECT_ID="octo/demo-repo"
  run "$SCRIPT"
  assert_contains pom.xml "<TESTLENS_PROJECT_ID>octo/demo-repo</TESTLENS_PROJECT_ID>"
}

@test "surefire/failsafe report the build tool and its version" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_contains pom.xml "<app.testlens.build-tool.type>maven</app.testlens.build-tool.type>"
  assert_contains pom.xml "<app.testlens.build-tool.version>\${maven.version}</app.testlens.build-tool.version>"
  local count
  count=$(grep -c "app.testlens.build-tool.type" pom.xml)
  assert_equal "$count" 2
}

@test "instrumentation dependency uses the requested version and test scope" {
  copy_fixture maven-single
  export INSTRUMENTATION_VERSION="9.9.9"
  run "$SCRIPT"
  assert_contains pom.xml "<artifactId>junit-platform-instrumentation</artifactId>"
  assert_contains pom.xml "<version>9.9.9</version>"
  assert_contains pom.xml "<scope>test</scope>"
}

@test "logs dir is empty by default" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_contains pom.xml "<TESTLENS_LOGS_DIR></TESTLENS_LOGS_DIR>"
}

@test "logs dir is populated when logging is on" {
  copy_fixture maven-single
  export WRITE_LOG_FILES="true"
  run "$SCRIPT"
  assert_contains pom.xml "testlens-logs</TESTLENS_LOGS_DIR>"
}

@test "session timeout tag is omitted when unset and present when set" {
  copy_fixture maven-single
  run "$SCRIPT"
  assert_not_contains pom.xml "TESTLENS_SESSION_TIMEOUT_SECONDS"

  copy_fixture maven-single
  export SESSION_TIMEOUT_SECONDS="45"
  run "$SCRIPT"
  assert_contains pom.xml "<TESTLENS_SESSION_TIMEOUT_SECONDS>45</TESTLENS_SESSION_TIMEOUT_SECONDS>"
}
