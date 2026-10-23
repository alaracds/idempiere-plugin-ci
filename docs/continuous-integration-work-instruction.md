# Establish Continuous Integration for Maven-Based iDempiere Plugins

The purpose of this task is to establish a reproducible continuous integration process for Maven-based iDempiere plugins.

This is important because every change must produce the same result on a developer workstation and in Jenkins, with traceable artifacts and early detection of Java, OSGi, Application Dictionary, 2Pack, test, and documentation defects.

## TOC

- [Outcome](#outcome)
- [Scope](#scope)
- [Roles and authority](#roles-and-authority)
- [Required repository structure](#required-repository-structure)
- [Required configuration](#required-configuration)
- [Apply plugin development criteria](#apply-plugin-development-criteria)
- [Establish the local validation entry point](#establish-the-local-validation-entry-point)
- [Validate the repository](#validate-the-repository)
- [Validate 2Packs](#validate-2packs)
- [Generate models reproducibly](#generate-models-reproducibly)
- [Configure Jenkins](#configure-jenkins)
- [Publish immutable artifacts](#publish-immutable-artifacts)
- [Protect integration and release branches](#protect-integration-and-release-branches)
- [Add database-backed validation](#add-database-backed-validation)
- [Promote artifacts](#promote-artifacts)
- [Pilot rollout](#pilot-rollout)
- [Failure handling](#failure-handling)
- [Completion criteria](#completion-criteria)

## Outcome

The purpose of this section is to define the state that continuous integration must produce.

This is important because a successful Jenkins build is useful only when it represents a reproducible, reviewable, and deployable source state.

The completed flow is:

```text
Feature branch
  -> pull request to master
  -> master build and QA deployment
  -> QA approval
  -> pull request from master to [IDEMPIERE_VERSION]
  -> release build and approval
  -> production deployment
```

The same repository command must drive local validation and Jenkins validation. Jenkins must not hide required build logic in manually configured job steps.

## Scope

Use this task for an iDempiere OSGi plugin repository that:

- builds with Maven and Tycho;
- targets a declared iDempiere version;
- contains one or more plugin bundles;
- may contain an OSGi test fragment;
- may deliver Application Dictionary changes through incremental 2Packs.

This task establishes continuous integration and artifact production. It does not authorize automatic production deployment.

## Roles and authority

The purpose of this section is to keep source changes, CI administration, review, and deployment approval separate.

This is important because a passing build must not implicitly authorize merging or deployment.

| Role | Responsibility | Authority boundary |
| --- | --- | --- |
| Plugin developer | Maintains plugin code, models, tests, POMs, 2Packs, and documentation. | May publish feature branches; may not bypass protected-branch checks. |
| Reviewer | Verifies behavior, scope, upgrade safety, and test evidence. | Approves or rejects the pull request; does not replace CI evidence. |
| CI administrator | Maintains Jenkins agents, credentials, shared pipeline logic, webhooks, and artifact retention. | May change CI infrastructure; does not approve functional behavior. |
| Release approver | Approves promotion from `master` to the applicable iDempiere version branch and authorizes its release artifact. | May promote an archived release artifact; must not rebuild it after approval. |

## Required repository structure

The purpose of this section is to give every plugin the same build and discovery shape.

This is important because shared validation and Jenkins logic depend on predictable entry points.

Use this structure unless the repository has a documented multi-bundle exception:

```text
[PLUGIN_REPOSITORY]/
├── Jenkinsfile
├── README.md
├── plugin-ci.properties
├── ci/
│   └── sql/
│       ├── [PLUGIN]-2pack-clean.sql
│       ├── [PLUGIN]-2pack-initial.sql
│       ├── [PLUGIN]-2pack-current.sql
│       └── [PLUGIN]-2pack-fingerprint.sql
├── tools/
│   └── generate-model.sh
├── [BUNDLE_ID]/
│   ├── pom.xml
│   ├── META-INF/
│   │   └── MANIFEST.MF
│   ├── build.properties
│   └── src/
└── [BUNDLE_ID].test/
    ├── pom.xml
    ├── META-INF/
    │   └── MANIFEST.MF
    ├── build.properties
    └── src/
```

Do not add a repository-level reactor POM when the approved target-platform builder expects bundle directories as its inputs. Each production bundle and test fragment must have its own POM, inherit directly from `org.idempiere.parent`, and declare the supported iDempiere revision.

Pass every bundle directory explicitly to the target-platform builder. For example:

```bash
./plugin-builder build \
  ../[BUNDLE_ID] \
  ../[BUNDLE_ID].test
```

The builder rewrites the bundle POM's `org.idempiere.parent` relative path for its isolated environment and generates the temporary reactor used by Maven. A bundle must not inherit through a repository-specific aggregator because that prevents this rewrite.

Ignore generated and workstation-specific content at repository level:

```gitignore
.classpath
.project
.settings/
bin/
target/
```

Track an IDE file only when it is intentionally standardized for every contributor and reviewed as source.

## Required configuration

The purpose of this section is to keep plugin-specific values outside shared scripts.

This is important because validation scripts should be reusable without copying and editing their logic for each plugin.

Create `plugin-ci.properties` with non-secret configuration:

```properties
bundle.id=[BUNDLE_ID]
test.bundle.id=[TEST_BUNDLE_ID]
idempiere.version=[IDEMPIERE_MAJOR_VERSION]
java.version=[JAVA_MAJOR_VERSION]
maven.minimum.version=[MAVEN_MINIMUM_VERSION]
entity.type=[ENTITY_TYPE]
model.package=[MODEL_PACKAGE]
model.source=[BUNDLE_ID]/src
model.tables=[TABLE_NAME]
packin.client=SYSTEM
packin.initial.version=[RELEASED_VERSION]
packin.candidate.version=[CANDIDATE_VERSION]
```

Do not store passwords, tokens, private repository credentials, production hostnames, or client identifiers in this file.

Jenkins credentials must be injected through its credential store. Local database credentials must use the approved local credential mechanism and must not be printed by validation scripts.

## Apply plugin development criteria

The purpose of this section is to translate the official iDempiere plugin-development guidance into verifiable repository requirements.

This is important because successful Java compilation alone does not prove that Equinox can identify, activate, manage, or distribute the bundle.

Use the supported iDempiere source checkout as the authority for runtime behavior. Use the official plugin-development documentation as design and distribution guidance. When they differ, record the supported iDempiere revision and verify the behavior in its source before creating a blocking rule.

Every production plugin must:

- live outside the iDempiere core repository so core upgrades do not mix with customization history;
- declare `org.adempiere.base` in `Require-Bundle`;
- declare `Bundle-SymbolicName` with `singleton:=true`;
- use `eclipse-plugin` Maven packaging and keep the POM `artifactId`, project directory, and bundle symbolic name consistent;
- declare only the bundle dependencies it actually uses and keep their supported iDempiere versions aligned;
- package every runtime resource named by its manifest, including Declarative Services descriptors under `OSGI-INF/`;
- use `plugin.xml` only for required Equinox extension points; use OSGi Declarative Services for registered services where the supported iDempiere API provides them;
- use `Incremental2PackActivator` and require `org.adempiere.plugin.utils` when it delivers incremental 2Packs;
- avoid a custom activator unless startup or shutdown behavior beyond the supported utility activators is necessary and tested.

Classify verification by lifecycle stage:

| Stage | Required evidence |
| --- | --- |
| Static validation | POM packaging and identity, singleton declaration, required bundles, activator/2Pack consistency, service descriptors, and packaged resources. |
| Target-platform build | Tycho resolves the declared dependencies and produces the plugin and test-fragment JARs. |
| Runtime smoke test | The bundle reaches `ACTIVE`; Declarative Services are satisfied; the expected process, model factory, callout, or other service is discoverable. |
| Installation test | A clean supported iDempiere instance installs the artifact and its 2Packs without undeclared manual prerequisites. |
| Upgrade test | A previously released artifact upgrades to the candidate while preserving incremental 2Pack order and data. |

A feature project, p2 repository, and target-platform project are required only when the selected distribution mechanism uses them. If p2 distribution is adopted, validate feature membership, feature and category IDs, `eclipse-feature`/`eclipse-repository` packaging, and install/update/uninstall from the produced repository. Do not require those projects for a plugin distributed through the existing company bundle workflow.

## Establish the local validation entry point

The purpose of this section is to provide one command that answers whether a branch is ready for Jenkins.

This is important because developers need the same result before push that Jenkins will enforce afterward.

Use the pinned shared CI tool as the local entry point:

```bash
idempiere-plugin-ci --project-dir [PLUGIN_REPOSITORY] validate
```

The script must:

- stop on the first blocking error;
- return `0` only when all required checks pass;
- return a nonzero status for failure;
- identify the failed check and corrective action;
- avoid modifying tracked source files;
- write temporary output outside the repository or into ignored build directories;
- call specialized validators instead of duplicating their logic.

Use stable status labels:

```text
[PASS] Java version
[PASS] Maven bundle POMs
[PASS] OSGi metadata
[PASS] Java compilation
[PASS] Tests
[PASS] 2Pack validation
[PASS] README validation
[PASS] Repository hygiene
```

Jenkins must call this script rather than reimplementing its checks.

## Validate the repository

The purpose of this section is to define the minimum checks required for every plugin branch.

This is important because a plugin can compile while still containing invalid OSGi metadata, accidental IDE files, incomplete documentation, or nonportable paths.

`validate-plugin.sh` must verify:

- the required Java version is active;
- Maven meets the minimum version required by Tycho;
- the Maven Wrapper is preferred when the repository or iDempiere checkout provides one;
- every configured production bundle and test fragment exists;
- every bundle contains a POM that inherits directly from `org.idempiere.parent`;
- every bundle POM declares the supported iDempiere revision and a portable local relative path;
- the target-platform builder receives every configured bundle directory explicitly;
- XML files are well formed;
- every `MANIFEST.MF` has a valid symbolic name and version;
- bundle IDs, artifact IDs, and project directories agree where the repository standard requires it;
- `build.properties` contains required runtime resources;
- all Java sources compile;
- all configured tests execute;
- `git diff --check` passes;
- no prohibited workstation file is staged or tracked;
- generated output is not staged;
- README content reflects actual bundles, processes, models, and 2Packs.

Do not treat Maven `validate` as proof that Java compilation succeeded. When Tycho packaging cannot run because the target platform is unavailable, report the environment failure separately and run the approved fallback compilation check. Jenkins must still require the full target-platform build.

## Validate 2Packs

The purpose of this section is to detect Application Dictionary packages that the supported iDempiere source code cannot import consistently.

This is important because validation rules must reproduce actual runtime contracts, not assumptions about how a 2Pack ought to be structured.

Treat the iDempiere source checkout used by the build as the source of truth. Every blocking rule must cite the local class and behavior that justify it. Re-audit the rule when the supported iDempiere revision changes. Keep organization policies in a separate, explicitly approved policy check; do not present them as iDempiere requirements.

`validate-2pack.sh` must inspect every versioned 2Pack and verify:

- ZIP integrity;
- a nonempty ZIP whose first entry identifies the root directory used by `Zipper.getParentDir`;
- presence of `[ROOT]/dict/PackOut.xml`, as resolved by `PipoDictionaryService`;
- well-formed package XML;
- the `idempiere` root consumed by `PackInHandler`;
- root attributes used without null handling by `PackInHandler`, including a parseable `Client` and `Description`;
- a three-component numeric version in each `2Pack_X.Y.Z[_INFO].zip` filename: `Incremental2PackActivator` orders by that filename and `PipoDictionaryService` only recognizes filename versions with three components;
- no two filenames whose versions compare equal under `org.adempiere.plugin.utils.Version`;
- immutability of 2Packs already released;
- inclusion of each required ZIP in the bundle build;
- well-formed auxiliary XML generated by PackOut when the runtime consumes it.

The baseline runtime-compatible validator must not assume that the ZIP root or XML package name equals the bundle ID, restrict `EntityType`, reject named transaction tables, or impose global UUID uniqueness. The cited iDempiere import path does not enforce those conditions. Add such controls only as separately documented organization policy with its own evidence, owner, and tests.

Classify findings consistently:

| Severity | Meaning | Pipeline result |
| --- | --- | --- |
| Error | Installation, portability, security, or consistency risk. | Fail. |
| Warning | Known limitation that does not invalidate the main package. | Pass with visible warning until a deadline or policy promotes it to error. |
| Information | Expected metadata or ordering change. | Pass and record. |

A new 2Pack must be exported with PackOut from the supported iDempiere version. Do not hand-edit `PackOut.xml` to make validation pass.

For plugins using `Incremental2PackActivator`, the filename is the authoritative package version used for ordering and installation history. Do not require the root `Version` attribute inside `PackOut.xml` to match the filename unless a different runtime component explicitly consumes that attribute.

## Generate models reproducibly

The purpose of this section is to regenerate persistent models with a reviewed, repeatable command.

This is important because manual Model Generator parameters and inconsistent Equinox launch configurations produce accidental or incomplete model changes.

Implement:

```bash
./tools/generate-model.sh [TABLE_NAME]
```

The wrapper must read defaults from `plugin-ci.properties` and:

- require the configured Java version;
- launch `org.adempiere.base.ModelGeneratorApplication` from the supported iDempiere product;
- use the configured source folder, model package, table `EntityType`, table name, and column `EntityType`;
- terminate the asynchronous Equinox runtime after generation completes;
- fail when the source folder or table is missing;
- show the generated file list and Git diff;
- fail when unexpected source files change;
- warn when the product build and database build differ;
- avoid logging database credentials.

Run the generator only after the Application Dictionary and physical schema are synchronized. Two consecutive executions without dictionary changes must produce no additional diff.

## Configure Jenkins

The purpose of this section is to make Jenkins the authoritative integration check for every branch and pull request.

This is important because successful local validation does not replace an isolated build with controlled versions and credentials.

Prefer a Multibranch Pipeline triggered by a source-control webhook. Periodic branch scanning may remain as a recovery mechanism, not the primary trigger.

The Jenkins pipeline must execute these stages:

```text
Checkout
  -> Environment
  -> Validate
  -> Test
  -> Package
  -> Archive
  -> Report
```

Required behavior:

- `Environment` reports Java, Maven, Tycho, and iDempiere versions.
- `Validate` enforces version compatibility for direct builds and pull requests targeting a version branch.
- `Validate` runs the pinned shared tool's `validate` command.
- `Test` fails when no tests execute and publishes standard JUnit results.
- `Package` builds against the approved target platform.
- `Package` validates each produced JAR by reading its OSGi manifest rather than assuming its filename, and verifies its version and required packaged resources.
- `Archive` stores the exact production and test-fragment JARs with their SHA-256 checksums and Jenkins fingerprints.
- `Report` exposes the commit, branch, checks, warnings, and artifact identity.

Keep shared pipeline logic in the versioned `idempiere-plugin-ci` repository. A plugin Jenkinsfile should keep its stages and dependencies visible, check out a pinned tool tag or commit, and invoke the corresponding command instead of duplicating its implementation.

Never use an unversioned container image for a release build. Pin the builder image or toolchain to an approved immutable version.

## Publish immutable artifacts

The purpose of this section is to make every deliverable traceable to one source commit and one CI execution.

This is important because each environment must receive the exact artifact approved from its own Jenkins branch job.

Use the branch itself as the deployment context:

| Branch | Purpose |
| --- | --- |
| `master` | Build the current candidate deployed and evaluated in QA. |
| Active `X.Y.Z` | Build the production candidate after QA approves promotion from `master`. |
| Historical `X.Y.Z` | Preserve a previous iDempiere line and build maintenance fixes based on that branch. |
| Any other branch | Validate development or maintenance work before merge. |

Recognize version branches with `^[0-9]+\.[0-9]+\.[0-9]+$`; do not maintain a fixed list of iDempiere versions. A direct version-branch build must match its configured `idempiere.version` and the compatible versions declared by the POMs, manifests, target platform, builder, and iDempiere dependencies.

Archive:

- the production plugin JAR;
- test results;
- included 2Packs;
- SHA-256 checksums;
- the validation report;
- a build manifest;
- release notes when the build is a release candidate.

Use an artifact name that includes the bundle, compatible version, short commit SHA, and Jenkins build number:

```text
[BUNDLE_ID]-[IDEMPIERE_VERSION]-[SHORT_SHA]-b[JENKINS_BUILD].jar
```

The build manifest must record at least:

```json
{
  "bundle": "[BUNDLE_ID]",
  "branch": "[BRANCH_NAME]",
  "commit": "[COMMIT_SHA]",
  "jenkinsBuild": "[BUILD_NUMBER]",
  "java": "[JAVA_VERSION]",
  "maven": "[MAVEN_VERSION]",
  "idempiere": "[IDEMPIERE_VERSION]",
  "twoPacks": ["[2PACK_FILE]"]
}
```

The QA artifact built from `master` and the production artifact built after merging into the release branch are distinct artifacts and are not expected to have the same checksum. Preserve their source relationship through pull-request and commit metadata. After the release artifact is approved, deploy that archived artifact by checksum without rebuilding it.

## Protect integration and release branches

The purpose of this section is to prevent unvalidated source from becoming a release candidate.

This is important because CI is advisory unless repository policy enforces its result.

Configure `master` to require:

- pull requests;
- a successful Jenkins status check;
- an up-to-date branch or the organization's approved merge policy;
- the required reviewer approval;
- resolved review conversations;
- no direct pushes except a documented emergency authority;
- no modification or removal of a previously released 2Pack.

Build feature branches and pull requests. Build the resulting `master` commit again after merge and archive it as the QA candidate.

Protect every branch matching `X.Y.Z` with the same review and CI requirements. Promotion to the active version branch normally uses a pull request from `master`. Maintenance of a historical version starts from that historical branch and returns to the same branch through a pull request. Jenkins must not assume that every pull request targeting `X.Y.Z` originates from `master`; it must verify that the resulting configuration still targets `X.Y.Z`.

## Add database-backed validation

The purpose of this section is to prove that incremental metadata installs and updates correctly, not only that its XML looks correct.

This is important because PackIn behavior, schema synchronization, defaults, translations, and idempotency cannot be proven by static inspection alone.

Provide an ephemeral PostgreSQL database with the supported iDempiere seed and run:

```text
Create clean database
  -> install released 2Packs in order
  -> install the candidate 2Pack
  -> verify dictionary and physical schema
  -> reinstall the candidate 2Pack
  -> verify idempotency
  -> discard the database
```

Project-specific assertions must be versioned with the plugin and contain no production data. Verify, as applicable:

- expected tables, columns, constraints, and defaults;
- expected windows, tabs, fields, processes, references, and translations;
- preservation of upgrade data;
- absence of duplicate metadata after reinstall;
- successful opening or execution of affected components;
- exclusion of transaction data from the package.

Database-backed validation becomes a required Jenkins check after the pilot is stable and its runtime is acceptable.

Use iDempiere's `org.adempiere.base.PackInFolderApplication` through the distributed `utils/RUN_ApplyPackInFromFolder.sh` entry point. Do not implement another XML importer, invoke `PackIn` classes with an ad hoc classpath, or reproduce Application Dictionary changes with SQL. The configured iDempiere runtime and its source version are part of the test fixture.

The shared entry point is `idempiere-plugin-ci --project-dir [PLUGIN_REPOSITORY] validate-2pack-db`. It must:

- require `IDEMPIERE_DB_VALIDATION=1` as explicit confirmation that the target is disposable;
- require `IDEMPIERE_HOME` to reference a configured installation containing `idempiereEnv.properties`, `utils/myEnvironment.sh`, and the official PackIn runner;
- require `EXPECTED_DATABASE` and compare it with both the iDempiere configuration and the live PostgreSQL connection before writing;
- read non-secret package versions and the PackIn client from `plugin-ci.properties`;
- stage versioned 2Packs under deterministic names that satisfy the `PackInFolder` filename contract;
- require the application's `Error=false` result because the distributed shell wrapper does not propagate the Java application's exit code;
- execute project-specific SQL assertions after the initial package, candidate upgrade, and candidate reinstall;
- remove only the temporary staging directory it created;
- fail on the first PackIn, connection, or assertion error.

Run it locally only against a newly restored seed database:

```bash
export IDEMPIERE_HOME=/srv/idempiere-ci
export EXPECTED_DATABASE=idempiere_plugin_ci
export IDEMPIERE_DB_VALIDATION=1
idempiere-plugin-ci --project-dir [PLUGIN_REPOSITORY] validate-2pack-db
```

The configured installation supplies PackIn's database credential through the normal iDempiere secret mechanism. PostgreSQL assertions use standard libpq authentication such as a restricted `.pgpass` entry. Do not put either credential in the repository or command arguments.

In Jenkins, provision the database and configured iDempiere runtime before this command and discard them afterward. Build the runtime from the supported clean iDempiere distribution; do not clone an environment containing unrelated custom bundles because their activators can install additional 2Packs during startup. Keep provisioning outside the plugin repository so every plugin uses the same seed image and lifecycle. Bind required credentials through Jenkins credentials, mask their output, and do not archive the configured runtime.

The clean-baseline assertion must reject an already-installed plugin. This keeps the result reproducible and ensures the test covers both the released baseline and candidate upgrade. A failed run preserves Jenkins logs and may preserve the disposable database temporarily for diagnosis according to the CI retention policy.

## Promote artifacts

The purpose of this section is to separate artifact production from environment deployment.

This is important because automatic compilation should not silently become automatic production change authority.

Use this promotion path:

```text
Feature branch
  -> pull request to master
  -> master artifact deployment to QA
  -> smoke and functional tests
  -> QA approval
  -> pull request from master to [IDEMPIERE_VERSION]
  -> release-branch build
  -> release approval
  -> production deployment of the archived release artifact
  -> health check
```

The merge into `[IDEMPIERE_VERSION]` authorizes Jenkins to create a production candidate; it does not authorize deployment by itself. Start with manual deployment using CI-produced artifacts. Automate QA only after artifact identity, backup, health checks, and rollback have been proven. Keep production approval manual until the organization explicitly changes that policy.

For a historical release, use this maintenance path:

```text
Historical [IDEMPIERE_VERSION]
  -> maintenance branch created from that version
  -> compatible correction and validation
  -> pull request back to the same [IDEMPIERE_VERSION]
  -> version-branch build and approval
  -> production deployment of the archived maintenance artifact
```

Before a deployment that imports metadata:

- identify the target iDempiere and database versions;
- confirm the next required 2Pack version;
- create the approved backup or restore point;
- record the current plugin artifact checksum;
- define rollback for the bundle and database metadata.

## Pilot rollout

The purpose of this section is to introduce the standard through one representative plugin before applying it broadly.

This is important because the pilot should expose assumptions in the shared scripts and Jenkins environment without disrupting every repository.

Use a plugin that contains Java code, generated models, a test fragment, translations, and incremental 2Packs.

Roll out in this order:

| Milestone | Deliverable | Exit condition |
| --- | --- | --- |
| Baseline | Current build, dependencies, Jenkins job, and artifact behavior documented. | Another developer can reproduce the current build. |
| Local validator | `validate-plugin.sh` and configuration. | Local and Jenkins checks agree. |
| 2Pack validator | Static package report. | Known packages pass and seeded defects fail. |
| Model wrapper | Reproducible generator command. | A second run produces no diff. |
| Jenkins integration | Webhook-driven multibranch pipeline. | Every push and pull request receives a status. |
| Branch policy | Current promotion and historical maintenance paths. | Version-branch builds and pull requests retain the target iDempiere compatibility. |
| Immutable artifacts | JAR, checksums, manifest, and reports archived. | An artifact resolves to one branch, commit, and build. |
| Database validation | Clean install, upgrade, and reinstall test. | Candidate 2Pack is portable and idempotent. |
| QA promotion | Controlled deployment of the archived artifact. | QA verifies the exact artifact intended for release. |

Do not copy the pilot scripts into other repositories until plugin-specific values have been removed into configuration and the shared behavior has been tested.

## Failure handling

The purpose of this section is to make failures actionable and prevent unsafe bypasses.

This is important because recurring warnings and environment failures otherwise become normalized and stop protecting the release.

| Failure | Required response |
| --- | --- |
| Local pass, Jenkins fail | Compare toolchain and target-platform identities; do not weaken the check. |
| Target platform unavailable | Mark as infrastructure failure, retain logs, and do not report compilation success. |
| 2Pack static validation fails | Correct the dictionary and export a new candidate; do not edit released ZIPs. |
| Clean PackIn fails | Preserve the disposable database and logs long enough to diagnose; block merge. |
| Reinstall creates duplicates | Correct UUIDs or package dependencies; block merge. |
| Model Generator changes unexpected files | Stop and reconcile dictionary metadata before commit. |
| Auxiliary generated XML is invalid | Record as a warning only when the main package remains valid and policy explicitly allows it; assign removal criteria. |
| Jenkins is unavailable | Keep the pull request open; only documented emergency authority may apply an exception. |
| Artifact checksum changes after approval | Reject the artifact and repeat validation and approval. |

An exception must identify its owner, reason, affected check, expiration, and remediation. Permanent exceptions belong in policy, not in build parameters.

## Completion criteria

The continuous integration implementation is complete for a plugin when:

- one local command runs the required validation;
- Jenkins runs the same command in a controlled toolchain;
- every push and pull request receives an automatic result;
- the full Maven/Tycho build uses the approved target platform;
- Java compilation and tests pass;
- 2Packs pass static validation;
- candidate 2Packs pass clean installation, upgrade, and idempotency checks;
- `master` and applicable `X.Y.Z` branches require the Jenkins result and review approval;
- each successful `master` build publishes an immutable QA artifact;
- each successful release-branch build publishes a distinct immutable production candidate;
- production deploys the approved release artifact without rebuilding it;
- production deployment remains an explicitly authorized action;
- the pilot procedure is configuration-driven and reusable by another Maven-based iDempiere plugin.

Tags: iDempiere, Maven, Tycho, Jenkins, continuous integration, OSGi, 2Pack, PostgreSQL
