# Quick Reference: Certificate Generation Commands

## Madrid VM (Windows Server 2022 - <madrid-vm-ip>)

### Step 1: Generate Certificate
**Run in PowerShell as Administrator:**

```powershell
cd C:\Users\azureadmin\backend\madrid-parking-api
openssl genrsa -out madrid.key 2048
openssl req -new -x509 -key madrid.key -out madrid.crt -days 365 `
  -subj "/C=ES/ST=Madrid/L=Madrid/O=Parking/OU=API/CN=<madrid-vm-ip>"
```

### Step 2: Verify Files
```powershell
dir madrid.*
```
Should show `madrid.crt` and `madrid.key`

### Step 3: Set Environment Variables
**Option A: Via .env file (recommended for services)**
```powershell
# Create or edit .env in the Madrid API directory
Add-Content -Path ".env" -Value "CERT_PATH=C:\Users\azureadmin\backend\madrid-parking-api\madrid.crt"
Add-Content -Path ".env" -Value "KEY_PATH=C:\Users\azureadmin\backend\madrid-parking-api\madrid.key"
```

**Option B: Via System Environment**
```powershell
[Environment]::SetEnvironmentVariable("CERT_PATH", "C:\Users\azureadmin\backend\madrid-parking-api\madrid.crt", "Machine")
[Environment]::SetEnvironmentVariable("KEY_PATH", "C:\Users\azureadmin\backend\madrid-parking-api\madrid.key", "Machine")
```

### Step 4: Restart Service
```powershell
# Stop
net stop MadridParkingAPI

# Start
net start MadridParkingAPI
```

### Step 5: Test
```powershell
curl.exe --insecure https://localhost:3002/api/parking
```

---

## Paris VM (Ubuntu 22.04 - <paris-vm-ip>)

### Step 1: Generate Certificate
**Run in terminal (SSH):**

```bash
cd ~/backend/paris-parking-api
openssl genrsa -out paris.key 2048
openssl req -new -x509 -key paris.key -out paris.crt -days 365 \
  -subj "/C=FR/ST=Paris/L=Paris/O=Parking/OU=API/CN=<paris-vm-ip>"
chmod 600 paris.key
chmod 644 paris.crt
```

### Step 2: Verify Files
```bash
ls -la paris.*
```
Should show `paris.crt` and `paris.key`

### Step 3: Set Environment Variables
**Via .env file (recommended):**
```bash
cat > ~/.env << 'EOF'
PORT=3003
CERT_PATH=/home/azureadmin/backend/paris-parking-api/paris.crt
KEY_PATH=/home/azureadmin/backend/paris-parking-api/paris.key
NODE_ENV=development
EOF
```

**Or append to existing .env:**
```bash
echo "CERT_PATH=/home/azureadmin/backend/paris-parking-api/paris.crt" >> ~/.env
echo "KEY_PATH=/home/azureadmin/backend/paris-parking-api/paris.key" >> ~/.env
```

### Step 4: Restart Service
```bash
# If using systemd
sudo systemctl restart paris-parking-api

# If running manually, kill and restart Node process
pkill -f "node.*paris"
node ~/backend/paris-parking-api/server.js &
```

### Step 5: Test
```bash
curl --insecure https://localhost:3003/api/parking
```

---

## Frontend App Service Configuration

### Set Environment Variables in Azure Portal:

1. Navigate to **App Service** → **Configuration** → **Application settings**
2. Add new application settings:

| Name | Value |
|------|-------|
| `REACT_APP_MADRID_API_URL` | `https://<madrid-vm-ip>:3002` |
| `REACT_APP_PARIS_API_URL` | `https://<paris-vm-ip>:3003` |
| `REACT_APP_LISBON_API_URL` | `<your-container-app-url>` |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` |

3. Click **Save** and confirm **Restart**

### Or via Azure CLI:
```bash
az webapp config appsettings set \
  --resource-group <rg-name> \
  --name <app-service-name> \
  --settings \
    REACT_APP_MADRID_API_URL="https://<madrid-vm-ip>:3002" \
    REACT_APP_PARIS_API_URL="https://<paris-vm-ip>:3003" \
    REACT_APP_LISBON_API_URL="<url>" \
    NODE_TLS_REJECT_UNAUTHORIZED="0"
```

---

## Verification Checklist

### From Madrid VM:
```powershell
# Check certificate is valid
openssl x509 -in madrid.crt -text -noout

# Check cert and key match
(openssl x509 -noout -modulus -in madrid.crt | openssl md5) -eq `
  (openssl rsa -noout -modulus -in madrid.key | openssl md5)

# Test HTTPS endpoint
curl.exe --insecure https://localhost:3002/api/parking
curl.exe --insecure https://localhost:3002/health
```

### From Paris VM:
```bash
# Check certificate is valid
openssl x509 -in paris.crt -text -noout

# Check cert and key match
diff <(openssl x509 -noout -modulus -in paris.crt) \
     <(openssl rsa -noout -modulus -in paris.key)

# Test HTTPS endpoint
curl --insecure https://localhost:3003/api/parking
curl --insecure https://localhost:3003/health
```

### From Local Machine:
```bash
# Test backend directly (may not work if firewall blocks)
curl --insecure https://<madrid-vm-ip>:3002/api/parking
curl --insecure https://<paris-vm-ip>:3003/api/parking

# Test frontend
# Open browser to: https://<app-service-name>.azurewebsites.net
# Check console (F12) for errors
# Verify parking data displays
```

---

## Troubleshooting One-Liners

```bash
# Check if service is running on port
# Windows:
netstat -ano | findstr ":3002"

# Linux:
lsof -i :3003
ss -tlnp | grep 3003

# Kill process on port
# Windows:
taskkill /PID <PID> /F

# Linux:
kill -9 <PID>

# Check certificate expiration
openssl x509 -enddate -noout -in madrid.crt
openssl x509 -enddate -noout -in paris.crt

# View certificate details
openssl x509 -in madrid.crt -text -noout | grep -A 2 "Subject:"
```

---

## Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| `ENOENT: no such file` | Verify cert paths in env vars, use absolute paths |
| `EADDRINUSE: port in use` | Kill other process on port 3002/3003 |
| `Certificate not trusted` | Normal for self-signed; use `--insecure` with curl or accept warning in browser |
| `CORS error in browser` | Ensure CORS middleware active, check backend URL in frontend config |
| `Mixed content error` | Both frontend and backend must be HTTPS (or both HTTP) |
| `Service won't start` | Check cert files exist and are readable, review logs |

---

## Timeline Estimate

- **Certificate generation:** 5-10 minutes per VM
- **Environment variable setup:** 2-3 minutes per VM
- **Service restart:** 1-2 minutes per VM
- **Frontend deployment:** 3-5 minutes (GitHub Actions)
- **Testing & validation:** 5-10 minutes
- **Total:** ~30-45 minutes for complete setup

---
> **Optional legacy HTTPS path:** The portable Azure deployment uses private HTTP VM endpoints over VNet integration and does not disable TLS verification in the frontend proxy.
