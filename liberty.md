# 1. Download latest Liberty
wget https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/wasdev/downloads/wlp/${LIBERTY_VERSION}/wlp-javaee8-${LIBERTY_VERSION}.zip

# Extract Liberty package
cd ~/Downloads
unzip wlp-javaee8-26.0.0.1.zip

# Navigate to Liberty bin directory
cd wlp

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

# Package the feature cache
tar -czf liberty-feature-cache-26.0.0.1.tar.gz feature-cache/

# Create project directory
mkdir ~/liberty-base-image
cd ~/liberty-base-image

# Copy feature cache
```sh
cp ~/Downloads/wlp/liberty-feature-cache-26.0.0.1.tar.gz .

# Copy feature cache (correct path)
cp ~/Downloads/wlp/liberty-feature-cache-26.0.0.1.tar.gz .

# Create Dockerfile
cat > Dockerfile <<'EOF'
FROM icr.io/appcafe/websphere-liberty:26.0.0.1

LABEL maintainer="middleware-team"
LABEL description="WebSphere Liberty with pre-cached features for offline builds"
LABEL version="26.0.0.1"

ADD liberty-feature-cache-26.0.0.1.tar.gz /opt/ibm/wlp/

RUN ls -la /opt/ibm/wlp/feature-cache/

RUN /opt/ibm/wlp/bin/installUtility install \
    --acceptLicense \
    --from=/opt/ibm/wlp/feature-cache \
    beanValidation-2.0 \
    cdi-2.0 \
    jaxrs-2.1 \
    jdbc-4.2 \
    jndi-1.0 \
    jpa-2.2 \
    mpMetrics-3.0 \
    mpHealth-3.0 \
    || echo "Some features already present or will be installed from cache"

CMD ["/opt/ibm/wlp/bin/server", "run", "defaultServer"]
EOF
```

## ORRR BUILD ON RHEL - WHAT I USED
```sh
cp -r ~/Downloads/wlp ./wlp-runtime

# Create Dockerfile with RHEL base
cat > Dockerfile <<'EOF'
FROM registry.access.redhat.com/ubi8/openjdk-11:latest

USER root

COPY wlp-runtime /opt/ibm/wlp

ADD liberty-feature-cache-26.0.0.1.tar.gz /opt/ibm/wlp/

RUN chown -R 1001:0 /opt/ibm/wlp && \
    chmod -R g+rw /opt/ibm/wlp

USER 1001

CMD ["/opt/ibm/wlp/bin/server", "run", "defaultServer"]
EOF
```

# Build image
docker build -t liberty-with-deps:26.0.0.1 .

# Tag for ECR (using your actual ECR repository)
docker tag liberty-with-deps:26.0.0.1 12692.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1
docker tag liberty-with-deps:26.0.0.1 12692.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 12692.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
docker push 12692.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1
docker push 12692.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest


## Daniel's team changes FROM line:
# Before
FROM icr.io/appcafe/websphere-liberty:latest

# After
FROM 12692.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest
