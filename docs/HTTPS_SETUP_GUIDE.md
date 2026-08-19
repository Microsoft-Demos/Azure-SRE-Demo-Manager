# HTTPS Setup Guide for Parking APIs

This guide provides step-by-step instructions to generate self-signed certificates and configure the backend APIs (Madrid and Paris) to use HTTPS.

## Overview

The parking APIs (Madrid on port 3002, Paris on port 3003) are being configured to use HTTPS with self-signed certificates. This allows:
- Frontend React app (HTTPS) to communicate with backend APIs over HTTPS without mixed-content blocking
- Private IP connectivity (<madrid-vm-ip> for Madrid, <paris-vm-ip> for Paris)
- Development/testing with self-signed certificates

## Prerequisites

- OpenSSL installed on the VMs (included in most Linux distributions and Windows Git Bash)
- SSH/RDP access to Madrid and Paris VMs
- Administrator privileges on the VMs

## Step 1: Generate Self-Signed Certificates

### For Madrid VM (Windows Server 2022)

**Connect to Madrid VM via RDP:**
```
IP: <madrid-vm-ip>
Port: 3389
```

**Generate certificate (run in PowerShell as Administrator):**

```powershell
# Navigate to Madrid API directory
cd C:\path\to\backend\madrid-parking-api

# Generate private key (valid for 365 days)
openssl genrsa -out madrid.key 2048

# Generate self-signed certificate
openssl req -new -x509 -key madrid.key -out madrid.crt -days 365 `
  -subj "/C=ES/ST=Madrid/L=Madrid/O=Parking/OU=API/CN=<madrid-vm-ip>"
```

**Alternative: Using Git Bash (if OpenSSL not in PATH):**
```bash
# Open Git Bash as Administrator
cd C:\path\to\backend\madrid-parking-api

# Generate private key
"C:\Program Files\Git\usr\bin\openssl.exe" genrsa -out madrid.key 2048

# Generate certificate
"C:\Program Files\Git\usr\bin\openssl.exe" req -new -x509 -key madrid.key -out madrid.crt -days 365 \
  -subj "/C=ES/ST=Madrid/L=Madrid/O=Parking/OU=API/CN=<madrid-vm-ip>"
```

**Verify files created:**
```powershell
dir madrid.*
# Should show: madrid.crt and madrid.key
```

### For Paris VM (Ubuntu 22.04)

**Connect to Paris VM via SSH:**
```bash
ssh -i <key.pem> azureadmin@<paris-vm-ip>
```

**Generate certificates:**
```bash
# Navigate to Paris API directory
cd /home/azureadmin/backend/paris-parking-api

# Generate private key (valid for 365 days)
openssl genrsa -out paris.key 2048

# Generate self-signed certificate
openssl req -new -x509 -key paris.key -out paris.crt -days 365 \
  -subj "/C=FR/ST=Paris/L=Paris/O=Parking/OU=API/CN=<paris-vm-ip>"
```

**Verify files created:**
```bash
ls -la paris.*
# Should show: paris.crt and paris.key with proper permissions
```

**Set proper permissions (important):**
```bash
chmod 600 paris.key
chmod 644 paris.crt
```

## Step 2: Update Environment Variables

### Madrid VM - Windows Environment Variables

**Set via PowerShell (Administrator):**
```powershell
# Set for current user
[Environment]::SetEnvironmentVariable("CERT_PATH", "C:\path\to\madrid.crt", "User")
[Environment]::SetEnvironmentVariable("KEY_PATH", "C:\path\to\madrid.key", "User")

# Or set for the service (if running as a service):
# Edit the .env file in the Madrid API directory
```

**Or update `.env` file:**
```
PORT=3002
CERT_PATH=C:\path\to\backend\madrid-parking-api\madrid.crt
KEY_PATH=C:\path\to\backend\madrid-parking-api\madrid.key
PARKING_NAME=Madrid Centro Parking
PARKING_CITY=Madrid
PARKING_LOCATION=Plaza Mayor, Madrid
EVENT_LOG_SOURCE=MadridParkingAPI
EVENT_LOG_NAME=Application
```

**Restart the Madrid service:**
```powershell
# Stop the service
net stop MadridParkingAPI

# Start the service
net start MadridParkingAPI

# Or if running as console app, restart manually
```

### Paris VM - Linux Environment Variables

**Set via environment or `.env` file:**
```bash
# Edit or create .env file in the Paris API directory
cat > /home/azureadmin/backend/paris-parking-api/.env << 'EOF'
PORT=3003
CERT_PATH=/home/azureadmin/backend/paris-parking-api/paris.crt
KEY_PATH=/home/azureadmin/backend/paris-parking-api/paris.key
PARKING_NAME=Paris Centre Parking
PARKING_CITY=Paris
PARKING_LOCATION=Champs-Élysées, Paris
SYSLOG_FACILITY=local0
SYSLOG_TAG=ParisParkingAPI
EOF
```

**Restart the Paris service:**
```bash
# If running as systemd service
sudo systemctl restart paris-parking-api

# Or if running manually, stop and start the Node.js process
```

## Step 3: Test HTTPS Connectivity

### Test Madrid API (on Madrid VM or from another machine)

**Using curl with self-signed certificate:**
```bash
# Test from local (ignoring certificate validation - development only)
curl --insecure https://localhost:3002/api/parking

