#!/usr/bin/env sh

set -eu

if [ "$#" -ne 1 ]; then
	echo 'Usage: compile.sh TARGET_PLATFORM_DIR' >&2
	exit 1
fi

TARGET_PLATFORM_DIR=$(CDPATH= cd -- "$1" && pwd)
CONFIG_FILE=${PLUGIN_CONFIG_FILE:-${PLUGIN_PROJECT_DIR:-$(pwd)}/plugin-ci.properties}
PROJECT_DIR=${PLUGIN_PROJECT_DIR:-$(pwd)}
BUILDER="$TARGET_PLATFORM_DIR/plugin-builder"
BUILD_NUMBER=${BUILD_NUMBER:-0}
export BUILD_NUMBER

property() {
	value=$(sed -n "s/^$1=//p" "$CONFIG_FILE" | tail -n 1)
	[ -n "$value" ] || { echo "[FAIL] Missing configuration property: $1" >&2; exit 1; }
	printf '%s' "$value"
}

[ -x "$BUILDER" ] || { echo "[FAIL] Target platform builder is unavailable: $BUILDER" >&2; exit 1; }
[ -n "${IDEMPIERE_REPOSITORY:-}" ] || { echo '[FAIL] IDEMPIERE_REPOSITORY is required by plugin-builder' >&2; exit 1; }
[ -d "$IDEMPIERE_REPOSITORY" ] || { echo "[FAIL] IDEMPIERE_REPOSITORY does not exist: $IDEMPIERE_REPOSITORY" >&2; exit 1; }
BUNDLE_ID=$(property 'bundle.id')
TEST_BUNDLE_ID=$(property 'test.bundle.id')
[ -d "$PROJECT_DIR/$BUNDLE_ID" ] || { echo "[FAIL] Missing bundle: $BUNDLE_ID" >&2; exit 1; }
[ -d "$PROJECT_DIR/$TEST_BUNDLE_ID" ] || { echo "[FAIL] Missing test bundle: $TEST_BUNDLE_ID" >&2; exit 1; }

cd "$TARGET_PLATFORM_DIR"
./plugin-builder build "$PROJECT_DIR/$BUNDLE_ID" "$PROJECT_DIR/$TEST_BUNDLE_ID"
