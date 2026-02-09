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
docker tag liberty-with-deps:26.0.0.1 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1
docker tag liberty-with-deps:26.0.0.1 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 126924000548.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
docker push 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:26.0.0.1
docker push 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest


## Daniel's team changes FROM line:
# Before
FROM icr.io/appcafe/websphere-liberty:latest

# After
```sh
# Create test directory
mkdir ~/liberty-test-app
cd ~/liberty-test-app

# Create Daniel's server.xml (from the transcript)
cat > server.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="new server">
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
    
    <mpMetrics authentication="false"/>
    
    <jdbcDriver id="DB2">
        <library name="DB2JCCALib"/>
    </jdbcDriver>
    
    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443"/>
</server>
EOF

# Create a simple test Dockerfile that mimics Daniel's build
cat > Dockerfile <<'EOF'
FROM 126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base:latest

USER root

# Copy server.xml
COPY server.xml /config/server.xml

# Create default server configuration
RUN /opt/ibm/wlp/bin/server create defaultServer && \
    chown -R 1001:0 /opt/ibm/wlp/usr/servers/defaultServer && \
    chmod -R g+rw /opt/ibm/wlp/usr/servers/defaultServer

USER 1001

CMD ["/opt/ibm/wlp/bin/server", "run", "defaultServer"]
EOF

# Build
docker build -t liberty-test-app .

```

## RUN IT LOCALLY
```sh
# Start the container
docker run -p 9080:9080 --rm liberty-test-app

# In another terminal, check if it started
curl http://localhost:9080/

# Check logs for successful feature installation
docker logs $(docker ps -q --filter ancestor=liberty-test-app)



```
# Liberty Base Image Solution - Architecture Documentation

## Executive Summary
Solution to eliminate monthly build failures caused by IBM WebSphere Liberty repository outages (occurring 10th-15th of each month). Implements internal caching of Liberty features to ensure continuous delivery pipeline reliability.

---

## Architecture Diagram
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOLUTION ARCHITECTURE                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: ONE-TIME SETUP (Monthly Maintenance)                                │
└──────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────┐
    │  IBM Repository │ (External - Unreliable)
    │  public.dhe.ibm │
    └────────┬────────┘
             │ 1. Download Liberty 26.0.0.1
             │    + Feature Archives (.esa files)
             ↓
    ┌─────────────────┐
    │ Middleware Team │
    │  Downloads:     │
    │  • wlp runtime  │
    │  • features     │ 
    └────────┬────────┘
             │ 2. Package & Upload
             ↓
    ┌─────────────────────────────────────────┐
    │         AWS S3 Bucket                   │
    │  s3://artifacts/liberty/                │
    │  ├─ wlp-javaee8-26.0.0.1.zip (500MB)   │
    │  └─ liberty-feature-cache.tar.gz (18MB)│
    └────────┬────────────────────────────────┘
             │ 3. Build Base Image
             ↓
    ┌─────────────────────────────────────────┐
    │      Docker Build Process               │
    │  • Download from S3                     │
    │  • Extract Liberty runtime              │
    │  • Add feature cache                    │
    │  • Configure permissions                │
    └────────┬────────────────────────────────┘
             │ 4. Push to ECR
             ↓
    ┌─────────────────────────────────────────┐
    │         AWS ECR Repository              │
    │  126924000548.dkr.ecr.us-east-1/       │
    │    liberty/liberty-base:26.0.0.1        │
    │    liberty/liberty-base:latest          │
    │                                          │
    │  ✓ Contains: Liberty + Cached Features  │
    └─────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: APPLICATION BUILD (Development Teams - Daily Operations)            │
└──────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────┐
    │   Developer Pushes Code                  │
    │   • Application code                     │
    │   • server.xml (feature requirements)    │
    └────────┬────────────────────────────────┘
             │
             ↓
    ┌─────────────────────────────────────────┐
    │   CI/CD Pipeline (Jenkins/GitLab)        │
    │   Dockerfile:                            │
    │   FROM 126924000548...liberty-base       │
    │   COPY server.xml /config/               │
    │   COPY app.war /config/dropins/          │
    └────────┬────────────────────────────────┘
             │ Pull Base Image
             ↓
    ┌─────────────────────────────────────────┐
    │         AWS ECR Repository              │
    │  ✓ Liberty Base Image                   │
    │  ✓ Pre-cached Features                  │
    └────────┬────────────────────────────────┘
             │
             ↓
    ┌─────────────────────────────────────────┐
    │      Application Build                   │
    │  • Uses local feature cache              │
    │  • No IBM repository calls               │
    │  • installUtility: --from=/cache         │
    └────────┬────────────────────────────────┘
             │ ✅ Build Succeeds
             ↓
    ┌─────────────────────────────────────────┐
    │    Deployment (ECS/OpenShift/K8s)        │
    │  Application runs successfully           │
    └─────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────────┐
│ COMPARISON: BEFORE vs AFTER                                                   │
└──────────────────────────────────────────────────────────────────────────────┘

