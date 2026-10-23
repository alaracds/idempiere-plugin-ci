#!/usr/bin/env sh

set -eu

if [ "$#" -ne 3 ]; then
	echo 'Usage: validate-branch.sh BRANCH_NAME CHANGE_BRANCH CHANGE_TARGET' >&2
	exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=${PLUGIN_PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
CONFIG_FILE=${PLUGIN_CONFIG_FILE:-$REPOSITORY_DIR/plugin-ci.properties}
BRANCH_NAME=$1
CHANGE_BRANCH=$2
CHANGE_TARGET=$3
IDEMPIERE_VERSION=$(sed -n 's/^idempiere.version=//p' "$CONFIG_FILE" | tail -n 1)
RELEASE_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

[ -n "$BRANCH_NAME" ] || {
	echo '[FAIL] BRANCH_NAME is required' >&2
	exit 1
}

if printf '%s\n' "$BRANCH_NAME" | grep -Eq "$RELEASE_PATTERN"; then
	[ "$BRANCH_NAME" = "$IDEMPIERE_VERSION" ] || {
		echo "[FAIL] Release branch $BRANCH_NAME does not match iDempiere $IDEMPIERE_VERSION" >&2
		exit 1
	}
fi

if printf '%s\n' "$CHANGE_TARGET" | grep -Eq "$RELEASE_PATTERN"; then
	[ "$CHANGE_TARGET" = "$IDEMPIERE_VERSION" ] || {
		echo "[FAIL] Pull request target $CHANGE_TARGET does not match iDempiere $IDEMPIERE_VERSION" >&2
		exit 1
	}
fi

echo "[PASS] Branch policy ($BRANCH_NAME)"
