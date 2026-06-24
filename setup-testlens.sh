#! /usr/bin/env bash
# Add Gradle init script
# Detect Gradle build based on env var, or presence the of settings script
if [[ -n "$GRADLE_USER_HOME" ]] || [[ -f settings.gradle ]] || [[ -f settings.gradle.kts ]]; then

  # set Gradle home to the default location if it was not set before, e.g. we detected the build
  # because of a settings script
  if [[ -z "$GRADLE_USER_HOME" ]]; then
    GRADLE_USER_HOME="$HOME/.gradle"
  fi

  # normalize file paths on windows
  if [[ "$RUNNER_OS" == "Windows" ]]; then
    # shellcheck disable=SC2001
    # SC2001: sed is intentionally used here over bash parameter expansion for readability,
    # as the bash equivalent `${VAR//\\//}` is visually ambiguous for backslash-to-slash substitution.
    WORKSPACE_PATH=$(echo "$WORKSPACE_PATH" | sed 's|\\|/|g')
    # shellcheck disable=SC2001
    GRADLE_USER_HOME=$(echo "$GRADLE_USER_HOME" | sed 's|\\|/|g')
  fi

  # write files required by TestLens
  echo -n "$TESTLENS_GITHUB_TOKEN" > "$GRADLE_USER_HOME"/init.d/TESTLENS_GITHUB_TOKEN
  echo -n "$JOB_CHECK_RUN_ID" > "$GRADLE_USER_HOME"/init.d/JOB_CHECK_RUN_ID
  cat << EOF > "$GRADLE_USER_HOME"/init.d/testlens-init.gradle
import org.gradle.api.provider.*;
gradle.beforeProject { project ->
  String relativeBuildPath = new File('$WORKSPACE_PATH').relativePath(project.rootDir)
  if (!relativeBuildPath.startsWith('..') && !new File(relativeBuildPath).isAbsolute()) {
    TestLensSetup.configure(project, relativeBuildPath)
  }
}
abstract class TestLensGitHubTokenValueSource implements ValueSource<String, ValueSourceParameters.None> {
  String obtain() { new File('$GRADLE_USER_HOME/init.d/TESTLENS_GITHUB_TOKEN').text }
}
abstract class TestLensJobCheckRunIdValueSource implements ValueSource<String, ValueSourceParameters.None> {
  String obtain() { new File('$GRADLE_USER_HOME/init.d/JOB_CHECK_RUN_ID').text }
}
final class TestLensSetup {
  static def configure(Project project, String relativeBuildPath) {
    project.plugins.withId('java') {
      project.testing.suites.configureEach {
        dependencies { runtimeOnly('app.testlens:junit-platform-instrumentation:$INSTRUMENTATION_VERSION') }
      }
    }
    def providers = project.providers
    project.tasks.withType(Test).configureEach { task ->
      def muteMarker = new File(task.temporaryDir, 'testlens-mute.marker')
      def logsDir = new File(task.temporaryDir, 'testlens-logs')
      def workUnitPath = task.path + (relativeBuildPath.isEmpty() ? '' : ' [' + relativeBuildPath + ']')
      task.environment('TESTLENS_PROJECT_ID', '$TESTLENS_PROJECT_ID')
      task.environment('TESTLENS_WORK_UNIT_PATH', workUnitPath)
      task.environment('TESTLENS_MUTE_MARKER_FILE', muteMarker.absolutePath)
      task.environment('TESTLENS_GITHUB_TOKEN', providers.of(TestLensGitHubTokenValueSource){}.get())
      task.environment('JOB_CHECK_RUN_ID', providers.of(TestLensJobCheckRunIdValueSource){}.get())
      if ('true'.equalsIgnoreCase('$WRITE_LOG_FILES')) {
        task.environment('TESTLENS_LOGS_DIR', logsDir.absolutePath)
      }
      if (!'$SESSION_TIMEOUT_SECONDS'.empty) {
        task.environment('TESTLENS_SESSION_TIMEOUT_SECONDS', '$SESSION_TIMEOUT_SECONDS')
      }
      task.filter.failOnNoMatchingTests = false
      if (task.hasProperty('failOnNoDiscoveredTests')) task.failOnNoDiscoveredTests = false
      task.addTestListener(new TestListener() {
        void beforeTest(TestDescriptor __) {}
        void afterTest(TestDescriptor __, TestResult ___) {}
        void beforeSuite(TestDescriptor __) {}
        void afterSuite(TestDescriptor __, TestResult ___) {
          if (muteMarker.isFile()) {
            task.outputs.doNotStoreInCache()
            muteMarker.delete()
          }
        }
      })
    }
  }
}
EOF
fi

