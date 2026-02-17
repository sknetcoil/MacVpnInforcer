# macOS VPN Enforcer

A robust security tool for macOS that enforces internet access restrictions unless a specific VPN connection is active.

## Overview

This tool ensures that your computer cannot access the internet unless it is connected to a designated VPN. It is designed to run automatically at startup and monitor your connection status constantly.

If the VPN drops, all internet traffic (except to the VPN server itself) is immediately blocked.

## Features

-   **Enterprise-Grade Reliability**: Version 2 uses event-driven monitoring (`scutil`) for instant reaction to network changes (< 1 second).
-   **Secure Bypass**: Password-protected bypass mechanism stored in a secure system directory to prevent tampering.
-   **Fail-Safe Design**: Defaults to blocking traffic if the service is stopped or fails.
-   **Comprehensive Logging**: Detailed activity logs at `/var/log/vpn_enforcer.log`.
-   **Always-On Protection**: Runs as a system daemon and starts automatically on boot.

## Installation

### Prerequisites
-   macOS (tested on recent versions)
-   Root privileges (via `sudo`)
-   The IP address of your VPN server

### Steps
1.  Open Terminal and navigate to this folder.
2.  Run the setup script:
    ```bash
    chmod +x setup.sh
    sudo ./setup.sh
    ```
3.  Follow the prompts to configure your VPN server IP and set a bypass password.

## Usage

### Continuous Protection
Once installed, the tool runs in the background.
-   **VPN Connected**: Internet works normally.
-   **VPN Disconnected**: Internet is blocked immediately.
-   **Logs**: Check `/var/log/vpn_enforcer.log` for activity.

### Emergency Bypass
To temporarily access the internet without the VPN:

1.  Open Terminal.
2.  Run the control command:
    ```bash
    sudo vpn_control.sh
    ```
3.  Enter the bypass password.
4.  You will get **5 minutes** of internet access.

## Uninstallation

To completely remove the tool and restore default network settings, run the uninstaller script:

```bash
chmod +x uninstall.sh
sudo ./uninstall.sh
```

This will remove all components, including logs and configuration files.

## Technical Details

-   **Backend**: `vpn_enforcer.sh` monitors `State:/Network/Global/IPv4` changes using `scutil`.
-   **Security**: Bypass flag stored in `/var/run/vpnenforcer` (root-only access).
-   **Firewall**: Uses `pfctl` (Packet Filter) to manage rules.


## Disclaimer
This tool modifies your system's firewall rules. Use at your own risk. Ensure you have the correct VPN server IP, or you may lock yourself out of the internet until you use the bypass or uninstall the tool.
