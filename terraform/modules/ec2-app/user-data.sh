#!/bin/bash
set -e

# Log everything to a file
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting application deployment..."
echo "App: ${app_name}"
echo "Environment: ${environment}"
echo "Image: ${docker_image}"
echo "=========================================="

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose (optional but useful)
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /opt/${app_name}
cd /opt/${app_name}

# Create docker-compose file
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  app:
    image: ${docker_image}
    container_name: ${app_name}
    restart: always
    ports:
      - "${app_port}:8080"
    environment:
      - PORT=8080
      - SERVICE_NAME=${app_name}
      - ENVIRONMENT=${environment}
      - LOG_LEVEL=info
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

# Pull and start the application
echo "Pulling Docker image..."
docker pull ${docker_image}

echo "Starting application..."
docker-compose up -d

# Wait for app to be healthy
echo "Waiting for application to be healthy..."
sleep 10

# Verify deployment
if curl -s http://localhost:${app_port}/health | grep -q "healthy"; then
    echo "=========================================="
    echo "Application deployed successfully!"
    echo "Health check: PASSED"
    echo "=========================================="
else
    echo "=========================================="
    echo "WARNING: Health check failed!"
    echo "Check logs: docker logs ${app_name}"
    echo "=========================================="
fi

# Create update script for future deployments
cat > /opt/${app_name}/update.sh <<'SCRIPT'
#!/bin/bash
cd /opt/${app_name}
docker-compose pull
docker-compose up -d
docker image prune -f
echo "Update complete!"
SCRIPT
chmod +x /opt/${app_name}/update.sh

echo "Deployment script finished."

