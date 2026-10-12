# Use an iPhone over Tailscale (no cable, no Mac)

Status: works on iOS 27.0.1 (iPhone 15 Pro Max), measured 2026-10-10. Receipts: `receipts/2026-10-10-iphone-over-tailnet.md`.

You pair the phone once over USB. After that, any Linux host on your tailnet can install apps, launch them, take
screenshots and read the syslog, with the phone on any network.

## Why this works (and what does not)

The phone offers two control doors:

| Door | Port | From a tailnet address |
|---|---|---|
| lockdownd | 62078 | Resets the connection before it replies, unless the sender is on the phone's own subnet. Measured from three hosts. |
| RemotePairing (`_remotepairing._tcp`) | 49152 in our runs | Answers. The pairing record decides who may use it, not the sender's address. |

So the route is: pair-verify against the RemotePairing port with the record from the USB pairing, open the CoreDevice
tunnel, then use the tunnel's RSD address for every command. mDNS does not cross Tailscale, so you give the
phone's tailnet address and the tool scans ports 49152 to 49167.

## One-time setup (phone on USB, 2 minutes)

1. Install pymobiledevice3 11.23 or newer with **Python 3.13 or newer** (the TCP tunnel needs TLS-PSK ciphers, which
   distribution Python 3.14 has; the `uv` standalone builds do not). Example: `python3.14 -m venv ~/pmd3 && ~/pmd3/bin/pip install pymobiledevice3`.
2. Phone: unlock, plug in, tap Trust once if asked. Developer Mode on. Tailscale app on, signed in to your tailnet.
3. `~/pmd3/bin/python tools/tailnet-tunnel.py pair`
   This runs `lockdown remotepairing --pair` (no tap on the phone) and writes
   `~/.local/share/pymobiledevice3/remote_<udid>.plist` with the host identifier pinned, so the file works on any host.
4. Copy that file to the same path on every host that should reach the phone (mode 600). It holds a private key: treat
   it like an SSH key.
5. Find the phone's tailnet address: `tailscale status` (the `iOS` line).

## Use it

```sh
sudo -v                                   # the tunnel needs a TUN device
~/pmd3/bin/python tools/tailnet-tunnel.py 100.x.y.z --hold 600   # prints: RSD fd..::1 65002
~/pmd3/bin/pymobiledevice3 developer dvt screenshot shot.png --rsd fd..::1 65002
~/pmd3/bin/pymobiledevice3 apps list --rsd fd..::1 65002
~/pmd3/bin/pymobiledevice3 developer dvt launch com.apple.Preferences --rsd fd..::1 65002
~/pmd3/bin/pymobiledevice3 syslog live --rsd fd..::1 65002
```

For a signed app build: `./device-run.sh --over-tailnet 100.x.y.z path/to/App.ipa` (installs, launches, closes the tunnel).

Add `--console [SECONDS]` (default 20) to watch the app's own output. After the install it launches the app
with `developer dvt launch <bundle id> --stream` and prints stdout and stderr for SECONDS. Then it prints
`running after N s: yes/no` and `fatal text seen: yes/no`, and stops the app. A fatal line in the stream is
a report about the app, not an error of the script. The same flag works on the cable path,
`./device-run.sh --rsd HOST PORT PKG`.

## Travel checklist

1. Keep Wi-Fi on. The phone needs a Wi-Fi connection (any network, any subnet). On cellular only, the RemotePairing port is closed.
2. Keep Tailscale connected on the phone (the VPN toggle on).
3. After any phone restart, unlock it once before you depend on it (expectation, not measured: iOS keeps most services
   closed until the first unlock).
4. If the pairing stops working (for example after a phone reset), pair over USB again with `tailnet-tunnel.py pair`.

## What was measured (iOS 27.0.1, 2026-10-10)

