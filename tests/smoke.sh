#!/usr/bin/env sh

set -eu

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for script in "$REPOSITORY_DIR/bin/idempiere-plugin-ci" "$REPOSITORY_DIR"/libexec/*.sh; do
	sh -n "$script"
done

help_output=$("$REPOSITORY_DIR/bin/idempiere-plugin-ci" --help)
printf '%s\n' "$help_output" | grep -q 'validate-2pack-db'
printf '%s\n' "$help_output" | grep -q 'package-artifacts'

for source in "$REPOSITORY_DIR"/libexec/*.java; do
	if java "$source" >/dev/null 2>&1; then
		echo "Expected validator without arguments to reject its invocation: $source" >&2
		exit 1
	fi
done

for key in bundle.id test.bundle.id idempiere.version java.version maven.minimum.version; do
	grep -q "^${key}=" "$REPOSITORY_DIR/plugin-ci.properties.example"
done

echo '[PASS] Toolkit smoke tests'
