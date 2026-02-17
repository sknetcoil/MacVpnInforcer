# VPN Enforcer V2 - Instructions

This document guides you through the installation, usage, and uninstallation of the VPN Enforcer V2 tool.

## Key Upgrades in V2
-   **Instant Reaction**: Blocks traffic instantly (< 1s) when VPN drops.
-   **Secure Bypass**: Uses a secure system directory for the bypass mechanism.
-   **Logging**: detailed logs at `/var/log/vpn_enforcer.log`.

## Installation

1.  **Open Terminal** and navigate to this folder:
    ```bash
    cd /Users/snirkadosh/WebApps/MacVpn
    ```

2.  **Make scripts executable**:
    ```bash
    chmod +x setup.sh uninstall.sh
    ```

3.  **Run the setup script**:
    ```bash
    sudo ./setup.sh
    ```

4.  **Follow the on-screen prompts** to configure your VPN IP and bypass password.

## Verification

To verify the tool is working:
1.  **Disconnect VPN**: Try to browse a website. It should fail IMMEDIATELY.
2.  **Connect VPN**: Browse a website. It should work.
3.  **Check Logs**:
    ```bash
    cat /var/log/vpn_enforcer.log
    ```

## Emergency Bypass

To access the internet without VPN for 5 minutes:
```bash
sudo vpn_control.sh
```

## Uninstallation

To completely remove the tool:
```bash
sudo ./uninstall.sh
```
