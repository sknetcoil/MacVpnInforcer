# macOS VPN Enforcer

A robust security tool for macOS that enforces internet access restrictions unless a specific VPN connection is active.

## Overview

This tool ensures that your computer cannot access the internet unless it is connected to a designated VPN. It is designed to run automatically at startup and monitor your connection status constantly.

If the VPN drops, all internet traffic (except to the VPN server itself) is immediately blocked.

## Features

-   **Always-On Protection**: Runs as a system daemon (`launchd`) and starts automatically on boot.
-   **Instant Blocking**: Uses macOS Packet Filter (`pf`) to block traffic the moment the VPN disconnects.
-   **VPN Exception**: Automatically allows traffic to your specific VPN server IP so you can reconnect.
-   **Emergency Bypass**: Includes a password-protected tool to temporarily allow internet access without the VPN (e.g., for captive portals or troubleshooting).

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

### continuous Protection
Once installed, the tool runs in the background. You don't need to do anything.
-   **VPN Connected**: Internet works normally.
-   **VPN Disconnected**: Internet is blocked.

### Emergency Bypass
To temporarily access the internet without the VPN:

1.  Open Terminal.
2.  Run the control command:
    ```bash
    sudo vpn_control.sh
    ```
3.  Enter the bypass password you set during installation.
4.  You will key **5 minutes** of internet access. You can re-run the command to extend the time.

## Technical Details

-   **Backend**: A bash script (`vpn_enforcer.sh`) running as a daemon.
-   **Firewall**: Uses `pfctl` (Packet Filter) to manage rules.
-   **Persistence**: A LaunchDaemon (`com.user.vpnenforcer.plist`) ensures the script restarts if killed and runs on boot.

## Uninstallation

To remove the tool and restore default network settings, run the following commands:

```bash
sudo launchctl unload /Library/LaunchDaemons/com.user.vpnenforcer.plist
sudo rm /Library/LaunchDaemons/com.user.vpnenforcer.plist
sudo rm /usr/local/bin/vpn_enforcer.sh
sudo rm /usr/local/bin/vpn_control.sh
sudo rm /etc/vpn_enforcer.conf
sudo rm /etc/pf.anchors/com.user.vpnenforcer

# Reset Firewall rules
sudo pfctl -a com.user.vpnenforcer -F all
```

## Disclaimer
This tool modifies your system's firewall rules. Use at your own risk. Ensure you have the correct VPN server IP, or you may lock yourself out of the internet until you use the bypass or uninstall the tool.
