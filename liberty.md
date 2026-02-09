
# Test S3 access
aws s3 ls s3://opentofu-state-bucket-donot-delete2/

# ============================================================================
# PHASE 1: DOWNLOAD AND EXTRACT LIBERTY
# ============================================================================

# Create working directory
cd ~
mkdir -p liberty-bc
cd liberty-bc

# Download Liberty from IBM
wget https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/wasdev/downloads/wlp/26.0.0.1/wlp-javaee8-26.0.0.1.zip

# Extract Liberty
unzip wlp-javaee8-26.0.0.1.zip

# Navigate to Liberty directory
cd wlp

# ============================================================================
# PHASE 2: DOWNLOAD FEATURES TO LOCAL CACHE
# ============================================================================

# Download Liberty features to local cache
./bin/installUtility download --location=./feature-cache --acceptLicense \
  beanValidation-2.0 \
  cdi-2.0 \
  jaxrs-2.1 \
  jdbc-4.2 \
  jndi-1.0 \
  jpa-2.2 \
  mpMetrics-3.0 \
  mpHealth-3.0

# Verify downloads
ls -lh feature-cache/features/26.0.0.1/*.esa | wc -l
# Should show ~89 files

# Package the feature cache
tar -czf liberty-feature-cache-26.0.0.1.tar.gz feature-cache/

# ============================================================================
# PHASE 3: UPLOAD TO S3
# ============================================================================

# Create Liberty directory in S3
aws s3 mb s3://opentofu-state-bucket-donot-delete2/liberty/ 2>/dev/null || true

# Upload Liberty runtime (correct path)
aws s3 cp ../wlp-javaee8-26.0.0.1.zip \
  s3://opentofu-state-bucket-donot-delete2/liberty/wlp-javaee8-26.0.0.1.zip

# Upload feature cache (already in current directory)
aws s3 cp liberty-feature-cache-26.0.0.1.tar.gz \
  s3://opentofu-state-bucket-donot-delete2/liberty/liberty-feature-cache-26.0.0.1.tar.gz

# Verify uploads
aws s3 ls s3://opentofu-state-bucket-donot-delete2/liberty/

# ============================================================================
# PHASE 4: BUILD DOCKER IMAGE
# ============================================================================

# Create Docker build directory
cd ~/liberty-build
mkdir docker-build
cd docker-build

# Build with AWS credentials as build arguments
cat > Dockerfile <<'EOF'
FROM registry.access.redhat.com/ubi8/openjdk-11:latest

USER root

# Accept AWS credentials as build arguments
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_DEFAULT_REGION=us-east-1

# Install unzip and AWS CLI
RUN microdnf install -y unzip tar gzip && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip && \
    microdnf clean all

# Set AWS credentials for this layer
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION

# Create IBM directory and download Liberty runtime from S3
RUN mkdir -p /opt/ibm && \
    aws s3 cp s3://opentofu-state-bucket-donot-delete2/liberty/wlp-javaee8-26.0.0.1.zip /tmp/ && \
    cd /tmp && \
    unzip wlp-javaee8-26.0.0.1.zip && \
    mv wlp /opt/ibm/wlp && \
    rm wlp-javaee8-26.0.0.1.zip

# Download feature cache from S3
RUN aws s3 cp s3://opentofu-state-bucket-donot-delete2/liberty/liberty-feature-cache-26.0.0.1.tar.gz /tmp/ && \
    tar -xzf /tmp/liberty-feature-cache-26.0.0.1.tar.gz -C /opt/ibm/wlp/ && \
    rm /tmp/liberty-feature-cache-26.0.0.1.tar.gz

# Unset credentials (security best practice)
ENV AWS_ACCESS_KEY_ID= \
    AWS_SECRET_ACCESS_KEY= \
    AWS_DEFAULT_REGION=

# Set permissions
RUN chown -R 1001:0 /opt/ibm/wlp && \
    chmod -R g+rw /opt/ibm/wlp

USER 1001

CMD ["/opt/ibm/wlp/bin/server", "run", "defaultServer"]
EOF


## Then build:
docker build \
  --build-arg AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) \
  --build-arg AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) \
  -t liberty-with-deps:26.0.0.1 .

# ============================================================================
# PHASE 5: TAG AND PUSH TO ECR
# ============================================================================

# Tag for ECR
docker tag liberty-with-deps:26.0.0.1 \
  126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1

docker tag liberty-with-deps:26.0.0.1 \
  126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  126924000548.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
docker push 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1
docker push 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

# Verify
aws ecr describe-images \
  --repository-name liberty/liberty-base \
  --region us-east-1

# ============================================================================
# PHASE 6: TEST THE IMAGE
# ============================================================================

# Create test directory
cd ~/liberty-build
mkdir test-app
cd test-app

# Create test server.xml
cat > server.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="test server">
    <featureManager>
        <feature>beanValidation-2.0</feature>
        <feature>cdi-2.0</feature>
        <feature>jaxrs-2.1</feature>
        <feature>jdbc-4.2</feature>
        <feature>jndi-1.0</feature>
        <feature>jpa-2.2</feature>
        <feature>mpMetrics-3.0</feature>
        <feature>mpHealth-3.0</feature>
    </featureManager>
    
    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443"/>
</server>
EOF

# Create test Dockerfile
cat > Dockerfile <<'EOF'
FROM 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

USER root

COPY server.xml /config/server.xml

RUN /opt/ibm/wlp/bin/server create defaultServer && \
    chown -R 1001:0 /opt/ibm/wlp/usr/servers/defaultServer && \
    chmod -R g+rw /opt/ibm/wlp/usr/servers/defaultServer

USER 1001

CMD ["/opt/ibm/wlp/bin/server", "run", "defaultServer"]
EOF

# Build test app
docker build -t liberty-test-app .

# Run test app
docker run -d -p 9080:9080 --name liberty-test liberty-test-app

# Wait for startup
sleep 10

# Check if running
docker logs liberty-test

# Test endpoint
curl http://localhost:9080/

# Cleanup test
docker stop liberty-test
docker rm liberty-test

# ============================================================================
# SUCCESS VERIFICATION
# ============================================================================

echo "✅ Verification Checklist:"
echo "1. S3 files uploaded:"
aws s3 ls s3://opentofu-state-bucket-donot-delete2/liberty/
echo ""
echo "2. ECR images pushed:"
aws ecr describe-images --repository-name liberty/liberty-base --region us-east-1 --query 'imageDetails[*].imageTags' --output table
echo ""
echo "3. Test app started successfully"
echo ""
echo " Liberty base image is ready for Daniel's team!"

# ============================================================================
# CLEANUP (Optional)
# ============================================================================

# Remove local build artifacts
cd ~
rm -rf liberty-build

# Note: Keep S3 files and ECR images for production use

## TEST K8S
### create a repo
```sh
aws ecr create-repository \
  --repository-name liberty-test-app \
  --region us-east-1
```

```sh
# Create test directory
mkdir ~/liberty-k8s-test
cd ~/liberty-k8s-test

# Create test server.xml
cat > server.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="test server">
    <featureManager>
        <feature>beanValidation-2.0</feature>
        <feature>cdi-2.0</feature>
        <feature>jaxrs-2.1</feature>
        <feature>jdbc-4.2</feature>
        <feature>jndi-1.0</feature>
        <feature>jpa-2.2</feature>
        <feature>mpMetrics-3.0</feature>
        <feature>mpHealth-3.0</feature>
    </featureManager>
    
    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443"/>
    
    <mpMetrics authentication="false"/>
    <mpHealth/>
</server>
EOF

# Create Dockerfile for test app
cd ~/liberty-k8s-test

cat > Dockerfile <<'EOF'
FROM 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

USER root

COPY server.xml /config/server.xml

RUN /opt/ibm/wlp/bin/server create defaultServer && \
    cp /config/server.xml /opt/ibm/wlp/usr/servers/defaultServer/server.xml && \
    chown -R 1001:0 /opt/ibm/wlp/usr/servers/defaultServer && \
    chmod -R g+rw /opt/ibm/wlp/usr/servers/defaultServer

USER 1001

# Use exec form to ensure server stays in foreground
ENTRYPOINT ["/opt/ibm/wlp/bin/server"]
CMD ["run", "defaultServer"]
EOF

# Build test app
docker build -t 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty-test-app:latest .

# Push to ECR
docker push 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty-test-app:latest

# Create Kubernetes manifests
cat > k8s-deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: liberty-test
  labels:
    app: liberty-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: liberty-test
  template:
    metadata:
      labels:
        app: liberty-test
    spec:
      containers:
      - name: liberty
        image: 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty-test-app:latest
        ports:
        - containerPort: 9080
          name: http
        - containerPort: 9443
          name: https
        livenessProbe:
          httpGet:
            path: /health/live
            port: 9080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 9080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: liberty-test
spec:
  selector:
    app: liberty-test
  ports:
  - name: http
    port: 9080
    targetPort: 9080
  - name: https
    port: 9443
    targetPort: 9443
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: liberty-test
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: liberty.s3g.be
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: liberty-test
            port:
              number: 9080
EOF

# Deploy to Kubernetes
kubectl apply -f k8s-deployment.yaml

# Watch the deployment
kubectl get pods -l app=liberty-test -w
```

## # Check pod status
```sh
# Check pod status
kubectl get pods -l app=liberty-test

# Check logs for "server is ready"
kubectl logs -l app=liberty-test

# Test health endpoints
curl http://liberty.sdoves.be/health/live
curl http://liberty.sdoves.be/health/ready

# Test metrics endpoint
curl http://liberty.sdoves.be/metrics