# Patch Maven Parent POM
if [[ -f "pom.xml" ]]; then
  POM_FILE="pom.xml"
  # shellcheck disable=SC2016
  # SC2016: Single-quoted `${project.build.directory}` is a Maven expression, not a shell variable - it must not be expanded.
  PROFILE_CONTENT="    <profile>
      <id>testlens</id>
      <activation>
        <property>
          <name>env.CI</name>
        </property>
      </activation>
      <dependencies>
        <dependency>
          <groupId>app.testlens</groupId>
          <artifactId>junit-platform-instrumentation</artifactId>
          <version>$INSTRUMENTATION_VERSION</version>
          <scope>test</scope>
        </dependency>
      </dependencies>
      <build>
        <plugins>
          <plugin>
            <artifactId>maven-surefire-plugin</artifactId>
            <configuration>
              <environmentVariables>
                <TESTLENS_PROJECT_ID>$TESTLENS_PROJECT_ID</TESTLENS_PROJECT_ID>
                <TESTLENS_GITHUB_TOKEN>$TESTLENS_GITHUB_TOKEN</TESTLENS_GITHUB_TOKEN>
                <TESTLENS_WORK_UNIT_PATH>\${project.name}</TESTLENS_WORK_UNIT_PATH>
                <JOB_CHECK_RUN_ID>$JOB_CHECK_RUN_ID</JOB_CHECK_RUN_ID>
                <TESTLENS_LOGS_DIR>$(if [[ $WRITE_LOG_FILES = "true" ]]; then echo '${project.build.directory}/testlens-logs'; fi)</TESTLENS_LOGS_DIR>
                $(if [[ -n "$SESSION_TIMEOUT_SECONDS" ]]; then echo "<TESTLENS_SESSION_TIMEOUT_SECONDS>$SESSION_TIMEOUT_SECONDS</TESTLENS_SESSION_TIMEOUT_SECONDS>"; fi)
              </environmentVariables>
            </configuration>
          </plugin>
          <plugin>
            <artifactId>maven-failsafe-plugin</artifactId>
            <configuration>
              <environmentVariables>
                <TESTLENS_PROJECT_ID>$TESTLENS_PROJECT_ID</TESTLENS_PROJECT_ID>
                <TESTLENS_GITHUB_TOKEN>$TESTLENS_GITHUB_TOKEN</TESTLENS_GITHUB_TOKEN>
                <TESTLENS_WORK_UNIT_PATH>\${project.name}</TESTLENS_WORK_UNIT_PATH>
                <JOB_CHECK_RUN_ID>$JOB_CHECK_RUN_ID</JOB_CHECK_RUN_ID>
                <TESTLENS_LOGS_DIR>$(if [[ $WRITE_LOG_FILES = "true" ]]; then echo '${project.build.directory}/testlens-logs'; fi)</TESTLENS_LOGS_DIR>
                $(if [[ -n "$SESSION_TIMEOUT_SECONDS" ]]; then echo "<TESTLENS_SESSION_TIMEOUT_SECONDS>$SESSION_TIMEOUT_SECONDS</TESTLENS_SESSION_TIMEOUT_SECONDS>"; fi)
              </environmentVariables>
            </configuration>
          </plugin>
        </plugins>
      </build>
    </profile>"
  CLOSING_PROFILES_TAG_LINE=$({ grep -n "</profiles>" "$POM_FILE" || true; } | tail -1 | cut -d: -f1)
  CLOSING_PROJECT_TAG_LINE=$({ grep -n "</project>" "$POM_FILE" || true; } | tail -1 | cut -d: -f1)
  if [ -n "$CLOSING_PROFILES_TAG_LINE" ]; then
    {
      head -n $((CLOSING_PROFILES_TAG_LINE - 1)) "$POM_FILE"
      echo "$PROFILE_CONTENT"
      tail -n +"$CLOSING_PROFILES_TAG_LINE" "$POM_FILE"
    } > "${POM_FILE}.tmp"
    mv "${POM_FILE}.tmp" "$POM_FILE"
  elif [ -n "$CLOSING_PROJECT_TAG_LINE" ]; then
    {
      head -n $((CLOSING_PROJECT_TAG_LINE - 1)) "$POM_FILE"
      echo ""
      echo "  <profiles>"
      echo "$PROFILE_CONTENT"
      echo "  </profiles>"
      tail -n +"$CLOSING_PROJECT_TAG_LINE" "$POM_FILE"
    } > "${POM_FILE}.tmp"
    mv "${POM_FILE}.tmp" "$POM_FILE"
  fi
fi
