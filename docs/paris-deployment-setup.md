# Paris API Deployment - Self-Hosted Runner Setup

This guide explains how to set up the Paris VM as a GitHub Actions self-hosted runner and deploy the Paris Parking API automatically.

## Architecture Overview

Since the Paris VM only has a private IP address (no public internet access), we use a **self-hosted GitHub Actions runner** installed on the same VM. This allows GitHub Actions to deploy code directly to the private VM.

**Benefits:**
- ✅ No need for public IP exposure
- ✅ Cost-efficient (same VM for API and runner)
- ✅ Automatic deployments on code changes
- ✅ Secure - traffic stays within the VNet

## Prerequisites

- SSH access to the Paris VM (vm-paris-api)
- GitHub repository access
- Node.js installed on the VM (already done via infrastructure deployment)

## Setup Instructions

### Step 1: Connect to the Paris VM

Since the VM has no public IP, you need to connect through the Azure Bastion or a jump box:

```bash
# Option 1: Azure Bastion (from Azure Portal)
# Go to Azure Portal → VM → Connect → Bastion

# Option 2: Via jumpbox/bastion host
ssh -J jumpbox-user@jumpbox-ip azureadmin@<paris-vm-private-ip>
```

### Step 2: Run the Setup Script

On your **local machine**, transfer the setup script to the Paris VM:

```bash
# From your local machine in the sre-lab directory
scp scripts/setup-paris-runner.sh azureadmin@<vm-ip>:~/
```

On the **Paris VM**, run the setup script:

```bash
chmod +x ~/setup-paris-runner.sh
./setup-paris-runner.sh
```

### Step 3: Configure the Script Variables

Before running, edit the script to set your GitHub details:

```bash
nano ~/setup-paris-runner.sh
```

Update these variables:
```bash
GITHUB_OWNER="your-github-username-or-org"
GITHUB_REPO="sre-lab"
```

### Step 4: Get the Runner Registration Token

1. Go to your GitHub repository
2. Navigate to **Settings** → **Actions** → **Runners**
3. Click **New self-hosted runner**
4. Select **Linux** as the OS
5. Copy the registration token that appears
6. Paste it when the setup script asks for it

### Step 5: Verify the Runner is Active

After setup completes, verify the runner is registered:

1. Go to: `https://github.com/<your-username>/sre-lab/settings/actions/runners`
2. You should see **paris-vm-runner** with a green dot (Idle status)

On the VM, check the service status:
```bash
cd ~/actions-runner
sudo ./svc.sh status
```

## How Deployment Works

### Automatic Deployment

When you push changes to the `backend/paris-parking-api/` directory:

1. GitHub Actions workflow triggers
2. Job runs on the self-hosted runner (Paris VM)
3. Code is checked out on the VM
4. Dependencies are installed
5. Service is restarted with new code
6. Health check verifies the API is running

### Manual Deployment

You can also trigger deployment manually:

1. Go to **Actions** tab in GitHub
2. Select **Deploy Paris API to Linux VM**
3. Click **Run workflow**
4. Select branch and click **Run workflow**

## Service Management

The Paris API runs as a systemd service:

### Check Service Status
```bash
sudo systemctl status paris-parking-api
```

### View Logs
```bash
# Service logs
sudo journalctl -u paris-parking-api -f

# Syslog entries
sudo tail -f /var/log/syslog | grep ParisParkingAPI
```

### Manual Service Control
```bash
# Restart the service
sudo systemctl restart paris-parking-api

# Stop the service
sudo systemctl stop paris-parking-api

# Start the service
sudo systemctl start paris-parking-api
```

### Test the API
```bash
# Health check
curl http://localhost:3003/health

# Get parking info
curl http://localhost:3003/api/parking

# Get metrics
curl http://localhost:3003/api/parking/metrics
```

## Runner Management

### Check Runner Status
```bash
cd ~/actions-runner
sudo ./svc.sh status
```

### View Runner Logs
```bash
journalctl -u actions.runner.* -f
```

### Restart Runner
```bash
cd ~/actions-runner
sudo ./svc.sh restart
```

### Remove Runner

If you need to remove the runner:

```bash
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove --token <removal-token>
```

Get the removal token from: `https://github.com/<owner>/<repo>/settings/actions/runners`

## Troubleshooting

### Runner Not Appearing in GitHub

1. Check if the service is running:
   ```bash
   cd ~/actions-runner
   sudo ./svc.sh status
   ```

2. Check runner logs:
   ```bash
   journalctl -u actions.runner.* -n 50
   ```

3. Verify network connectivity:
   ```bash
   curl -I https://github.com
   ```

### Deployment Fails

1. Check if the runner is online in GitHub UI
2. View workflow logs in GitHub Actions tab
3. Check service logs on the VM:
   ```bash
   sudo journalctl -u paris-parking-api -n 100
   ```

### API Not Responding

1. Check if the service is running:
   ```bash
   sudo systemctl status paris-parking-api
   ```

2. Check for port conflicts:
   ```bash
   sudo lsof -i :3003
   ```

3. Review application logs:
   ```bash
   sudo journalctl -u paris-parking-api -f
   ```

### Permission Issues

If you encounter permission errors:

```bash
# Fix ownership of application directory
sudo chown -R azureadmin:azureadmin /opt/paris-parking-api

# Fix runner directory permissions
sudo chown -R azureadmin:azureadmin ~/actions-runner
```

## Security Considerations

- The VM remains private (no public IP)
- Runner communicates outbound to GitHub (HTTPS)
- No inbound connections required
- Secrets are managed through GitHub Secrets
- Service runs as non-root user (azureadmin)

## Cost Optimization

Running the GitHub Actions runner on the same VM as the API:
- ✅ No additional VM costs
- ✅ Minimal resource overhead (runner uses ~100MB RAM when idle)
- ✅ Runner only active during deployments
- ✅ Same VM serves dual purpose (API host + CI/CD agent)

## Next Steps

1. Set up the runner using the instructions above
2. Make a change to the Paris API code
3. Push to the `main` branch
4. Watch the automatic deployment in the GitHub Actions tab
5. Verify the API is updated by checking the `/health` endpoint