| Phone state | Result from two Linux hosts (neither on the phone's subnet) |
|---|---|
| Cable in, Wi-Fi on | Works. Pair-verify, tunnel, info, apps, launch, screenshot, syslog. |
| Cable out, Wi-Fi on, other subnet than the phone | Works. Same port (49152) before and after a Wi-Fi toggle. |
| Cable out, Wi-Fi off, cellular + Tailscale | Fails. Port 49152 to 49167 refused; a scan of ports 1-1024 and 49152-65535 found one unrelated open port that does not answer RemotePairing. The phone itself answers `tailscale ping`. |
| Screen locked (duration not recorded) | Works. Screenshot shows the passcode screen; apps launch behind it. |
| Screen off and locked, idle for hours (2026-10-11) | The tunnel, pair-verify and a screenshot work. The screenshot is all black. Launching an app fails on both routes: `dvt launch` reports "Failed to launch process with bundle identifier" and `core-device launch-application` reports code 10002. We did not test whether waking the phone fixes it. |
| Screen locked, 30 minutes | Not measured as such. The 2026-10-11 row above covers a longer idle and shows a different result. |
| `device-run.sh --over-tailnet App.ipa` | Works. Installs and launches a signed ipa, closes the tunnel on exit. |

Receipts and raw output: `receipts/2026-10-10-iphone-over-tailnet.md`.

## LLDB over the tunnel

Measured (cable out, Wi-Fi on): the tunnel carries `dvt launch --suspended`, `developer debugserver start-server`, and lldb's
`process connect` and `process attach`. The process stops at `_dyld_start`, and `breakpoint set -n main` resolves to your app
when the local binary matches the installed build.

**Sysroot (needed).** Without the device's on-disk system libraries, lldb reads them from process memory across the tunnel
and had not reached `main` after 150 seconds. With the sysroot in
`~/.cache/omarchy-apple-dev/DeviceSupport/<version> (<build>)/Symbols` and `platform select remote-ios --sysroot <that dir>`,
the "read from process memory" warning is gone and `continue` runs the app. Build the sysroot once per iOS build, with no
phone traffic, from Apple's public IPSW cache (the same cache `sdk-free/setup.sh --ipsw` downloads; 6.7 GB for 24A446):

```sh
ipsw dyld info dyld_shared_cache_arm64e --dylibs | grep -o '/[^ ]*$' | grep -E '^/usr/lib/(swift/|libobjc)' > dylibs.txt
while read -r p; do mkdir -p "Symbols$(dirname "$p")"; \
  ipsw dyld extract dyld_shared_cache_arm64e "$(basename "$p")" --slide -o "Symbols$(dirname "$p")"; done < dylibs.txt
```

That gave 80 libraries, 70 MB. Copy only that folder to the host that runs lldb, then delete the cache.

**A stop at a breakpoint over the tunnel works (2026-10-11).** With the phone's screen on and the cable out, lldb
stopped at `breakpoint set -n main` in our own app and printed the frame and registers:

```
Process 259 stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: 0x0000000102d78444 SwiftUIWide1`main
(lldb) register read pc sp x0 x1
      pc = 0x0000000102d78444  SwiftUIWide1`main
(lldb) breakpoint list
1: name = 'main', locations = 1, resolved = 1, hit count = 1
```

Three things were in place when the stop appeared.

1. The sysroot above.
2. `target.module[0].SetPlatformFileSpec(<remote path>)`, the same step `device-run.sh` uses in `lldb_session`. Read the
   remote path from `pymobiledevice3 apps list --rsd ADDR PORT`. Without it lldb replaces the local binary with the remote
   one.
3. A 220 second wait for the stop. Retry 1 used a 40 second wait. It inserted the breakpoint and ended while lldb was
   still handling dyld image-load stops, before `main`. Its packet log shows debugserver answered
   `{"results":["OK","OK"]}` to the batch insert that held `Z0,104ad0444,4`, the address of `main`.

Of these three, only the wait was varied between the two retries (40 s ended before `main`, 220 s reached it). Both
retries had the sysroot and the file spec. We did not test the sysroot or the file spec alone. The whole run, from the
first probe to the end, took 3 min 53 s. The run order was: launch suspended, forward debugserver,
`platform select remote-ios --sysroot`, `target create`, `SetPlatformFileSpec`, `process connect`,
`process attach`, `breakpoint set -n main`, `continue`, wait for the stop. A stop at a breakpoint on a screen-off phone
is untested, because launch fails there (see the table above).

Always end a debug session by killing the app (`developer dvt pkill --bundle BUNDLE_ID --rsd ADDR PORT`) so the phone is not
left with a suspended app.

## What each failure looks like

| You see | Meaning | Fix |
|---|---|---|
| `ConnectionRefusedError` on every port 49152-49167 | The phone has no Wi-Fi up (cellular only), or Tailscale is off | Turn Wi-Fi on; check `tailscale status` shows the phone online |
| `tailscale ping` times out | Tailscale is off on the phone, or the phone is asleep with no network | Open the Tailscale app |
| `ConnectionTerminatedError` right after connect | The pairing record does not match this host | Re-copy the record made by `tailnet-tunnel.py pair` (it pins the host identifier) |
| `NO_CIPHERS_AVAILABLE` | Python without TLS-PSK ciphers (uv standalone builds) | Use distribution Python 3.13 or newer |
| `QuicProtocolNotSupportedError` | Python older than 3.13 | Use Python 3.13 or newer |
| `This command requires root` | The tunnel needs a TUN device | Run through `sudo` (the tool does it with `sudo -n`) |

## Limits

- iOS 27 only. The pairing record and the open RemotePairing port are the iOS 27 flow.
- The phone needs a Wi-Fi connection and the Tailscale VPN running.
- The host key file is a credential. Anyone with it and a route to the phone can drive it.
- A screenshot shows whatever is on the screen. If you use the phone while a test runs, the picture can show private
  messages or other apps. Test while nobody uses the phone and the lock screen is showing. The table above shows that a
  phone with its screen off for hours refuses launches, so wake it to the lock screen first. Treat each screenshot as
  private and delete it after you read it. We found this when two test screenshots showed a chat and the app library
  instead of our app.

## Plan B: a laptop you charge the phone from

If Tailscale on the phone is not reliable, plug the phone into one Linux laptop on your tailnet whenever you charge it.
Agents then use `ssh <laptop>` and the normal USB commands. Needs: sshd enabled, `pymobiledevice3` and `usbmuxd`
installed, the agent host's public key in `~/.ssh/authorized_keys`, and a tap on Trust once per phone.
