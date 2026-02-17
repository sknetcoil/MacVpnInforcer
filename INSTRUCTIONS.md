# VPN Enforcer - Instructions

This document guides you through the installation, usage, and uninstallation of the VPN Enforcer tool.

## Prerequisites

-   macOS (tested on recent versions)
-   Root privileges (via `sudo`)
-   Knowledge of your VPN Server IP address

## Installation

1.  **Open Terminal** and navigate to this folder:
    ```bash
    cd /Users/snirkadosh/WebApps/MacVpn
    ```

2.  **Make the setup script executable**:
    ```bash
    chmod +x setup.sh
    ```

3.  **Run the setup script**:
    ```bash
    sudo ./setup.sh
    ```

4.  **Follow the on-screen prompts**:
    -   **VPN Server IP**: Enter the IP address of the VPN server you need to connect to.
    -   **VPN Interface**: Press Enter to use the default `utun` (or specify `utun0`, `utun1` if known).
    -   **Bypass Password**: Set a secure password. This is required to temporarily disable the internet block if you need to access the internet without the VPN.

## How it Works

-   **Automatic Blocking**: When the computer starts, or when the VPN disconnects, the tool automatically blocks all outgoing internet traffic (except to the VPN server itself).
-   **VPN Connection**: Once the VPN connects, the tool detects it and automatically opens internet access through the VPN.

## Bypass Mode (Emergency Internet Access)

If you need to access the internet *without* the VPN (e.g., to login to a captive portal, or if the VPN server is down):

1.  Run the control script:
    ```bash
    sudo vpn_control.sh
    ```
    *(Note: This usage assumes the script is in your path. If not found, run `/usr/local/bin/vpn_control.sh`)*

2.  Enter the **Bypass Password** you set during installation.
3.  If correct, you will have internet access for **5 minutes**. You can run the command again to extend the time.

## Verification

To verify the tool is working:
1.  **Disconnect VPN**: Try to browse a website. It should fail.
2.  **Connect VPN**: Browse a website. It should work.

## Uninstallation

To completely remove the tool and restore normal settings:

1.  Run the following commands in Terminal:
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