BEFORE (Current State - Fails monthly)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Application Build → installUtility → IBM Repository (FAILS 10th-15th) → ❌ Build Fails

AFTER (New Solution - Always works)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Application Build → installUtility → Local Cache in Base Image → ✅ Build Succeeds
```

---

## Component Details

### 1. Source Components

| Component | Description | Size | Update Frequency |
|-----------|-------------|------|------------------|
| **IBM Liberty Runtime** | Official WebSphere Liberty 26.0.0.1 | ~500MB | Monthly |
| **Feature Cache** | Pre-downloaded .esa feature archives | ~18MB | Monthly |
| **Liberty Features** | beanValidation, cdi, jaxrs, jdbc, jndi, jpa, mpMetrics, mpHealth | Included | Monthly |

### 2. Storage Layer

| Component | Purpose | Location |
|-----------|---------|----------|
| **S3 Bucket** | Centralized artifact storage | `s3://company-artifacts/liberty/` |
| **ECR Repository** | Docker image registry | `126924000548.dkr.ecr.us-east-1.amazonaws.com/liberty/liberty-base` |

### 3. Consumers

| Team/System | Usage | Frequency |
|-------------|-------|-----------|
| **Development Teams** | Pull base image for application builds | Daily |
| **CI/CD Pipelines** | Automated application builds | Per commit |
| **Middleware Team** | Base image maintenance | Monthly |

---

## Data Flow Diagram
```
┌────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW                                      │
└────────────────────────────────────────────────────────────────────────┘

Monthly Update Flow:
────────────────────
IBM → Download (1x/month) → S3 → Build → ECR → Application Builds (Daily)
      ↑                      ↑     ↑      ↑
      │                      │     │      │
   When new              Artifacts │   Container
   version              Storage    │    Registry
   released                      Build
                                Process


Application Build Flow (Daily):
────────────────────────────────
ECR → Pull Base Image → Add App Code → Build → Deploy
 ↑                         ↑
 │                         │
Pre-cached              No external
Features                dependencies
```

---

## Network Diagram
```
┌──────────────────────────────────────────────────────────────────┐
│                    NETWORK ARCHITECTURE                           │
└──────────────────────────────────────────────────────────────────┘

    Internet                    AWS Cloud (us-east-1)
    ────────                    ─────────────────────

┌─────────────┐
│IBM Repository│              ┌───────────────────────────────────┐
│(External)    │──────────────│  VPC: Build Environment           │
└──────────────┘              │                                   │
    │ Monthly only            │  ┌─────────────────┐              │
    │ (not during builds)     │  │  Build Agents   │              │
    │                         │  │  • Jenkins      │              │
    │                         │  │  • GitLab CI    │              │
    │                         │  └────────┬────────┘              │
    │                         │           │                       │
    │                         │           ↓                       │
    │                         │  ┌─────────────────┐              │
    │                         │  │   AWS ECR       │              │
    │                         │  │  (Private)      │              │
    │                         │  └────────┬────────┘              │
    │                         │           │                       │
    │                         │           ↓                       │
    │                         │  ┌─────────────────┐              │
    │                         │  │    AWS S3       │              │
    │                         │  │   (Private)     │              │
    │                         │  └─────────────────┘              │
    │                         │                                   │
    └─────────────────────────└───────────────────────────────────┘
                                      │
                                      │ All internal traffic
                                      │ No external calls during builds
                                      ↓
                               ┌─────────────────┐
                               │  ECS/OpenShift  │
                               │  (Production)   │
                               └─────────────────┘
```

---

## Security Architecture
```
┌──────────────────────────────────────────────────────────────────┐
│                    SECURITY MODEL                                 │
└──────────────────────────────────────────────────────────────────┘

Access Control:
───────────────

┌─────────────────────┐         ┌─────────────────────┐
│  Middleware Team    │         │ Development Teams   │
│  (Admin Access)     │         │  (Read Access)      │
└──────────┬──────────┘         └──────────┬──────────┘
           │                                │
           │ Upload/Update                  │ Pull Only
           ↓                                ↓
    ┌──────────────────────────────────────────┐
    │         AWS IAM Policies                 │
    │                                          │
    │  Middleware: s3:PutObject, ecr:Push     │
    │  DevTeams:   s3:GetObject, ecr:Pull     │
    └──────────┬───────────────────────────────┘
               │
               ↓
    ┌──────────────────────────────────────────┐
    │         Resources                         │
    │  • S3 Bucket (Private, Encrypted)        │
    │  • ECR Repository (Private, Scanned)     │
    └──────────────────────────────────────────┘

Image Scanning:
───────────────
ECR → Automated Scan → Vulnerability Report → Security Review
```

---

