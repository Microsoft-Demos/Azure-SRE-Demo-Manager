# Paris API Quick Setup Guide

## Summary

The Paris API code is structured identically to the Madrid API. It uses HTTPS with self-signed certificates and Syslog for logging. Follow the steps below to deploy and configure it on the Linux VM.

## What's Included

- Certificate generation scripts (`scripts/generate-paris-certs.sh`)
- Paris API code: HTTPS support, Syslog logger, all parking endpoints
- Automated setup script: `scripts/setup-paris-api.sh`
- Automated GitHub Actions deployment: `.github/workflows/deploy-paris-api.yml`

## Quick Setup (Run on Paris VM)

### Option 1: Automated Setup

```bash
# 1. Copy the setup script to the VM
# (Run from your local machine)
scp scripts/setup-paris-api.sh azureadmin@<paris-vm-ip>:~/

# 2. SSH into the Paris VM
ssh azureadmin@<paris-vm-ip>

# 3. Make the script executable
chmod +x setup-paris-api.sh

# 4. Run the setup script
./setup-paris-api.sh

# This will:
# - Create the API directory
# - Copy certificates from <tmp-cert-dir>
# - Create .env file with correct paths
# - Set up systemd service
# - Configure firewall
```

### Option 2: Manual Setup

```bash
# 1. Create API directory
mkdir -p ~/paris-parking-api

# 2. Copy certificates
cp ~/tmp/paris.crt ~/paris-parking-api/
cp ~/tmp/paris.key ~/paris-parking-api/
chmod 600 ~/paris-parking-api/paris.key
chmod 644 ~/paris-parking-api/paris.crt

# 3. Create .env file
cat > ~/paris-parking-api/.env << 'EOF'
PORT=3003
NODE_ENV=production
CERT_PATH=/home/azureadmin/paris-parking-api/paris.crt
KEY_PATH=/home/azureadmin/paris-parking-api/paris.key
PARKING_NAME=Paris Centre Parking
PARKING_CITY=Paris
PARKING_LOCATION=Champs-Élysées, Paris
SYSLOG_FACILITY=local0
SYSLOG_TAG=ParisParkingAPI
EOF

# 4. Deploy application code (choose one method)
# Method A: SCP from local machine
# scp -r backend/paris-parking-api/* azureadmin@<vm-ip>:~/paris-parking-api/

# Method B: Git clone
# cd ~/paris-parking-api && git clone <repo> .

# 5. Install dependencies
cd ~/paris-parking-api
npm install

# 6. Test manually first
node server.js

# Expected output:
# 🚗 Paris Parking API running on HTTPS port 3003
# 📍 Location: Champs-Élysées, Paris
# 🔒 Using HTTPS with self-signed certificate
# 🐧 Platform: linux
# 📝 Syslog: Enabled
```

## Testing

```bash
# Test health endpoint
curl --insecure https://localhost:3003/health

# Expected response:
# {
#   "status": "healthy",
#   "timestamp": "2026-02-05T...",
#   "service": "paris-parking-api",
#   "city": "Paris",
#   "platform": "linux",
#   "syslogLogging": true
# }

# Test parking data
curl --insecure https://localhost:3003/api/parking

# Test from external machine
curl --insecure https://<paris-vm-public-ip>:3003/health
```

## Systemd Service Setup

```bash
# Create service file
sudo tee /etc/systemd/system/paris-parking-api.service > /dev/null << 'EOF'
[Unit]
Description=Paris Parking API Service
After=network.target

[Service]
Type=simple
User=azureadmin
WorkingDirectory=/home/azureadmin/paris-parking-api
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=paris-parking-api
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable paris-parking-api
sudo systemctl start paris-parking-api

# Check status
sudo systemctl status paris-parking-api
```

## Monitoring

```bash
# View service logs
sudo journalctl -u paris-parking-api -f

# View syslog entries
sudo tail -f /var/log/syslog | grep ParisParkingAPI

# Check service status
sudo systemctl status paris-parking-api
```

## Firewall

```bash
# Allow port 3003
sudo ufw allow 3003/tcp

# Check firewall status
sudo ufw status
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u paris-parking-api -n 50 --no-pager

# Test manually
cd ~/paris-parking-api
node server.js
```

### Port already in use

```bash
# Find process using port 3003
sudo lsof -i :3003

# Kill the process
sudo kill -9 <PID>
```

### Certificate errors

```bash
# Verify certificates exist
ls -la ~/paris-parking-api/paris.*

# Check .env file
cat ~/paris-parking-api/.env

# Verify paths match
```

### Syslog not working

```bash
# Install posix module
cd ~/paris-parking-api
npm install posix

# Check rsyslog service
sudo systemctl status rsyslog
```

## File Structure on VM

```
/home/azureadmin/paris-parking-api/
├── server.js              # Main application
├── syslogLogger.js        # Syslog logger
├── package.json           # Dependencies
├── package-lock.json
├── .env                   # Environment config
├── paris.crt              # SSL certificate
├── paris.key              # Private key
└── node_modules/          # Dependencies
```

## Verification Checklist

- [ ] Certificates copied to `~/paris-parking-api/`
- [ ] `.env` file created with correct paths
- [ ] Application files deployed
- [ ] Dependencies installed (`npm install` completed)
- [ ] Service starts without errors
- [ ] Health endpoint responds: `https://localhost:3003/health`
- [ ] Parking endpoint responds: `https://localhost:3003/api/parking`
- [ ] Syslog entries visible in `/var/log/syslog`
- [ ] Service enabled to start on boot
- [ ] Firewall allows port 3003

## Expected State After Setup

```bash
# Service running
$ sudo systemctl status paris-parking-api
● paris-parking-api.service - Paris Parking API Service
   Active: active (running)

# Port listening
$ sudo lsof -i :3003
COMMAND  PID       USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node    1234 azureadmin   23u  IPv6  12345      0t0  TCP *:3003 (LISTEN)

# Logs showing startup
$ sudo journalctl -u paris-parking-api -n 5
🚗 Paris Parking API running on HTTPS port 3003
📍 Location: Champs-Élysées, Paris
🔒 Using HTTPS with self-signed certificate

# Syslog entries
$ sudo tail /var/log/syslog | grep ParisParkingAPI
Feb  5 11:20:15 paris-vm ParisParkingAPI[1234]: {"message":"Parking Operation: SERVER_START"...}
```

## Related Files

- Certificate generation: `scripts/generate-paris-certs.sh` ✅ (already run)
- Setup script: `scripts/setup-paris-api.sh` ✅ (use this)
- Environment template: `backend/paris-parking-api/.env.template`
- Detailed instructions: `docs/paris-api-setup-instructions.md`

## Common Commands

```bash
# Start service
sudo systemctl start paris-parking-api

# Stop service
sudo systemctl stop paris-parking-api

# Restart service
sudo systemctl restart paris-parking-api

# View status
sudo systemctl status paris-parking-api

# Follow logs
sudo journalctl -u paris-parking-api -f

# View syslog
sudo tail -f /var/log/syslog | grep ParisParkingAPI

# Test API
curl --insecure https://localhost:3003/health
```
> **Historical/manual path:** The standard GitHub workflow deploys Paris through Azure VM Run Command and uses private HTTP inside the VNet.