# Expected output: JSON parking data
# {
#   "id": "madrid-parking-001",
#   "name": "Madrid Centro Parking",
#   ...
# }
```

**Verify certificate details:**
```bash
# View certificate
openssl x509 -in madrid.crt -text -noout

# Verify certificate and key match
openssl x509 -noout -modulus -in madrid.crt | openssl md5
openssl rsa -noout -modulus -in madrid.key | openssl md5
# Both md5 hashes should be identical
```

### Test Paris API (on Paris VM or from another machine)

```bash
# Test from local
curl --insecure https://localhost:3003/api/parking

# Expected output: JSON parking data
# {
#   "id": "paris-parking-001",
#   "name": "Paris Centre Parking",
#   ...
# }
```

### Test from Frontend App Service

The React frontend needs to accept self-signed certificates. Options:

**Option A: Development Mode - Disable Certificate Validation (NOT for Production)**

Add to App Service environment variables:
```
NODE_TLS_REJECT_UNAUTHORIZED=0
```

Then restart the App Service.

**Option B: Production Mode - Configure Fetch with Custom Agent**

Update `parkingService.ts` to handle self-signed certificates properly (more secure):

```typescript
// This requires additional configuration in the React app
// See: https://nodejs.org/api/https.html#https_https_request_options_callback
```

## Step 4: Update Frontend Configuration

The React frontend (`parkingService.ts`) has been updated to call:
- Madrid: `https://<madrid-vm-ip>:3002`
- Paris: `https://<paris-vm-ip>:3003`

### Via Environment Variables (Recommended)

Set these in App Service Configuration:
```
REACT_APP_MADRID_API_URL=https://<madrid-vm-ip>:3002
REACT_APP_PARIS_API_URL=https://<paris-vm-ip>:3003
REACT_APP_LISBON_API_URL=<public-container-app-url>
```

### Via Code Defaults

If environment variables are not set, the app uses defaults defined in `parkingService.ts`.

## Step 5: Verify End-to-End Connectivity

**From your local machine:**

1. Test backend directly:
```bash
curl --insecure https://<madrid-vm-ip>:3002/api/parking
curl --insecure https://<paris-vm-ip>:3003/api/parking
```

2. Access frontend:
```
https://<app-parking-frontend-xxx>.azurewebsites.net
```

3. Check browser console for any errors:
   - Open DevTools (F12)
   - Go to Console tab
   - Look for CORS errors or certificate warnings

4. Verify parking data loads:
   - Madrid and Paris parking data should display
   - No mixed-content errors should appear

## Troubleshooting

### Certificate Path Issues

**Problem:** `ENOENT: no such file or directory`

**Solution:**
- Verify certificate files exist: `ls -la madrid.crt madrid.key`
- Check path in environment variable matches actual file location
- Use absolute paths in CERT_PATH and KEY_PATH

### Port Already in Use

**Problem:** `EADDRINUSE: address already in use :::3002`

**Solution:**
```bash
# Find process using port
lsof -i :3002  # Linux/Mac
netstat -ano | findstr :3002  # Windows

# Kill the process
kill -9 <PID>  # Linux/Mac
taskkill /PID <PID> /F  # Windows
```

### Certificate Not Trusted

**Problem:** Browser shows certificate warning

**Solution:** This is expected for self-signed certificates in development
- Click "Advanced" and "Proceed" (varies by browser)
- Or add the certificate to trusted roots (production approach)

### CORS Errors

**Problem:** `Access to XMLHttpRequest has been blocked by CORS policy`

**Solution:**
- Verify CORS is enabled in Node.js server: `app.use(cors())`
- Check that frontend is calling correct IP and port
- Review backend logs for blocked requests

### Service Won't Start

**Problem:** Service fails on startup

**Solution:**
- Check certificate files exist and are readable
- Verify certificate and key are valid: `openssl x509 -in madrid.crt -text -noout`
- Review application logs for detailed error messages

## Important Notes

1. **Self-Signed Certificates:** These are for development/testing only. In production, use certificates from a trusted Certificate Authority.

2. **Certificate Validity:** Certificates are valid for 365 days. Plan to regenerate before expiration.

3. **Private IPs:** Certificates use private IPs (<madrid-vm-ip>, <paris-vm-ip>). They won't work if accessed via public IPs or DNS names (unless DNS also points to these IPs).

4. **Mixed Content:** Ensure frontend URL scheme (HTTPS) matches backend API scheme (HTTPS).

5. **Firewall Rules:** Ensure NSG rules allow inbound traffic on ports 3002 and 3003 from the App Service subnet.

## Certificate Renewal

When certificates expire (after 365 days):

```bash
# Delete old certificates
rm madrid.crt madrid.key

# Regenerate using steps in Step 1
openssl genrsa -out madrid.key 2048
openssl req -new -x509 -key madrid.key -out madrid.crt -days 365 \
  -subj "/C=ES/ST=Madrid/L=Madrid/O=Parking/OU=API/CN=<madrid-vm-ip>"

# Restart the service
```

## Next Steps

1. Run certificate generation commands on Madrid VM
2. Run certificate generation commands on Paris VM
3. Update environment variables on both VMs
4. Restart both services
5. Test HTTPS connectivity from frontend
6. Monitor application logs for issues
7. Verify parking data displays correctly in React frontend

> **Optional legacy HTTPS path:** The portable Azure deployment uses private HTTP VM endpoints over VNet integration. Follow this guide only if you intentionally add trusted VM certificates and update the API URLs.
