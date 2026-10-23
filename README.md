# iDempiere Plugin CI

`idempiere-plugin-ci` provides a versioned command-line interface for validating, compiling, testing, and packaging Maven/Tycho iDempiere plugins. The same commands are intended for developer workstations and Jenkins pipelines.

The tool extracts shared CI behavior from individual plugin repositories without hiding the selected Java version, builder image, target platform, iDempiere version, or database runtime.

## What It Covers

| Stage | Command | Purpose |
| --- | --- | --- |
| Branch policy | `validate-branch` | Checks feature, `master`, pull-request, and version-branch compatibility. |
| Static validation | `validate` | Checks Java/Maven versions, bundle POMs, OSGi metadata, build properties, incremental 2Packs, and repository hygiene. |
| Compilation and tests | `compile` | Calls the approved target platform's `plugin-builder` for the production bundle and test fragment. |
| Artifact validation | `validate-artifacts` | Verifies bundle identities, versions, content, and build qualifier. |
| Immutable packaging | `package-artifacts` | Produces release archives, checksums, and build metadata. |
| Database-backed 2Pack validation | `validate-2pack-db` | Uses iDempiere's official PackIn application to test clean installation, incremental upgrade, assertions, and reinstall behavior. |

Deployment is deliberately excluded. A successful pipeline produces evidence and immutable artifacts; it does not authorize a QA or production deployment.

## Architecture

```text
Plugin repository
├── Jenkinsfile
├── plugin-ci.properties
├── production bundle
├── test fragment
└── ci/sql/                    plugin-specific database assertions
            │
            ▼
idempiere-plugin-ci            shared, versioned commands and validators
            │
            ├── Java + Maven/Tycho builder image
            ├── versioned iDempiere target platform
            └── clean configured iDempiere runtime + disposable PostgreSQL seed
```

The plugin owns its identity and assertions. This repository owns repeatable CI behavior. Jenkins owns credentials and infrastructure lifecycle.

## Requirements

- POSIX-compatible shell.
- Git.
- Java version declared by the plugin, currently Java 17 for the pilot.
- Maven at or above the plugin's declared minimum.
- The versioned target-platform repository for compilation.
- PostgreSQL client tools for database-backed validation.
- A clean, configured iDempiere runtime matching the supported version when running PackIn validation.
- Docker on workstations that reproduce the Jenkins builder environment.

The Recurrent pilot currently uses these explicit dependencies:

| Dependency | Version or reference |
| --- | --- |
| Builder image | `carl0jgr/idempiere-source-builder:12` |
| Target platform | `idempiere-target-platform-plugin`, branch `12.0` |
| iDempiere compatibility | `12.0.0` |
| Java | 17 |

## Installation

Clone this repository beside or independently from a plugin repository. Do not copy `libexec` files into each plugin.

```bash
git clone --branch v0.1.0 https://github.com/alaracds/idempiere-plugin-ci.git
export IDEMPIERE_PLUGIN_CI="$PWD/idempiere-plugin-ci"
```

Pin a tag or immutable commit in normal use; do not make builds depend implicitly on the latest `main`.

Verify the CLI:

```bash
"$IDEMPIERE_PLUGIN_CI/bin/idempiere-plugin-ci" --help
```

## Plugin Configuration

Each plugin repository provides `plugin-ci.properties`. Start from [plugin-ci.properties.example](plugin-ci.properties.example).

The file contains no secrets. It declares:

- production and test bundle IDs;
- iDempiere, Java, and Maven compatibility;
- model-generation metadata;
- visible builder image and target-platform references;
- PackIn client and incremental package versions;
- paths to plugin-specific SQL assertions.

Database assertions remain in the plugin because they describe its own Application Dictionary contract. See [the Recurrent example](examples/recurrent/plugin-ci.properties).

## Local Usage

Set the plugin path once:

```bash
PLUGIN_DIR=/path/to/plugin-repository
CI="$IDEMPIERE_PLUGIN_CI/bin/idempiere-plugin-ci"
```

Run static validation:

```bash
"$CI" --project-dir "$PLUGIN_DIR" validate
```

Validate a branch or pull-request context:

```bash
"$CI" --project-dir "$PLUGIN_DIR" \
  validate-branch feature/example '' master
```

Clone the configured target platform and compile:

```bash
export IDEMPIERE_REPOSITORY=/path/to/idempiere-source

git clone --branch 12.0 \
  https://github.com/ingeint/idempiere-target-platform-plugin.git \
  /tmp/idempiere-target-platform-12

"$CI" --project-dir "$PLUGIN_DIR" \
  compile /tmp/idempiere-target-platform-12
```

Local compilation uses build qualifier `0` unless `BUILD_NUMBER` is set. Jenkins supplies its normal build number automatically.
The target-platform builder also requires `IDEMPIERE_REPOSITORY`; the Jenkins builder image normally supplies it, while a workstation must point it to the compatible iDempiere source checkout.

Then validate and package the output:

```bash
"$CI" --project-dir "$PLUGIN_DIR" \
  validate-artifacts /tmp/idempiere-target-platform-12/target 0

"$CI" --project-dir "$PLUGIN_DIR" \
  package-artifacts \
  /tmp/idempiere-target-platform-12/target \
  /tmp/idempiere-target-platform-12/release \
  feature/example 0
```

