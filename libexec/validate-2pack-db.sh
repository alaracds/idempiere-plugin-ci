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

environment_property() {
	key=$1
	sed -n "s/^${key}=//p" "$IDEMPIERE_ENV_FILE" | tail -n 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

run_assertions() {
	assertion_file=$1
	PGOPTIONS="${PGOPTIONS:-} -c search_path=adempiere,public" \
		psql -X -v ON_ERROR_STOP=1 -q -f "$assertion_file"
}

run_packin() {
	packin_directory=$1
	packin_label=$2
	packin_log="$STAGING_DIR/packin-${packin_label}.log"
	if ! "$PACKIN_RUNNER" "$packin_directory" >"$packin_log" 2>&1; then
		cat "$packin_log" >&2
		fail "PackIn $packin_label command failed"
	fi
	cat "$packin_log"
	grep -Eq '^[[:space:]]*Error=false[[:space:]]*$' "$packin_log" ||
		fail "PackIn $packin_label did not report Error=false"
}

stage_pack() {
	version=$1
	sequence=$2
	source_file="$REPOSITORY_DIR/$BUNDLE_ID/META-INF/2Pack_${version}.zip"
	target_dir=$3
	[ -f "$source_file" ] || fail "Missing 2Pack: $source_file"
	cp "$source_file" "$target_dir/20000101${sequence}_${PACKIN_CLIENT}_${BUNDLE_ID}_${version}.zip"
}

[ -f "$CONFIG_FILE" ] || fail 'Missing plugin-ci.properties'
require_command cp
require_command mktemp
require_command psql

[ "${IDEMPIERE_DB_VALIDATION:-0}" = '1' ] ||
	fail 'Set IDEMPIERE_DB_VALIDATION=1 to confirm that the configured database is disposable'
[ -n "${IDEMPIERE_HOME:-}" ] || fail 'IDEMPIERE_HOME is required'
[ -n "${EXPECTED_DATABASE:-}" ] || fail 'EXPECTED_DATABASE is required'

IDEMPIERE_ENV_FILE="$IDEMPIERE_HOME/idempiereEnv.properties"
PACKIN_RUNNER="$IDEMPIERE_HOME/utils/RUN_ApplyPackInFromFolder.sh"
[ -f "$IDEMPIERE_ENV_FILE" ] || fail "Missing configured iDempiere environment: $IDEMPIERE_ENV_FILE"
[ -x "$PACKIN_RUNNER" ] || fail "Missing executable PackIn runner: $PACKIN_RUNNER"
[ -x "$IDEMPIERE_HOME/utils/myEnvironment.sh" ] ||
	fail "Missing configured environment script: $IDEMPIERE_HOME/utils/myEnvironment.sh"

BUNDLE_ID=$(property 'bundle.id')
PACKIN_CLIENT=$(property 'packin.client')
INITIAL_VERSION=$(property 'packin.initial.version')
CANDIDATE_VERSION=$(property 'packin.candidate.version')
CLEAN_ASSERTIONS=$(property 'packin.assertions.clean')
INITIAL_ASSERTIONS=$(property 'packin.assertions.initial')
CURRENT_ASSERTIONS=$(property 'packin.assertions.current')
FINGERPRINT_QUERY=$(property 'packin.assertions.fingerprint')

CONFIGURED_DATABASE=$(environment_property 'ADEMPIERE_DB_NAME')
[ "$CONFIGURED_DATABASE" = "$EXPECTED_DATABASE" ] ||
	fail "Configured iDempiere database '$CONFIGURED_DATABASE' does not match EXPECTED_DATABASE '$EXPECTED_DATABASE'"

export PGHOST=${PGHOST:-$(environment_property 'ADEMPIERE_DB_SERVER')}
export PGPORT=${PGPORT:-$(environment_property 'ADEMPIERE_DB_PORT')}
export PGDATABASE=${PGDATABASE:-$CONFIGURED_DATABASE}
export PGUSER=${PGUSER:-$(environment_property 'ADEMPIERE_DB_USER')}
[ "$PGDATABASE" = "$EXPECTED_DATABASE" ] ||
	fail "PostgreSQL target '$PGDATABASE' does not match EXPECTED_DATABASE '$EXPECTED_DATABASE'"

connected_database=$(psql -X -v ON_ERROR_STOP=1 -Atqc 'select current_database()') ||
	fail 'Unable to connect to the validation database'
[ "$connected_database" = "$EXPECTED_DATABASE" ] ||
	fail "Connected database '$connected_database' does not match EXPECTED_DATABASE '$EXPECTED_DATABASE'"
pass "Disposable database guard ($connected_database)"

run_assertions "$REPOSITORY_DIR/$CLEAN_ASSERTIONS" || fail 'Database is not a clean plugin baseline'
pass 'Clean plugin baseline'

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idempiere-plugin-2pack-db.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM
mkdir -p "$STAGING_DIR/initial" "$STAGING_DIR/candidate"

stage_pack "$INITIAL_VERSION" '0001' "$STAGING_DIR/initial"
run_packin "$STAGING_DIR/initial" "$INITIAL_VERSION"
run_assertions "$REPOSITORY_DIR/$INITIAL_ASSERTIONS" || fail "Assertions for 2Pack $INITIAL_VERSION failed"
pass "2Pack $INITIAL_VERSION installation"

stage_pack "$CANDIDATE_VERSION" '0002' "$STAGING_DIR/candidate"
run_packin "$STAGING_DIR/candidate" "$CANDIDATE_VERSION"
run_assertions "$REPOSITORY_DIR/$CURRENT_ASSERTIONS" || fail "Assertions for 2Pack $CANDIDATE_VERSION failed"
pass "2Pack $CANDIDATE_VERSION upgrade"

before_counts=$(psql -X -v ON_ERROR_STOP=1 -Atqf "$REPOSITORY_DIR/$FINGERPRINT_QUERY")
run_packin "$STAGING_DIR/candidate" "${CANDIDATE_VERSION}-reinstall"
after_counts=$(psql -X -v ON_ERROR_STOP=1 -Atqf "$REPOSITORY_DIR/$FINGERPRINT_QUERY")
[ "$before_counts" = "$after_counts" ] ||
	fail "Metadata counts changed after reinstall ($before_counts -> $after_counts)"
run_assertions "$REPOSITORY_DIR/$CURRENT_ASSERTIONS" || fail 'Assertions failed after reinstall'
pass "2Pack $CANDIDATE_VERSION reinstall is idempotent"

pass 'Database-backed 2Pack validation complete'
