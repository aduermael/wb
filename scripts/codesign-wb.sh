wb_sign_binary() {
  path="$1"

  case "${WB_CODESIGN:-auto}" in
    off|0|false|no)
      echo "Skipping code signing for $path"
      return 0
      ;;
  esac

  if ! command -v codesign >/dev/null 2>&1; then
    echo "Missing required command: codesign" >&2
    exit 1
  fi

  identity="${WB_CODESIGN_IDENTITY:--}"
  codesign --force --sign "$identity" --identifier com.aduermael.wb --timestamp=none "$path"
  codesign --verify --strict --verbose=2 "$path"

  if [ "$identity" = "-" ]; then
    echo "Signed $path with ad-hoc identity"
  else
    echo "Signed $path with identity: $identity"
  fi
}
