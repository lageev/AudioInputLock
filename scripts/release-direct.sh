#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FocusMic"
PROJECT_NAME="FocusMic.xcodeproj"
SCHEME="FocusMic"
CONFIGURATION="Release"
DIRECT_TARGET_NAME="FocusMic"
INFO_PLIST="SupportFiles/FocusMic-Info.plist"
APPCAST_PATH="landing/appcast.xml"
MINIMUM_SYSTEM_VERSION="15.0"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION=""
BUILD_NUMBER=""
REPO=""
SHIP=0
CREATE_GITHUB_RELEASE=0
PUBLISH=0
ALLOW_DIRTY=0
OVERWRITE=0
NOTARIZE=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/release-direct.sh <version> <build> [options]

Examples:
  scripts/release-direct.sh 0.0.2 6
  scripts/release-direct.sh 0.0.2 6 --notarize
  scripts/release-direct.sh 0.0.2 6 --ship --notarize
  scripts/release-direct.sh 0.0.2 6 --ship --publish --notarize

Options:
  --ship                    Commit release metadata, tag, push, and create a GitHub draft release.
  --publish                 Create a public GitHub release instead of a draft. Implies --ship.
  --github-draft            Create a GitHub draft release without committing/tagging.
  --repo owner/name          GitHub repository. Defaults to gh repo view or origin.
  --notarize                Submit the exported app to Apple notarization before zipping for Sparkle.
  --allow-dirty             Allow an already dirty worktree. Not allowed with --ship.
  --overwrite               Replace build/releases/v<version> if it already exists.
  -h, --help                Show this help.

Environment:
  TEAM_ID                   Optional Apple team ID for xcodebuild export.
  NOTARYTOOL_PROFILE        Keychain profile used by xcrun notarytool when --notarize is set.
  DEVELOPER_DIR             Optional Xcode developer directory override.
  SPARKLE_BIN               Optional directory containing Sparkle sign_update.
  EXPORT_METHOD             xcodebuild export method. Defaults to developer-id.
  ARCHIVE_CODE_SIGN_IDENTITY
                            Optional archive signing identity override.
USAGE
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

info() {
  printf '==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

select_xcode() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  local active_developer_dir
  active_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$active_developer_dir" == "/Library/Developer/CommandLineTools"* ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    info "Using ${DEVELOPER_DIR}"
  fi
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  [[ $# -ge 2 ]] || fail "version and build number are required"
  VERSION="$1"
  BUILD_NUMBER="$2"
  shift 2

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ship)
        SHIP=1
        CREATE_GITHUB_RELEASE=1
        ;;
      --publish)
        SHIP=1
        CREATE_GITHUB_RELEASE=1
        PUBLISH=1
        ;;
      --github-draft)
        CREATE_GITHUB_RELEASE=1
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || fail "--repo requires owner/name"
        REPO="$1"
        ;;
      --notarize)
        NOTARIZE=1
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        ;;
      --overwrite)
        OVERWRITE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
    shift
  done
}