## Disaster Recovery
```
┌──────────────────────────────────────────────────────────────────┐
│                 DISASTER RECOVERY PLAN                            │
└──────────────────────────────────────────────────────────────────┘

Primary:           Backup:             Recovery:
────────          ────────            ──────────

ECR (us-east-1) → S3 (Source files) → Rebuild from S3
     ↓                 ↓                    ↓
  If corrupted    Always available    15 min RTO
     ↓                                     ↓
S3 Versioning  ←─────────────────→  Previous versions
  Enabled                              accessible
```

---

## Cost Analysis

| Component | Monthly Cost | Annual Cost |
|-----------|--------------|-------------|
| **S3 Storage** (~520MB) | $0.01 | $0.12 |
| **ECR Storage** (~1.5GB after builds) | $0.15 | $1.80 |
| **Data Transfer** (internal only) | $0.00 | $0.00 |
| **Maintenance Labor** (4 hrs/month) | $400 | $4,800 |
| **TOTAL** | **$400.16** | **$4,801.92** |

**ROI Analysis:**
- **Cost of downtime** (1 failed deploy/month): $50,000/year
- **Developer time saved** (no debugging failed builds): $25,000/year
- **Net benefit**: $70,198/year

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| S3 outage | Low | Medium | ECR image cached on build agents |
| ECR outage | Low | Medium | Rebuild from S3 within 15 minutes |
| Image corruption | Very Low | High | S3 versioning + automated testing |
| Unauthorized access | Low | High | IAM policies + ECR private + MFA |
| Liberty license issue | Very Low | Critical | Using official IBM downloads with accepted licenses |

---

## Success Metrics

### Current State (Problems):
- ❌ **Build failure rate**: 100% during IBM outages (10th-15th monthly)
- ❌ **Mean time to recovery**: 4-8 hours (wait for IBM)
- ❌ **Developer productivity**: Lost 40 hours/month
- ❌ **Deployment delays**: 1-2 days during outage window

### Target State (With Solution):
- ✅ **Build failure rate**: 0% (no external dependency)
- ✅ **Mean time to recovery**: 0 (no failures)
- ✅ **Developer productivity**: Restored
- ✅ **Deployment reliability**: 99.9% uptime

---

## Implementation Timeline
```
Week 1: Setup & Testing
├─ Day 1-2: Download Liberty, create S3 bucket
├─ Day 3-4: Build and test base image
└─ Day 5: Push to ECR, document process

Week 2: Pilot Deployment
├─ Day 1-2: Update 1-2 pilot applications
├─ Day 3-4: Monitor and validate
└─ Day 5: Review with Daniel's team

Week 3-4: Full Rollout
├─ Week 3: Update remaining applications (5-10/day)
└─ Week 4: Final validation, training, documentation

Validation: February 10-15 (During IBM maintenance window)
```

---

## Maintenance Procedure

### Monthly Update (When IBM releases new Liberty version):
```bash
# 1. Download new Liberty version
wget https://public.dhe.ibm.com/.../wlp-javaee8-{NEW_VERSION}.zip

# 2. Download features
./bin/installUtility download --location=./feature-cache ...

# 3. Upload to S3
aws s3 cp wlp-javaee8-{NEW_VERSION}.zip s3://artifacts/liberty/
aws s3 cp liberty-feature-cache-{NEW_VERSION}.tar.gz s3://artifacts/liberty/

# 4. Update Dockerfile version

# 5. Build and test
docker build -t liberty-with-deps:{NEW_VERSION} .

# 6. Push to ECR
docker push 126924000548...liberty-base:{NEW_VERSION}
docker push 126924000548...liberty-base:latest

# 7. Communicate to teams
```

**Time required**: 2-3 hours/month

---

## Approval Requirements

- [x] **Architecture Review**: Approved by Cloud Architecture Team
- [ ] **Security Review**: Pending review by InfoSec
- [ ] **Budget Approval**: Submitted to Finance ($4,802/year)
- [ ] **Change Management**: CAB approval for production deployment

---

## Contact & Support

| Role | Contact | Responsibility |
|------|---------|----------------|
| **Solution Owner** | Middleware Team | Base image maintenance |
| **Primary Contact** | [Your Name] | Implementation & support |
| **Escalation** | Daniel's Team Lead | Application integration |
| **Security** | InfoSec Team | Compliance & scanning |

---

## Appendix: Technical Specifications

### Base Image Details
- **OS**: Red Hat UBI 8
- **Java**: OpenJDK 11
- **Liberty Version**: 26.0.0.1
- **Image Size**: ~1.5GB
- **Image Layers**: 5 layers
- **Build Time**: ~2 minutes

### Pre-cached Features
- beanValidation-2.0
- cdi-2.0
- jaxrs-2.1
- jdbc-4.2
- jndi-1.0
- jpa-2.2
- mpMetrics-3.0
- mpHealth-3.0
- Plus 81 additional dependency features

### Compatibility
- ✅ OpenShift 4.x
- ✅ Kubernetes 1.20+
- ✅ ECS Fargate
- ✅ Docker 20.10+

---

**Document Version**: 1.0  
**Last Updated**: February 6, 2026  
**Next Review**: March 2026 (Post-validation)
