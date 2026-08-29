# VPN Trigger Manager

**VPN Trigger Manager** is a rootless iOS jailbreak tweak that manages temporary VPN connections used during incoming caller lookups.

Caller-ID tweaks such as **PhoneHub**, **Yellow Pages**, and similar search tools may need to contact services such as **Truecaller** or another provider that is unavailable or restricted on the current network. A Packet Tunnel VPN such as **Shadowrocket** can connect automatically when the lookup begins, but it may remain connected after the call. VPN Trigger Manager watches that flow and disconnects only the new Packet Tunnel VPN that started during the incoming call.

Existing VPN connections are preserved. Personal VPN is also preserved by default.

> Beta software: test the behavior with your own VPN configuration before relying on it.

## What it does

1. Watches incoming calls locally through CallKit.
2. Records the active VPN tunnels and Packet Tunnel configurations when the call begins.
3. Detects a new tunnel that appears while the call is active.
4. Waits briefly after the call ends.
5. Stops only the Packet Tunnel VPN that became active during that call.
6. Verifies the disconnection and can retry once if required.

The tweak does not provide a VPN server, proxy node, subscription, caller database, or caller-ID service. It only manages the VPN connection on the device.

## Example use case

A typical setup uses:

- A caller-search tweak such as **PhoneHub** or **Yellow Pages**.
- A lookup provider such as **Truecaller** or another service that may be restricted on the current network.
- **Shadowrocket** or another compatible Packet Tunnel VPN.
- VPN Trigger Manager to disconnect the temporary VPN after the call.

Flow:

1. An incoming call begins.
2. The caller-search tweak requests information from its configured provider.
3. Shadowrocket connects through an On Demand rule for the provider's domain.
4. The lookup completes while the call is active.
5. When the call ends, VPN Trigger Manager disconnects only the VPN that started during the call.

Product names belong to their respective owners. This project is not affiliated with PhoneHub, Yellow Pages, Truecaller, or Shadowrocket.

## Installation

### Sileo or Zebra

1. Open the [latest release](https://github.com/AAZ-25/VPN-Trigger-Manager/releases/latest).
2. Download `VPN-Trigger-Manager-rootless.deb`.
3. Open or share the DEB with **Sileo**, **Zebra**, or another compatible package manager.
4. Install the package and allow the package manager to install the required dependencies.
5. Respring the device.
6. Open:
   `Settings → VPN Trigger Manager`
7. Confirm that **Enable Tweak** is on.

A repository source is not required when installing the DEB directly from GitHub Releases.

## Shadowrocket setup

Menu names may vary slightly between Shadowrocket versions.

1. Add and test a working Shadowrocket node.
2. Allow Shadowrocket to install its iOS VPN configuration when requested.
3. Keep **Always On** disabled.
4. Open:
   `Shadowrocket → Settings → On Demand / Connect On Demand`
5. Add a **Connect** rule for the domain used by the caller-lookup provider.
6. Enable **Connect On Demand**.
7. Leave Shadowrocket disconnected before testing.
8. Make an incoming test call and confirm that the caller-search request starts Shadowrocket automatically.
9. End the call and confirm that VPN Trigger Manager disconnects the newly started VPN.

The domain must match the service actually contacted by the caller-search tweak. VPN Trigger Manager does not choose or inspect that domain.

On Demand domain rules are handled by iOS DNS behavior. A cached DNS result may occasionally prevent a domain rule from triggering immediately.

## Recommended tweak settings

For a Shadowrocket On Demand setup:

- **Enable Tweak** — On
- **Stop Personal VPN** — Off
- **Disable Connect On Demand** — Off initially
- **Verify Disconnection** — On
- **Retry Once If Needed** — On
- **Diagnostic Logging** — Off unless troubleshooting

If Shadowrocket reconnects immediately after the tweak stops it, enable **Disable Connect On Demand**. The tweak temporarily disables On Demand for the target connection, sends the stop request, and then restores the setting.

## Simulated-call test

The Settings page includes a 15-second test:

1. Open `Settings → VPN Trigger Manager`.
2. Keep **Auto Start VPN During Test** enabled if you want the tweak to start an available disconnected Packet Tunnel automatically.
3. Tap **Run Simulated Call Test**.
4. Wait for the test to finish.
5. Tap **Show Last Test Result**.

The test does not place a real call. It runs the same detection, stop, verification, and optional retry flow.

## Troubleshooting

- Confirm that the VPN appears in iOS as a Packet Tunnel configuration.
- Confirm that Shadowrocket can connect normally before testing On Demand.
- Confirm that the caller-search tweak is making a request to the domain used in the On Demand rule.
- Keep **Always On** disabled when testing a domain-based On Demand rule.
- Turn on **Diagnostic Logging** only while troubleshooting.
- Use **Respring** after installation or if SpringBoard did not load the tweak.
- If the VPN remains active, keep **Verify Disconnection** and **Retry Once If Needed** enabled.
- If the VPN reconnects immediately, enable **Disable Connect On Demand**.

Diagnostic logging is off by default, rotates after 1 MB, and records sanitized technical states rather than caller numbers, contacts, VPN server addresses, or VPN configuration names.

## Privacy

VPN Trigger Manager:

- Processes call state and VPN state locally on the device.
- Does not read or upload the caller's phone number.
- Does not upload contacts or call history.
- Does not include analytics, advertising, or a remote service.
- Does not store VPN credentials or subscription details.

Any caller-search provider used by PhoneHub, Yellow Pages, or another tool has its own privacy policy and behavior.

## Compatibility

- Rootless jailbreak
- iOS 15 or newer
- `arm64` and `arm64e`
- PreferenceLoader-compatible Settings page
- Packet Tunnel VPN configurations such as Shadowrocket

## Build from source

Install [Theos](https://theos.dev/docs/installation), then run:

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

The DEB is written to `packages/`.

## Package identity

- Package: `com.aaz.vpntriggermanager`
- Product: **VPN Trigger Manager**
- Author: **AAZ**

Copyright © 2026 AAZ. All rights reserved.
