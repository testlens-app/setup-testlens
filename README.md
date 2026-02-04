# GitHub Action for TestLens

The `setup-testlens` action connects a Maven or Gradle build to [TestLens](https://testlens.app).

## Prerequisites

The [TestLens GitHub App](https://github.com/apps/testlens-app) needs to be installed on the repository.

> [!IMPORTANT]
> **TestLens is currently in private beta.**
> Therefore, an extra step is required to onboard a new GitHub organization.
> If you’re interested in trying out TestLens, please [contact us via the website](https://testlens.app/contact/).

## Setup for Gradle

For Gradle, the action should be added right after the `setup-gradle` action in all workflow files that should be instrumented:

```yml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: 8 # or later
      - uses: gradle/actions/setup-gradle@v5
      - uses: testlens-app/setup-testlens@v5
      - run: ./gradlew build
```

The action writes a Gradle init script that instruments all `Test` tasks.

## Setup for Maven

For Maven, the action needs to be added before the first call to `mvn` that should be instrumented.
We recommend adding it right after `actions/setup-java` or a similar action that ensures the required version of Java is available.

```yml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: 8 # or later
      - uses: testlens-app/setup-testlens@v5
      - run: mvn verify
```

The action expects the root parent POM to be present in the root directory of the repository.
It alters the POM by adding a profile that instruments all executions of the `maven-surefire-plugin`.
