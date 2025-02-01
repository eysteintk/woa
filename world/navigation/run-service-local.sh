#!/bin/bash
set -e

# Local variables
IMAGE_NAME="woa-world-navigation"
IMAGE_TAG="latest"
LOCAL_PORT=8080
ENV_FILE="local.env"

# Check if environment file exists
check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ Error: $ENV_FILE not found!"
        echo "Please run create-env.sh to generate the environment file."
        exit 1
    fi
}

# Build and run image
echo "🔨 Building Docker image..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

echo "🏃‍♂️ Running the image locally for testing..."
# Stop and remove existing container if it exists
docker rm -f ${IMAGE_NAME}-local 2>/dev/null || true

check_env_file

docker run -d \
    --env-file ${ENV_FILE} \
    -p ${LOCAL_PORT}:80 \
    --add-host=host.docker.internal:host-gateway \
    --name ${IMAGE_NAME}-local \
    ${IMAGE_NAME}:${IMAGE_TAG}

echo "🌐 Local deployment is running at http://localhost:${LOCAL_PORT}"
echo "📊 Viewing logs..."
docker logs -f ${IMAGE_NAME}-local