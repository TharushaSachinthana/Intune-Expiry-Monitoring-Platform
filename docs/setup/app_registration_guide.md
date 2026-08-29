# Microsoft Entra ID App Registration — Setup Guide

## Overview

The monitoring platform authenticates as an **application identity** using Microsoft Entra ID and OAuth 2.0 Client Credentials Flow.

No user login is required — the platform uses an App Registration with **application permissions** to call Microsoft Graph.

---

## Step 1 — Create an App Registration

1. Sign in to [Microsoft Entra ID (Azure AD)](https://entra.microsoft.com)
2. Navigate to: **App registrations** → **New registration**
3. Configure:
   - **Name**: `Intune-Expiry-Monitor` (or your preferred name)
   - **Supported account types**: Accounts in this organizational directory only (Single tenant)
   - **Redirect URI**: Leave blank (not required for Client Credentials Flow)
4. Click **Register**

---

## Step 2 — Note the App Registration Details

After registration, note the following values from the **Overview** page:

| Value | Location | Config Key |
|-------|----------|------------|
| **Application (client) ID** | Overview page | `clientId` |
| **Directory (tenant) ID** | Overview page | `tenantId` |

---

## Step 3 — Create a Client Secret

1. In your App Registration, navigate to: **Certificates & secrets** → **Client secrets** → **New client secret**
2. Configure:
   - **Description**: `Intune-Monitor-Secret`
   - **Expiry**: 12 months (recommended — monitor this expiry too!)
3. Click **Add**
4. **Copy the secret value immediately** — it will not be shown again
5. This is your `clientSecret` config value

> [!CAUTION]
> Store the client secret securely. Do not commit it to source control.
> For production, use Azure Key Vault to store and retrieve secrets.

---

## Step 4 — Grant Application Permissions

1. In your App Registration, navigate to: **API permissions** → **Add a permission** → **Microsoft Graph** → **Application permissions**
2. Add the following permissions:

| Permission | Purpose |
|------------|---------|
| `DeviceManagementServiceConfig.Read.All` | APNs certificate, DEP tokens |
| `DeviceManagementApps.Read.All` | VPP tokens |
| `DeviceManagementConfiguration.Read.All` | Enrollment tokens (future) |

> [!IMPORTANT]
> Apply the **Least Privilege Principle** — only grant permissions for the resources you actively monitor.
> For Phase 1 (APNs only), `DeviceManagementServiceConfig.Read.All` is sufficient.

---

## Step 5 — Grant Admin Consent

Application permissions require **admin consent** before they can be used.

1. After adding permissions, click: **Grant admin consent for [Your Tenant]**
2. Confirm the consent
3. Status should show ✓ **Granted for [Your Tenant]**

---

## Step 6 — Update monitoring_config.json

Open `config/monitoring_config.json` and replace the placeholder values:

```json
"authentication": {
    "tenantId":     "YOUR_ACTUAL_TENANT_ID",
    "clientId":     "YOUR_ACTUAL_CLIENT_ID",
    "clientSecret": "YOUR_ACTUAL_CLIENT_SECRET"
}
```

---

## Step 7 — Validate Setup

Run the setup validation script:

```powershell
# Validate files and config
.\scripts\Setup-Platform.ps1

# Validate files, config, AND test authentication
.\scripts\Setup-Platform.ps1 -TestAuth
```

---

## Authentication Flow Reference

```
Monitoring Application
        │
        │ POST https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token
        │ Body: grant_type=client_credentials
        │       client_id={clientId}
        │       client_secret={clientSecret}
        │       scope=https://graph.microsoft.com/.default
        ▼
Microsoft Entra ID
        │
        │ 200 OK: { access_token, expires_in, token_type }
        ▼
Microsoft Graph API
        │
        │ GET /deviceManagement/applePushNotificationCertificate
        │ Authorization: Bearer {access_token}
        ▼
Intune APNs Certificate Resource
```

---

## References

- [Microsoft identity platform — Client Credentials Flow](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow)
- [Microsoft Graph permissions reference](https://docs.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft Intune — App registrations](https://docs.microsoft.com/en-us/mem/intune/developer/intune-graph-apis)
