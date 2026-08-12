# system-config

Machine configuration that would otherwise exist only as installed files with
no source, no history, and a lifespan of one reboot.

Everything here was previously written to `/tmp`, installed, and then existed
in exactly one place: the running system. Modifying or reinstalling any of it
meant rewriting it from scratch.

## vpn/

A NordVPN WireGuard setup managed through NetworkManager rather than the
official client, whose suspend/resume handling desynced the kernel interface
from the daemon's idea of it and could only be recovered by rebooting.

```
nordvpn-select          resolve a live, lightly-loaded server in a US state and
                        swap the WireGuard peer IN PLACE. The interface never
                        goes down, so NM's policy rules are never torn down, so
                        nothing leaves in clear text mid-switch.
                        -> /usr/local/sbin/

nordvpn-repin           edit the netplan source correctly. Three coordinated
                        edits, one of which embeds the peer's public key in a
                        passthrough key NAME. A sed version silently matched
                        nothing against the real file.
                        -> /usr/local/bin/

nordvpn-killswitch      arm | disarm | status for the nftables kill switch.
                        Also swaps DNS on disarm, because the configured
                        resolvers are NordVPN's and unreachable outside the
                        tunnel.
                        -> /usr/local/sbin/

nordvpn-killswitch.nft  the ruleset. policy drop on output and forward; only
                        loopback, the tunnel, LAN, the WireGuard handshake, the
                        cached API addresses, and DHCP get out.
                        -> /etc/nftables.d/

nordvpn-api-refresh     caches the API's addresses into the nft set and
                        /etc/hosts WHILE THE TUNNEL IS UP, so recovery from a
                        retired server needs no DNS. Refuses to run when
                        traffic is not routing through the tunnel.
                        -> /usr/local/sbin/

vpn-state               one word describing what the network is ACTUALLY doing,
                        from routing and handshake age rather than from
                        NetworkManager - which reports "activated" for a dead
                        tunnel carrying nothing.
                        -> /usr/local/bin/

nordvpn-tray            AppIndicator. Connect by state, Disconnect (kill switch
                        stays armed), Go Unprotected (disarmed, clear text).
                        -> ~/.local/bin/

nordvpn-tray.desktop    autostart entry -> ~/.config/autostart/

nordvpn-select-poll.*   hourly heal + rebalance. Heals unconditionally on a
                        dead or delisted server; only rebalances when the
                        current server is above 45% AND something is 20 points
                        better.
                        -> /etc/systemd/system/

90-nordvpn-verify       NM dispatcher hook. NOT INSTALLED. It heals on any 'up'
                        event, which silently relocates the exit country - a
                        decision that was never settled.
```

## Install

```
sudo ./vpn/install.sh
```

Idempotent. Copies everything to its real location and then prints what it
deliberately did not do - start, restart, enable, or arm anything. Those are
separate decisions.

## Why the kill switch is policy drop

With `policy accept` plus explicit drops, anything not thought of leaks. With
`policy drop` plus explicit accepts, anything not thought of breaks. Breaking
gets noticed and fixed; leaking does not.

Consequences that are correct behaviour rather than bugs:

- **DNS stops entirely when the tunnel is down.** The resolvers are NordVPN's,
  reachable only inside the tunnel. Everything will look broken.
- **Containers lose network when the tunnel is down.** They egress through
  FORWARD, which is also policy drop.
- **The Pi stays reachable.** `192.168.12.0/24` is explicitly allowed - that
  traffic never leaves the house, so it is not a leak.

## The recovery deadlock

The switch would otherwise block the thing that repairs the tunnel:
`nordvpn-select` heals by asking the API for a live server over 443, and with
the tunnel down both 443 and DNS are dropped - armed exactly when it prevents
the fix, and a retired server is the failure this whole setup exists for.

Solved by caching while healthy rather than opening DNS. `nordvpn-api-refresh`
populates the nft set and `/etc/hosts` while the tunnel is up; when it drops,
both are already current and recovery needs no lookup.

The API sits behind Cloudflare, so those addresses rotate - which is why the
set is refreshed rather than hardcoded - and are shared infrastructure, so the
hole technically permits reaching anything Cloudflare fronts if something
deliberately targets those IPs with another SNI. Targeted abuse, not a passive
leak, and it is the price of being able to recover.

## Nothing persists across a reboot yet

The kill switch is not loaded at boot. Deliberate: a reboot is a guaranteed way
out while the behaviour is still being evaluated.
