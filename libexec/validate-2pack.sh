#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=${PLUGIN_PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
CONFIG_FILE=${PLUGIN_CONFIG_FILE:-$REPOSITORY_DIR/plugin-ci.properties}

property() {
	sed -n "s/^$1=//p" "$CONFIG_FILE" | tail -n 1
}

BUNDLE_ID=$(property 'bundle.id')

java "$SCRIPT_DIR/TwoPackValidator.java" \
	"$REPOSITORY_DIR/$BUNDLE_ID"
