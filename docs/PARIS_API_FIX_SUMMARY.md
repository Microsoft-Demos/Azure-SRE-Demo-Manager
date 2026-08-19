# Paris API Setup Notes

## Overview

The Paris API is structurally identical to the Madrid API. Both expose the same RESTful endpoints and support HTTPS via self-signed certificates. The key difference is the logging backend:

- **Madrid**: Windows Event Viewer (`windowsEventLogger.js`)
- **Paris**: Linux Syslog (`syslogLogger.js`)

## API Feature Comparison

| Feature | Madrid | Paris |
|---------|--------|-------|
| HTTPS Support | ✅ | ✅ |
| Certificate Handling | ✅ | ✅ |
| API Endpoints | ✅ | ✅ |
| Error Handling | ✅ | ✅ |
| Health Check | ✅ | ✅ |
| Graceful Shutdown | ✅ | ✅ |
| Logger | Windows Event Viewer | Syslog |

## Default Configuration

| Setting | Madrid | Paris |
|---------|--------|-------|
| Port | 3002 | 3003 |
| Levels | 4 | 6 |
| Slots/Level | 120 | 80 |

## Certificate Setup

Certificates for the Paris API are generated via `scripts/generate-paris-certs.sh`. They should be placed in the API directory (e.g., `/opt/paris-parking-api/`). See [HTTPS_SETUP_GUIDE.md](HTTPS_SETUP_GUIDE.md) for details.

## Deployment

The GitHub Actions workflow (`deploy-paris-api.yml`) automates certificate generation and deployment. See [paris-deployment-setup.md](paris-deployment-setup.md) for setup instructions.

## Verification

After deployment:

```bash
sudo systemctl status paris-parking-api
curl --insecure https://localhost:3003/health
curl --insecure https://localhost:3003/api/parking
sudo journalctl -u paris-parking-api -f
sudo tail -f /var/log/syslog | grep ParisParkingAPI
```
> **Historical note:** The portable deployment now runs the private Paris endpoint over HTTP inside the VNet by default.
