# APNs Certificate Renewal Runbook

## Trigger Conditions

This runbook applies when the Intune Expiry Monitoring Platform generates:
- **CRITICAL** alert — APNs certificate 8–30 days from expiry
- **URGENT** alert — APNs certificate ≤ 7 days from expiry

---

## Business Impact

An expired APNs certificate breaks Intune communication with **all managed Apple devices**:

```
APNs Certificate (expired)
        ↓
Apple Push Notification Service (unavailable)
        ↓
Intune Device Communication (broken)
        ↓
Managed Apple Devices (unresponsive to MDM)
        ↓
Policy Delivery (failed)
        ↓
Business Operations (disrupted)
```

**Affected device types**: iOS, iPadOS, macOS  
**Estimated recovery time after renewal**: 4–8 hours

---

## Pre-Renewal Checklist

Before beginning renewal:

- [ ] Identify the Apple ID used to create the current APNs certificate
- [ ] Confirm you have access to the Apple Push Certificates Portal
- [ ] Confirm you have Intune Administrator access in the Microsoft Intune Admin Center
- [ ] Notify relevant stakeholders of the upcoming renewal activity
- [ ] Schedule during a low-impact maintenance window if possible

> [!CAUTION]
> The renewal must be performed with **the same Apple ID** that created the original certificate.
> Using a different Apple ID will create a new certificate and break all existing device enrollments.

---

## Renewal Steps

### Step 1 — Verify Current Certificate Status

1. Sign in to [Microsoft Intune Admin Center](https://intune.microsoft.com)
2. Navigate to: **Devices** → **Enroll Devices** → **Apple MDM Push Certificate**
3. Note:
   - Current expiration date
   - Apple ID associated with the certificate
   - Certificate subject / topic identifier

### Step 2 — Download the Certificate Signing Request (CSR)

1. In the APNs certificate blade, click **Download your CSR**
2. Save the `.csr` file locally

### Step 3 — Sign in to Apple Push Certificates Portal

1. Navigate to: [https://identity.apple.com/pushcert/](https://identity.apple.com/pushcert/)
2. Sign in with the **same Apple ID** used for the original certificate

> [!WARNING]
> Signing in with a different Apple ID will create a new certificate, breaking existing enrollments.

### Step 4 — Renew the Certificate

1. Locate the existing Intune certificate in the portal (look for Microsoft Corporation as the vendor)
2. Click **Renew** (do NOT click Create a Certificate)
3. Upload the `.csr` file downloaded in Step 2
4. Download the renewed `.pem` file

### Step 5 — Upload the Renewed Certificate to Intune

1. Return to Intune Admin Center → APNs Certificate blade
2. Click **Upload your MDM push Certificate**
3. Enter the Apple ID used for renewal
4. Select the `.pem` file downloaded from Apple Push Certificates Portal
5. Click **Upload**

### Step 6 — Verify Renewal

1. Confirm the new expiry date shows approximately 1 year from today
2. Verify the certificate status shows **Active**
3. Check that a test device responds to a sync request within 30 minutes

---

## Post-Renewal Actions

- [ ] Update any documentation or CMDB records with the new expiry date
- [ ] Run the monitoring platform to confirm the new HealthState = **HEALTHY**
- [ ] Notify stakeholders that renewal is complete
- [ ] Close any open CRITICAL/URGENT incidents

---

## Monitoring Verification

After renewal, run a dry-run to confirm the platform detects the updated certificate:

```powershell
.\src\core\Invoke-MonitoringRun.ps1 -DryRun
```

Expected output:
```
🟢 MDM Push Certificate
    Health State  : Healthy
    Days Remaining: ~365
    Expires       : [New Date ~1 year from today]
    Action        : Not Required
```

---

## References

- [Microsoft Docs — Apple MDM Push Certificate](https://docs.microsoft.com/en-us/mem/intune/enrollment/apple-mdm-push-certificate-get)
- [Apple Push Certificates Portal](https://identity.apple.com/pushcert/)
- [Microsoft Intune Admin Center](https://intune.microsoft.com)
