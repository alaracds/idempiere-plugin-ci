#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=${PLUGIN_PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
CONFIG_FILE=${PLUGIN_CONFIG_FILE:-$REPOSITORY_DIR/plugin-ci.properties}

if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ "${FORCE_COLOR:-0}" = '1' ]; }; then
	GREEN='\033[32m'
	RED='\033[31m'
	RESET='\033[0m'
else
	GREEN=''
	RED=''
	RESET=''
fi

fail() {
	printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$1" >&2
	exit 1
}

pass() {
	printf '%b[PASS]%b %s\n' "$GREEN" "$RESET" "$1"
}

property() {
	key=$1
	value=$(sed -n "s/^${key}=//p" "$CONFIG_FILE" | tail -n 1)
	[ -n "$value" ] || fail "Missing configuration property: $key"
	printf '%s' "$value"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

validate_manifest() {
	bundle_dir=$1
	manifest="$REPOSITORY_DIR/$bundle_dir/META-INF/MANIFEST.MF"
	[ -f "$manifest" ] || fail "Missing bundle manifest: $bundle_dir/META-INF/MANIFEST.MF"
	grep -q "^Bundle-SymbolicName: ${bundle_dir}\(;.*\)\?$" "$manifest" ||
		fail "$bundle_dir has an unexpected Bundle-SymbolicName"
	grep -q "^Bundle-Version: ${IDEMPIERE_VERSION}\.qualifier$" "$manifest" ||
		fail "$bundle_dir has an unexpected Bundle-Version"
	grep -q "^Bundle-RequiredExecutionEnvironment: JavaSE-${JAVA_VERSION}$" "$manifest" ||
		fail "$bundle_dir does not require JavaSE-${JAVA_VERSION}"
}

[ -f "$CONFIG_FILE" ] || fail 'Missing plugin-ci.properties'
require_command git
require_command java
require_command mvn
require_command mktemp
require_command sort

GIT_CONFIG_GLOBAL=$(mktemp "${TMPDIR:-/tmp}/plugin-ci-git-config.XXXXXX")
export GIT_CONFIG_GLOBAL
trap 'rm -f "$GIT_CONFIG_GLOBAL"' EXIT HUP INT TERM
git config --global --add safe.directory "$REPOSITORY_DIR"

BUNDLE_ID=$(property 'bundle.id')
TEST_BUNDLE_ID=$(property 'test.bundle.id')
IDEMPIERE_VERSION=$(property 'idempiere.version')
JAVA_VERSION=$(property 'java.version')
MAVEN_MINIMUM_VERSION=$(property 'maven.minimum.version')

actual_java=$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)
[ "$actual_java" = "$JAVA_VERSION" ] ||
	fail "Java $JAVA_VERSION is required; found ${actual_java:-unknown}"
pass 'Java version'

maven_version=$(mvn --version | sed -n '1s/.*Apache Maven \([0-9][0-9.]*\).*/\1/p')
[ -n "$maven_version" ] || fail 'Unable to determine the Maven version'
[ "$(printf '%s\n%s\n' "$MAVEN_MINIMUM_VERSION" "$maven_version" | sort -V | head -n 1)" = "$MAVEN_MINIMUM_VERSION" ] ||
	fail "Maven $MAVEN_MINIMUM_VERSION or newer is required; found $maven_version"
pass "Maven available ($maven_version)"

[ ! -f "$REPOSITORY_DIR/pom.xml" ] ||
	fail 'Repository-level pom.xml is incompatible with the target-platform builder'
java "$SCRIPT_DIR/PluginXmlValidator.java" \
	"$REPOSITORY_DIR/$BUNDLE_ID" \
	"$REPOSITORY_DIR/$TEST_BUNDLE_ID" \
	"$IDEMPIERE_VERSION" || fail 'Maven bundle POM validation failed'
pass 'Maven bundle POMs'

pass 'XML files'

validate_manifest "$BUNDLE_ID"
validate_manifest "$TEST_BUNDLE_ID"
grep -q "^Bundle-SymbolicName: ${BUNDLE_ID};singleton:=true$" \
	"$REPOSITORY_DIR/$BUNDLE_ID/META-INF/MANIFEST.MF" ||
	fail "$BUNDLE_ID must be an OSGi singleton"
grep -q 'org\.adempiere\.base' "$REPOSITORY_DIR/$BUNDLE_ID/META-INF/MANIFEST.MF" ||
	fail "$BUNDLE_ID must require org.adempiere.base"

if find "$REPOSITORY_DIR/$BUNDLE_ID/META-INF" -maxdepth 1 -type f -name '2Pack_*.zip' | grep -q .; then
	grep -q '^Bundle-Activator: org\.adempiere\.plugin\.utils\.Incremental2PackActivator$' \
		"$REPOSITORY_DIR/$BUNDLE_ID/META-INF/MANIFEST.MF" ||
		fail "$BUNDLE_ID ships incremental 2Packs without Incremental2PackActivator"
	grep -q 'org\.adempiere\.plugin\.utils' "$REPOSITORY_DIR/$BUNDLE_ID/META-INF/MANIFEST.MF" ||
		fail "$BUNDLE_ID ships incremental 2Packs without org.adempiere.plugin.utils"
fi
grep -q "^Fragment-Host: ${BUNDLE_ID}$" \
	"$REPOSITORY_DIR/$TEST_BUNDLE_ID/META-INF/MANIFEST.MF" ||
	fail "$TEST_BUNDLE_ID does not target fragment host $BUNDLE_ID"
pass 'OSGi metadata'

for bundle_dir in "$BUNDLE_ID" "$TEST_BUNDLE_ID"; do
	build_properties="$REPOSITORY_DIR/$bundle_dir/build.properties"
	[ -f "$build_properties" ] || fail "Missing $bundle_dir/build.properties"
	grep -q '^source\.\. = src/$' "$build_properties" ||
		fail "$bundle_dir/build.properties does not declare src/"
	grep -q '^bin\.includes = ' "$build_properties" ||
		fail "$bundle_dir/build.properties does not declare bin.includes"
done
if grep -q '^Service-Component:' "$REPOSITORY_DIR/$BUNDLE_ID/META-INF/MANIFEST.MF"; then
	grep -q 'OSGI-INF/' "$REPOSITORY_DIR/$BUNDLE_ID/build.properties" ||
		fail "$BUNDLE_ID declares services but does not package OSGI-INF/"
fi
pass 'Bundle build properties'

"$SCRIPT_DIR/validate-2pack.sh" || fail '2Pack validation failed'
pass '2Pack validation'

if git -C "$REPOSITORY_DIR" ls-files |
	grep -Eq '(^|/)(\.classpath|\.project|\.settings/|\.DS_Store$|bin/|target/)'; then
	fail 'Workstation or generated files are tracked by Git'
fi
git -C "$REPOSITORY_DIR" diff --check
git -C "$REPOSITORY_DIR" diff --cached --check
pass 'Repository hygiene'

pass 'Static plugin validation complete'