To reproduce Jenkins precisely, run these commands inside the builder image declared in `plugin-ci.properties`, mounting a Maven cache in the same way as Jenkins. The repository intentionally keeps that image visible instead of selecting it silently.

## Database-Backed 2Pack Validation

The database command performs real writes and DDL through iDempiere PackIn. It refuses to run unless all of the following are true:

- `IDEMPIERE_DB_VALIDATION=1` explicitly confirms a disposable target;
- `IDEMPIERE_HOME` points to a configured iDempiere installation;
- `EXPECTED_DATABASE` matches `ADEMPIERE_DB_NAME` in that installation;
- the live PostgreSQL connection resolves to the same database;
- the plugin-specific clean-baseline assertion passes.

Example:

```bash
export IDEMPIERE_HOME=/srv/idempiere-ci-12
export EXPECTED_DATABASE=idempiere_plugin_ci
export IDEMPIERE_DB_VALIDATION=1
export PGHOST=127.0.0.1
export PGPORT=5432
export PGDATABASE="$EXPECTED_DATABASE"
export PGUSER=adempiere

"$CI" --project-dir "$PLUGIN_DIR" validate-2pack-db
```

Use the normal iDempiere secret mechanism for PackIn and libpq authentication, such as a restricted `.pgpass`, for SQL assertions. Never store a password in `plugin-ci.properties`, the Jenkinsfile, the repository, or command arguments.

The runtime must come from a clean iDempiere distribution. Do not clone a working server containing unrelated custom bundles: their activators can install unrelated 2Packs during the validation startup.

Database provisioning and disposal belong to CI infrastructure, not to an individual plugin or this validator. The infrastructure must restore a supported seed, configure a clean iDempiere runtime, run this command, retain diagnostic evidence on failure according to policy, and discard the environment.

## Jenkins Integration

The existing declarative pipeline does not need to be replaced. Checkout this repository at a pinned version and call individual commands from the corresponding existing stages.

```groovy
dir('.ci-tool') {
    git branch: 'v0.1.0', url: 'https://github.com/alaracds/idempiere-plugin-ci.git'
}

sh '.ci-tool/bin/idempiere-plugin-ci --project-dir "$WORKSPACE" validate'
```

The complete [Jenkinsfile example](examples/Jenkinsfile) preserves visible stages, the builder image, target-platform repository, test report publication, artifact archiving, and cleanup. Replace example repository URLs and credential IDs before use.

The database stage should run on a dedicated label whose node provides:

- a clean iDempiere runtime through `IDEMPIERE_HOME`;
- a disposable database through `EXPECTED_DATABASE` and standard PostgreSQL variables;
- `IDEMPIERE_DB_VALIDATION=1`;
- credentials injected from Jenkins Credentials;
- an infrastructure cleanup action that runs even after failure.

Keep the database stage optional during the pilot. Make it required only after provisioning and cleanup are reproducible on Jenkins.

## Repository Layout

```text
idempiere-plugin-ci/
├── bin/
│   └── idempiere-plugin-ci
├── libexec/
│   ├── compile.sh
│   ├── validate-plugin.sh
│   ├── validate-2pack.sh
│   ├── validate-2pack-db.sh
│   ├── validate-branch.sh
│   ├── validate-artifacts.sh
│   ├── package-artifacts.sh
│   └── Java source validators
├── examples/
│   ├── Jenkinsfile
│   └── recurrent/
├── docs/
├── tests/
│   └── smoke.sh
└── plugin-ci.properties.example
```

Run the toolkit's self-check before publishing a version:

```bash
./tests/smoke.sh
```

## Versioning and Adoption

Use semantic tags for this tool. Plugin pipelines must pin a tag or commit. A breaking configuration or command change requires a new major version.

Adopt changes in this order:

1. Validate this repository against Recurrent locally.
2. Use a pinned version from the Recurrent Jenkinsfile.
3. Confirm feature, `master`, and active release branch builds.
4. Stabilize clean database provisioning.
5. Roll out to another plugin without copying shared scripts.

Do not remove the plugin's existing scripts until the external commands have produced equivalent local and Jenkins results.

## Troubleshooting

| Failure | Check |
| --- | --- |
| Wrong Java version | Run with the JDK declared in `plugin-ci.properties`. |
| Missing `xmllint` | The current static validator no longer requires it; confirm the pinned tool version. |
| Target platform builder unavailable | Verify the checkout path and executable `plugin-builder`. |
| `IDEMPIERE_REPOSITORY` missing | Point it to the source checkout matching the configured iDempiere version. |
| Artifact qualifier mismatch | Use the same Jenkins build number for compilation and artifact validation. |
| Database guard failure | Compare `EXPECTED_DATABASE`, iDempiere configuration, and libpq variables. |
| PackIn reports failure while the shell exits successfully | Inspect the application result; the tool requires the emitted `Error=false` marker. |
| Unexpected metadata appears | Verify the runtime contains no unrelated custom bundles or activators. |

## Current Status

This repository is a pilot extracted from `com.cdsoftware.recurrent`. Static validation and Recurrent's database-backed `1.0.1` → `1.0.2` upgrade path have been demonstrated locally. Jenkins consumption and clean-runtime provisioning remain pilot milestones until verified on the CI agent.
