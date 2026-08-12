#!/bin/bash
# ~/github/system-config/vpn/install.sh
#
# Install the VPN tooling from this directory to where it runs.
# Idempotent - safe to re-run after editing anything here.
#
# It does NOT: start or restart any service, enable any timer, arm the kill
# switch, or touch a running process. Those are deliberate acts and they are
# printed at the end for you to run when you decide to.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo ./install.sh"; exit 2; }

U=zenko
H=/home/$U

ok() { printf "  %-46s %s\n" "$1" "$2"; }

echo "== root-owned =="
install -o root -g root -m 0755 nordvpn-select      /usr/local/sbin/nordvpn-select      && ok /usr/local/sbin/nordvpn-select ok
install -o root -g root -m 0755 nordvpn-repin       /usr/local/bin/nordvpn-repin        && ok /usr/local/bin/nordvpn-repin ok
install -o root -g root -m 0755 nordvpn-api-refresh /usr/local/sbin/nordvpn-api-refresh && ok /usr/local/sbin/nordvpn-api-refresh ok
install -o root -g root -m 0755 nordvpn-killswitch  /usr/local/sbin/nordvpn-killswitch  && ok /usr/local/sbin/nordvpn-killswitch ok
install -o root -g root -m 0755 vpn-state           /usr/local/bin/vpn-state            && ok /usr/local/bin/vpn-state ok

install -d -o root -g root -m 0755 /etc/nftables.d
install -o root -g root -m 0644 nordvpn-killswitch.nft /etc/nftables.d/nordvpn-killswitch.nft && ok /etc/nftables.d/nordvpn-killswitch.nft ok

install -o root -g root -m 0644 nordvpn-select-poll.service /etc/systemd/system/ && ok /etc/systemd/system/nordvpn-select-poll.service ok
install -o root -g root -m 0644 nordvpn-select-poll.timer   /etc/systemd/system/ && ok /etc/systemd/system/nordvpn-select-poll.timer ok

# The dispatcher hook is NOT installed by default. It heals the tunnel on any
# NM 'up' event, which silently relocates the exit country - a decision that
# was never settled. Install it by hand if you want it.
ok "90-nordvpn-verify" "NOT installed by design - see README"

echo
echo "== user-owned =="
install -o $U -g $U -m 0755 nordvpn-tray         $H/.local/bin/nordvpn-tray          && ok $H/.local/bin/nordvpn-tray ok
install -o $U -g $U -m 0644 nordvpn-tray.desktop $H/.config/autostart/nordvpn-tray.desktop && ok $H/.config/autostart/nordvpn-tray.desktop ok

echo
echo "== sudoers =="
if [ -f /etc/sudoers.d/nordvpn-select ]; then
  if grep -q nordvpn-killswitch /etc/sudoers.d/nordvpn-select; then
    ok "/etc/sudoers.d/nordvpn-select" "already grants killswitch"
  else
    ok "/etc/sudoers.d/nordvpn-select" "NEEDS the killswitch line - see below"
  fi
else
  ok "/etc/sudoers.d/nordvpn-select" "ABSENT - the tray cannot call anything"
fi

cat <<'EOF'

== not done, on purpose ==

  The tray must be restarted to pick up a new binary:
      pkill -f nordvpn-tray
      setsid ~/.local/bin/nordvpn-tray >/dev/null 2>&1 &

  The kill switch is not armed. Check, then load:
      sudo nft -c -f /etc/nftables.d/nordvpn-killswitch.nft
      sudo /usr/local/sbin/nordvpn-killswitch arm
      sudo nft list table inet killswitch

  The hourly poll timer is not enabled:
      sudo systemctl daemon-reload
      sudo systemctl enable --now nordvpn-select-poll.timer

  The tray needs sudo for the kill switch. If the line is missing:
      printf 'zenko ALL=(root) NOPASSWD: /usr/local/sbin/nordvpn-select\nzenko ALL=(root) NOPASSWD: /usr/local/sbin/nordvpn-killswitch\n' \
        | sudo tee /etc/sudoers.d/nordvpn-select >/dev/null
      sudo chmod 0440 /etc/sudoers.d/nordvpn-select
      sudo visudo -c

  Nothing here persists the kill switch across a reboot yet. That is
  deliberate - a reboot is a guaranteed way out while you are still
  deciding whether you like how it behaves.
EOF
