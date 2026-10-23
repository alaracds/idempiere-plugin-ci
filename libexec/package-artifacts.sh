#!/usr/bin/env sh

set -eu

if [ "$#" -ne 4 ]; then
	echo 'Usage: package-artifacts.sh ARTIFACT_DIR OUTPUT_DIR BRANCH_NAME BUILD_NUMBER' >&2
	exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=${PLUGIN_PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
CONFIG_FILE=${PLUGIN_CONFIG_FILE:-$REPOSITORY_DIR/plugin-ci.properties}

property() {
	sed -n "s/^$1=//p" "$CONFIG_FILE" | tail -n 1
}

BUNDLE_ID=$(property 'bundle.id')
TEST_BUNDLE_ID=$(property 'test.bundle.id')
IDEMPIERE_VERSION=$(property 'idempiere.version')
JAVA_VERSION=$(property 'java.version')
MAVEN_VERSION=$(mvn --version | sed -n '1s/.*Apache Maven \([0-9][0-9.]*\).*/\1/p')
COMMIT=$(git -C "$REPOSITORY_DIR" rev-parse HEAD)

java "$SCRIPT_DIR/BuildArtifactPackager.java" \
	"$1" "$2" "$BUNDLE_ID" "$TEST_BUNDLE_ID" "$IDEMPIERE_VERSION" \
	"$3" "$COMMIT" "$4" "$JAVA_VERSION" "$MAVEN_VERSION"