validate_args() {
  [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)?$ ]] || fail "version should look like 1.2.3"
  [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "build number must be an integer"

  if [[ "$SHIP" -eq 1 && "$ALLOW_DIRTY" -eq 1 ]]; then
    fail "--ship requires a clean worktree; remove --allow-dirty"
  fi

  if [[ "$NOTARIZE" -eq 1 && -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    fail "--notarize requires NOTARYTOOL_PROFILE"
  fi
}

require_tools() {
  require_command git
  require_command gh
  require_command ruby
  require_command xcodebuild
  require_command xcrun
  require_command ditto
  require_command /usr/libexec/PlistBuddy
}

require_clean_worktree() {
  if [[ "$ALLOW_DIRTY" -eq 0 ]] && [[ -n "$(git status --porcelain)" ]]; then
    fail "worktree is dirty. Commit/stash first, or use --allow-dirty for prepare-only runs"
  fi
}

find_sparkle_tool() {
  local tool="$1"
  local candidate

  if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/${tool}" ]]; then
    printf '%s\n' "${SPARKLE_BIN}/${tool}"
    return
  fi

  for base in "$HOME/Library/Developer/Xcode/DerivedData" "/private/tmp/FocusMicDerivedData"; do
    [[ -d "$base" ]] || continue
    candidate="$(find "$base" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool}" -type f -perm +111 2>/dev/null | sort | tail -n 1 || true)"
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  fail "could not find Sparkle ${tool}. Build once with SwiftPM resolved, or set SPARKLE_BIN"
}

detect_repo() {
  if [[ -n "$REPO" ]]; then
    return
  fi

  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  if [[ -n "$REPO" ]]; then
    return
  fi

  REPO="$(ruby -e '
remote = `git config --get remote.origin.url`.strip
if remote =~ %r{\Agit@github.com:([^/]+/[^.]+)(?:\.git)?\z}
  puts $1
elsif remote =~ %r{\Ahttps://github.com/([^/]+/[^.]+)(?:\.git)?\z}
  puts $1
end
')"

  [[ -n "$REPO" ]] || fail "could not detect GitHub repo; pass --repo owner/name"
}

validate_sparkle_config() {
  local public_key
  public_key="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || true)"
  [[ -n "$public_key" ]] || fail "SUPublicEDKey is missing in ${INFO_PLIST}"
  [[ "$public_key" != "REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY" ]] || fail "SUPublicEDKey still contains placeholder"

  local feed_url
  feed_url="$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true)"
  [[ -n "$feed_url" ]] || fail "SUFeedURL is missing in ${INFO_PLIST}"
}

validate_notary_profile() {
  [[ "$NOTARIZE" -eq 1 ]] || return

  info "Checking notarytool profile ${NOTARYTOOL_PROFILE}"
  xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" >/dev/null
}

prepare_output_dir() {
  RELEASE_TAG="v${VERSION}"
  RELEASE_DIR="$PROJECT_ROOT/build/releases/${RELEASE_TAG}"
  ARCHIVE_PATH="$RELEASE_DIR/${APP_NAME}.xcarchive"
  EXPORT_PATH="$RELEASE_DIR/export"
  EXPORT_OPTIONS_PLIST="$RELEASE_DIR/ExportOptions.plist"
  ZIP_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}.zip"
  NOTARY_ZIP_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-notary.zip"
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/$(basename "$ZIP_PATH")"

  if [[ -e "$RELEASE_DIR" ]]; then
    if [[ "$OVERWRITE" -eq 1 ]]; then
      rm -rf "$RELEASE_DIR"
    else
      fail "${RELEASE_DIR} already exists. Use --overwrite to replace it"
    fi
  fi

  mkdir -p "$RELEASE_DIR"
}

write_export_options() {
  cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

  if [[ -n "${TEAM_ID:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM_ID}" "$EXPORT_OPTIONS_PLIST"
  fi
}

update_project_version() {
  ruby - "$PROJECT_NAME/project.pbxproj" "$VERSION" "$BUILD_NUMBER" "$DIRECT_TARGET_NAME" <<'RUBY'
path, version, build, target_name = ARGV
text = File.read(path)

target_match = text.to_enum(:scan, /([A-Z0-9]{24}) \/\* #{Regexp.escape(target_name)} \*\/ = \{\n(.*?)\n\t\t\};/m)
  .map { Regexp.last_match }
  .find { |match| match[2].include?("isa = PBXNativeTarget;") }
abort "target not found: #{target_name}" unless target_match

config_list_id = target_match[2][/buildConfigurationList = ([A-Z0-9]{24}) /, 1]
abort "build configuration list not found for #{target_name}" unless config_list_id

list_match = text.match(/^\t\t#{Regexp.escape(config_list_id)} \/\* .*? \*\/ = \{\n(.*?)\n\t\t\};/m)
abort "configuration list block not found: #{config_list_id}" unless list_match

config_ids = list_match[1].scan(/([A-Z0-9]{24}) \/\* (Debug|Release) \*\//).map(&:first)
abort "no Debug/Release build configurations found for #{target_name}" if config_ids.empty?

def replace_setting(settings, key, value)
  changed = false
  settings = settings.gsub(/^(\s*)#{Regexp.escape(key)} = .*?;$/) do
    changed = true
    "#{$1}#{key} = #{value};"
  end
  unless changed
    indent = settings[/^(\s*)[A-Z0-9_"]+/, 1] || "\t\t\t\t"
    settings = "#{settings}\n#{indent}#{key} = #{value};"
  end
  settings
end

changed_blocks = 0
config_ids.each do |config_id|
  replaced = false
  text = text.gsub(/(\t\t#{Regexp.escape(config_id)} \/\* .*? \*\/ = \{\n.*?\t\t\tbuildSettings = \{\n)(.*?)(\n\t\t\t\};\n\t\t\tname = .*?;\n\t\t\};)/m) do
    replaced = true
    settings = replace_setting($2, "CURRENT_PROJECT_VERSION", build)
    settings = replace_setting(settings, "MARKETING_VERSION", version)
    "#{$1}#{settings}#{$3}"
  end
  abort "build configuration block not found: #{config_id}" unless replaced
  changed_blocks += 1
end

File.write(path, text)
puts "updated #{target_name} MARKETING_VERSION=#{version}, CURRENT_PROJECT_VERSION=#{build} in #{changed_blocks} configurations"
RUBY
}

archive_and_export() {
  write_export_options

  info "Archiving ${APP_NAME} ${VERSION} (${BUILD_NUMBER})"
  local archive_args
  archive_args=(
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH"
  )

  if [[ -n "$ARCHIVE_CODE_SIGN_IDENTITY" ]]; then
    archive_args+=(CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY")
  fi

  archive_args+=(archive)
  xcodebuild "${archive_args[@]}"

  info "Exporting archive"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

  APP_PATH="$EXPORT_PATH/${APP_NAME}.app"
  [[ -d "$APP_PATH" ]] || fail "exported app not found: ${APP_PATH}"

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

notarize_app() {
  [[ "$NOTARIZE" -eq 1 ]] || return

  info "Submitting app for notarization"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"
  xcrun notarytool submit "$NOTARY_ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait

  info "Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
}

zip_and_sign_update() {
  info "Creating Sparkle zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  info "Signing zip with Sparkle"
  SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP_PATH")"
  printf '%s\n' "$SIGN_OUTPUT"

  ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | ruby -ne 'if $_ =~ /sparkle:edSignature="([^"]+)"/; puts $1; exit; end')"
  ZIP_LENGTH="$(printf '%s\n' "$SIGN_OUTPUT" | ruby -ne 'if $_ =~ /length="([0-9]+)"/; puts $1; exit; end')"

  [[ -n "$ED_SIGNATURE" ]] || fail "could not parse sparkle:edSignature from sign_update output"
  [[ -n "$ZIP_LENGTH" ]] || fail "could not parse length from sign_update output"
}

update_appcast() {
  local pub_date
  pub_date="$(ruby -r time -e 'puts Time.now.rfc2822')"

  ruby - "$APPCAST_PATH" "$VERSION" "$BUILD_NUMBER" "$pub_date" "$MINIMUM_SYSTEM_VERSION" "$DOWNLOAD_URL" "$ED_SIGNATURE" "$ZIP_LENGTH" <<'RUBY'
require "cgi"

path, version, build, pub_date, minimum_system_version, download_url, signature, length = ARGV
xml = File.read(path)
visible_xml = xml.gsub(/<!--.*?-->/m, "")

if visible_xml.include?("<sparkle:version>#{build}</sparkle:version>")
  abort "appcast already contains sparkle:version #{build}"
end

item = <<~XML
    <item>
      <title>#{CGI.escapeHTML(version)}</title>
      <pubDate>#{CGI.escapeHTML(pub_date)}</pubDate>
      <sparkle:version>#{CGI.escapeHTML(build)}</sparkle:version>
      <sparkle:shortVersionString>#{CGI.escapeHTML(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>#{CGI.escapeHTML(minimum_system_version)}</sparkle:minimumSystemVersion>
      <enclosure
        url="#{CGI.escapeHTML(download_url)}"
        sparkle:edSignature="#{CGI.escapeHTML(signature)}"
        length="#{CGI.escapeHTML(length)}"
        type="application/octet-stream"/>
    </item>
XML

unless xml.sub!(/(\s*<language>zh-CN<\/language>\n)/, "\\1#{item}")
  abort "could not find appcast insertion point after <language>zh-CN</language>"
end

File.write(path, xml)
puts "updated #{path} with #{version} (#{build})"
RUBY

  ruby -r rexml/document -e 'REXML::Document.new(File.read(ARGV.fetch(0)))' "$APPCAST_PATH"
}

ship_release() {
  [[ "$SHIP" -eq 1 ]] || return

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$branch" != "HEAD" ]] || fail "--ship cannot run on a detached HEAD"

  if git rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
    fail "tag already exists locally: ${RELEASE_TAG}"
  fi

  info "Committing release metadata"
  git add "$PROJECT_NAME/project.pbxproj" "$APPCAST_PATH"
  git commit -m "Release ${RELEASE_TAG}"

  info "Tagging ${RELEASE_TAG}"
  git tag -a "$RELEASE_TAG" -m "${APP_NAME} ${VERSION}"

  info "Pushing ${branch} and ${RELEASE_TAG}"
  git push origin "$branch"
  git push origin "$RELEASE_TAG"
}

create_github_release() {
  [[ "$CREATE_GITHUB_RELEASE" -eq 1 ]] || return

  if [[ "$SHIP" -eq 0 ]]; then
    warn "creating a GitHub release without committing/tagging; make sure ${RELEASE_TAG} points to the release commit"
  fi

  local release_args
  release_args=(release create "$RELEASE_TAG" "$ZIP_PATH" --repo "$REPO" --title "${APP_NAME} ${VERSION}" --notes "${APP_NAME} ${VERSION}")

  if [[ "$PUBLISH" -eq 0 ]]; then
    release_args+=(--draft)
  else
    release_args+=(--latest)
  fi

  info "Creating GitHub release ${RELEASE_TAG}"
  gh "${release_args[@]}"
}

print_summary() {
  cat <<SUMMARY

Release assets prepared:
  App:      ${APP_PATH}
  Zip:      ${ZIP_PATH}
  Appcast:  ${APPCAST_PATH}
  URL:      ${DOWNLOAD_URL}

Sparkle enclosure:
  sparkle:edSignature="${ED_SIGNATURE}"
  length="${ZIP_LENGTH}"
SUMMARY

  if [[ "$CREATE_GITHUB_RELEASE" -eq 0 ]]; then
    cat <<NEXT

Next steps:
  1. Review the diff, especially ${APPCAST_PATH}.
  2. Upload ${ZIP_PATH} to GitHub Release ${RELEASE_TAG}, or rerun with --ship.
  3. Confirm the updated appcast is available from the configured SUFeedURL.
NEXT
  elif [[ "$PUBLISH" -eq 0 ]]; then
    cat <<NEXT

GitHub draft release created. Review it on GitHub, then publish when ready.
NEXT
  else
    cat <<NEXT

GitHub release published. Make sure the updated appcast is available from the configured SUFeedURL.
NEXT
  fi
}

main() {
  parse_args "$@"
  validate_args
  select_xcode
  require_tools
  require_clean_worktree
  detect_repo
  validate_sparkle_config
  validate_notary_profile

  SIGN_UPDATE="$(find_sparkle_tool sign_update)"
  prepare_output_dir

  info "Repository: ${REPO}"
  info "Sparkle sign_update: ${SIGN_UPDATE}"
  update_project_version
  archive_and_export
  notarize_app
  zip_and_sign_update
  update_appcast
  ship_release
  create_github_release
  print_summary
}

main "$@"
