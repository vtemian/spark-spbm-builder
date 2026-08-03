#!/bin/sh
# debsign shells out to gpg, which tries to read the passphrase from /dev/tty.
# CI has no tty, so signing dies with "cannot open '/dev/tty'". This shim feeds
# the passphrase from the environment instead. Same approach gitfs-builder uses.
#
# GPG_PASSPHRASE comes from a GitHub secret and is never written to disk.
exec gpg --batch --yes --pinentry-mode loopback \
     --passphrase "${GPG_PASSPHRASE:-}" "$@"
