#!/bin/bash

# =============================================================================
# Database Server Initialization Script
# Installs: Docker, PostgreSQL, Redis, TimescaleDB
# =============================================================================

# Enable error logging
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

set -x  # Enable debug mode
echo "Starting database server initialization at $(date)"

# Update system
echo "Updating system packages..."
yum update -y

# Install Docker
echo "Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Detect and format additional EBS volume
echo "Detecting additional EBS volumes..."
echo "Available block devices:"
lsblk

DATA_DEVICE=""

# Method 1: Find device by size (look for 30GB non-root volume)
echo "Searching for data volume..."
for device in $(lsblk -d -n -o NAME,SIZE,TYPE | grep disk | awk '{print $1}'); do
  FULL_DEVICE="/dev/$device"
  
  # Skip if it's the root device
  if mount | grep -q "^$FULL_DEVICE"; then
    echo "Skipping root device: $device"
    continue
  fi
  
  # Check if device has no filesystem
  FSTYPE=$(lsblk -n -o FSTYPE $FULL_DEVICE 2>/dev/null | head -1)
  if [ -z "$FSTYPE" ]; then
    DATA_DEVICE="$FULL_DEVICE"
    echo "Found unformatted device: $DATA_DEVICE"
    break
  else
    echo "Device $device has filesystem: $FSTYPE (skipping)"
  fi
done

# Method 2: Fallback - check common NVMe data volume names
if [ -z "$DATA_DEVICE" ]; then
  for nvme in nvme1n1 nvme2n1 xvdf sdf; do
    if [ -b "/dev/$nvme" ]; then
      FSTYPE=$(lsblk -n -o FSTYPE /dev/$nvme 2>/dev/null | head -1)
      if [ -z "$FSTYPE" ]; then
        DATA_DEVICE="/dev/$nvme"
        echo "Found unformatted device (fallback): $DATA_DEVICE"
        break
      fi
    fi
  done
fi

# Format and mount data volume
if [ -n "$DATA_DEVICE" ] && [ -b "$DATA_DEVICE" ]; then
  echo "Formatting device $DATA_DEVICE with ext4..."
  if mkfs -t ext4 -F $DATA_DEVICE; then
    echo "Formatting successful!"
    
    mkdir -p /data
    echo "Mounting $DATA_DEVICE to /data..."
    if mount $DATA_DEVICE /data; then
      echo "Mount successful!"
      
      # Add to fstab for persistent mount
      UUID=$(blkid -s UUID -o value $DATA_DEVICE)
      if [ -n "$UUID" ]; then
        echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
        echo "Added to fstab with UUID: $UUID"
      else
        echo "$DATA_DEVICE /data ext4 defaults,nofail 0 2" >> /etc/fstab
        echo "Added to fstab with device path"
      fi
      
      echo "Device mounted successfully!"
    else
      echo "ERROR: Failed to mount $DATA_DEVICE"
      mkdir -p /data
    fi
  else
    echo "ERROR: Failed to format $DATA_DEVICE"
    mkdir -p /data
  fi
else
  echo "WARNING: No additional EBS volume found. Using root volume for data."
  mkdir -p /data
fi

# Create directories with proper permissions
echo "Creating data directories..."
mkdir -p /data/postgres
mkdir -p /data/redis
mkdir -p /data/timescaledb
mkdir -p /data/backups
chown -R ec2-user:docker /data

# Create docker-compose.yml
cat > /opt/database-compose.yml <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:${postgres_version}-alpine
    container_name: postgres
    restart: always
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD:-postgres_password_change_me}
      POSTGRES_DB: academic_platform
    volumes:
      - /data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:${redis_version}-alpine
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    command: redis-server --requirepass $${REDIS_PASSWORD:-redis_password_change_me} --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - /data/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

%{ if enable_timescaledb }
  timescaledb:
    image: timescale/timescaledb:latest-pg15
    container_name: timescaledb
    restart: always
    ports:
      - "5433:5432"
    environment:
      POSTGRES_USER: timescaledb
      POSTGRES_PASSWORD: $${TIMESCALEDB_PASSWORD:-timescaledb_password_change_me}
      POSTGRES_DB: academic_metrics
    volumes:
      - /data/timescaledb:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U timescaledb"]
      interval: 10s
      timeout: 5s
      retries: 5
%{ endif }
EOF

# Start databases
echo "Starting database containers..."
cd /opt
docker-compose -f database-compose.yml up -d

# Wait for services to be ready
echo "Waiting for services to initialize (30 seconds)..."
sleep 30

# Verify containers are running
echo "Verifying containers..."
docker ps

# Create initial databases
echo "Creating initial databases..."
docker exec postgres psql -U postgres -c "CREATE DATABASE kong;" || echo "Kong database may already exist"
docker exec postgres psql -U postgres -c "CREATE DATABASE auth_service;" || echo "Auth service database may already exist"

# Configure automated backups
cat > /opt/backup-databases.sh <<'BACKUP'
#!/bin/bash
BACKUP_DIR="/data/backups"
DATE=$$(date +%%Y%%m%%d_%%H%%M%%S)

# Backup PostgreSQL
docker exec postgres pg_dumpall -U postgres | gzip > $BACKUP_DIR/postgres_$DATE.sql.gz

# Backup Redis
docker exec redis redis-cli --rdb /data/dump.rdb
cp /data/redis/dump.rdb $BACKUP_DIR/redis_$DATE.rdb

# Keep only last 7 days
find $BACKUP_DIR -name "postgres_*.sql.gz" -mtime +7 -delete
find $BACKUP_DIR -name "redis_*.rdb" -mtime +7 -delete
BACKUP
chmod +x /opt/backup-databases.sh

# Schedule daily backups
echo "0 2 * * * /opt/backup-databases.sh" | crontab -

# Create welcome message
cat > /etc/motd <<WELCOME
================================================
Academic Platform - Database Server
Environment: ${environment}
------------------------------------------------
PostgreSQL: port 5432
Redis: port 6379
%{ if enable_timescaledb }TimescaleDB: port 5433%{ endif }
================================================
WELCOME

echo "Database server initialization complete!"

