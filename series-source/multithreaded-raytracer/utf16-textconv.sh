#!/bin/sh
# Emit UTF-8 text for a source file that may be UTF-16 encoded.
# Used as a git textconv driver so UTF-16 sources diff as text, not binary.
f="$1"
bom=$(head -c 2 "$f" | od -An -tx1 | tr -d ' \n')
case "$bom" in
  fffe) iconv -f UTF-16LE -t UTF-8 "$f" ;;
  feff) iconv -f UTF-16BE -t UTF-8 "$f" ;;
  *)    cat "$f" ;;
esac
