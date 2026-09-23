#!/usr/bin/env bash
# Saved add-on options: production is the reference for every fresh install.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUN_SH="$SCRIPT_DIR/../run.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

load_function() {
	local name=$1
	local definition
	definition=$(sed -n "/^\t${name}() {/,/^\t}/p" "$RUN_SH")
	if [ -z "$definition" ]; then
		echo "Function not found: $name" >&2
		exit 1
	fi
	eval "$definition"
}

load_function choose_preserve_files
load_function restore_saved_options
load_function save_options

curl() {
	:
}

bashio::log.info() {
	:
}

bashio::log.warning() {
	echo "warning: $*" >&2
}

assert_json() {
	local file=$1 filter=$2 expected=$3 actual
	actual=$(jq -c "$filter" "$file")
	if [ "$actual" != "$expected" ]; then
		echo "Expected $filter in $file to be $expected, got $actual" >&2
		exit 1
	fi
}

AUTH_HEADER="Authorization: Bearer test"
SUPERVISOR="http://supervisor"

# One Home Assistant: a shared /share and a fresh /data per install.
PRESERVE_DIR="$TEST_TMP/share/.librecoach-preserve"
PRESERVE_FILE="$PRESERVE_DIR/options.json"
PRERELEASE_PRESERVE_FILE="$PRESERVE_DIR/options-prerelease.json"
DEFAULTS='{"hughes_enabled":false,"mqtt_pass":"default","debug_logging":false}'

# Start an install of a given version, then run the boot-time restore.
boot() {
	local version=$1 fresh=${2:-fresh}
	ADDON_VERSION=$version
	DATA_DIR="$TEST_TMP/data-$version"
	STATE_FILE="$DATA_DIR/.librecoach-state.json"
	OPTIONS_FILE="$DATA_DIR/options.json"
	if [ "$fresh" = "fresh" ]; then
		rm -rf "$DATA_DIR"
		mkdir -p "$DATA_DIR"
		echo "$DEFAULTS" >"$OPTIONS_FILE"
	fi
	choose_preserve_files
	restore_saved_options
	touch "$STATE_FILE"
}

# The user edits options in the add-on UI and restarts it.
set_option() {
	local filter=$1
	jq -c "$filter" "$OPTIONS_FILE" >"$OPTIONS_FILE.new"
	mv "$OPTIONS_FILE.new" "$OPTIONS_FILE"
	save_options
}

# Release and pre-release versions are told apart by the version string.
ADDON_VERSION=1.7.1
choose_preserve_files
[ "$IS_RELEASE_BUILD" = "true" ] && [ "$OWN_PRESERVE_FILE" = "$PRESERVE_FILE" ]
for version in 1.7.1-beta.4 1.7.1-alpha.2 "" null; do
	ADDON_VERSION=$version
	choose_preserve_files
	[ "$IS_RELEASE_BUILD" = "false" ] && [ "$OWN_PRESERVE_FILE" = "$PRERELEASE_PRESERVE_FILE" ]
done

# A tester who never ran production keeps settings across beta/alpha installs.
boot 1.7.1-beta.4
set_option '.hughes_enabled = true | .mqtt_pass = "beta-pass"'
[ ! -f "$PRESERVE_FILE" ]
boot 1.7.1-alpha.2
assert_json "$OPTIONS_FILE" '.hughes_enabled' 'true'
assert_json "$OPTIONS_FILE" '.mqtt_pass' '"beta-pass"'

# A first production install after testing adopts the tester's settings.
boot 1.7.1
assert_json "$OPTIONS_FILE" '.mqtt_pass' '"beta-pass"'
set_option '.mqtt_pass = "prod-pass" | .hughes_enabled = false'
assert_json "$PRESERVE_FILE" '.' '{"hughes_enabled":false,"mqtt_pass":"prod-pass","debug_logging":false}'

# Once production has saved, every beta and alpha install copies production,
# even after a pre-release build saved different values more recently.
boot 1.7.1-alpha.2
assert_json "$OPTIONS_FILE" '.mqtt_pass' '"prod-pass"'
set_option '.mqtt_pass = "alpha-pass" | .debug_logging = true'
boot 1.7.1-beta.4
assert_json "$OPTIONS_FILE" '.mqtt_pass' '"prod-pass"'
assert_json "$OPTIONS_FILE" '.debug_logging' 'false'
assert_json "$PRESERVE_FILE" '.mqtt_pass' '"prod-pass"'

# An existing install is not a fresh install and keeps its own settings.
boot 1.7.1-alpha.2 existing
assert_json "$OPTIONS_FILE" '.mqtt_pass' '"alpha-pass"'

# Production saves exactly its own options, dropping keys it does not have.
jq -c '. + {"beta_only": true}' "$PRESERVE_FILE" >"$PRESERVE_FILE.new"
mv "$PRESERVE_FILE.new" "$PRESERVE_FILE"
boot 1.7.1 existing
save_options
assert_json "$PRESERVE_FILE" 'has("beta_only")' 'false'

echo "preserved options tests passed"
