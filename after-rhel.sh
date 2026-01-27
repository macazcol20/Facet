#!/usr/bin/env bash
set -euo pipefail

# ====== Tunables ======
K8S_SERIES="v1.32"              # pkgs.k8s.io repo series (stable line)
K8S_VERSION="1.32.3"            # desired kube* version (rpm ends with -0)
CONTAINERD_VER="2.0.4"
RUNC_VER="1.2.6"
CNI_VER="1.6.2"

# ====== Pre-reqs ======
dnf -y install \
  curl wget tar iproute iptables ipvsadm conntrack-tools socat \
  ebtables ethtool device-mapper-persistent-data lvm2 \
  nftables \
  selinux-policy-base policycoreutils-python-utils \
  yum-utils

# Disable swap now and permanently
swapoff -a || true
sed -i.bak '/ swap / s/^/#/' /etc/fstab

# SELinux: permissive (simplest for lab)
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

# Load modules & sysctl
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# ====== containerd (manual install, distro-agnostic like your Ubuntu script) ======
cd /tmp
wget -q https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VER}/containerd-${CONTAINERD_VER}-linux-amd64.tar.gz
tar -C /usr/local -xzf containerd-${CONTAINERD_VER}-linux-amd64.tar.gz
rm -f containerd-${CONTAINERD_VER}-linux-amd64.tar.gz

# systemd unit for containerd
wget -q https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/lib/systemd/system
mv containerd.service /usr/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd

# runc
wget -q https://github.com/opencontainers/runc/releases/download/v${RUNC_VER}/runc.amd64 -O /usr/local/sbin/runc
chmod +x /usr/local/sbin/runc

# CNI plugins
mkdir -p /opt/cni/bin
wget -q https://github.com/containernetworking/plugins/releases/download/v${CNI_VER}/cni-plugins-linux-amd64-v${CNI_VER}.tgz
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v${CNI_VER}.tgz
rm -f cni-plugins-linux-amd64-v${CNI_VER}.tgz

# containerd config (SystemdCgroup=true)
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# flip SystemdCgroup to true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# cri-tools (crictl)
CRI_VER="v1.32.0"
wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRI_VER}/crictl-${CRI_VER}-linux-amd64.tar.gz
tar -C /usr/local/bin -xzf crictl-${CRI_VER}-linux-amd64.tar.gz
rm -f crictl-${CRI_VER}-linux-amd64.tar.gz
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# ====== Kubernetes repo (pkgs.k8s.io) ======
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_SERIES}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_SERIES}/rpm/repodata/repomd.xml.key
EOF

# Install kubelet/kubeadm/kubectl
dnf -y makecache
# Try to pin version; rpm suffix is usually "-0"
dnf -y install kubelet-${K8S_VERSION}-0 kubeadm-${K8S_VERSION}-0 kubectl-${K8S_VERSION}-0 || \
dnf -y install kubelet kubeadm kubectl

# Lock versions to avoid surprise upgrades
dnf -y install 'dnf-command(versionlock)'
dnf versionlock add kubelet kubeadm kubectl

# Kubelet will start after kubeadm init
systemctl enable kubelet

# ====== Firewalld (open minimal master ports) ======
if systemctl is-active --quiet firewalld; then
  firewall-cmd --add-port=6443/tcp --permanent   # kube-apiserver
  firewall-cmd --add-port=2379-2380/tcp --permanent # etcd (local)
  firewall-cmd --add-port=10250/tcp --permanent  # kubelet
  firewall-cmd --add-port=10257/tcp --permanent  # kube-controller-manager
  firewall-cmd --add-port=10259/tcp --permanent  # kube-scheduler
  firewall-cmd --reload
fi

echo "===== Prep complete. Next: kubeadm init + CNI (Calico) ====="

# ====== (Optional) kubeadm init right away ======
# Adjust the CIDR to match your CNI. Your notes used 192.168.0.0/16.
# kubeadm init --pod-network-cidr=192.168.0.0/16

# After init, set up kubeconfig for the current (root) user:
#   mkdir -p $HOME/.kube
#   cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#   chown $(id -u):$(id -g) $HOME/.kube/config
#
# Then install Calico (same commands you used previously):
#   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml
#   curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/custom-resources.yaml
#   kubectl create -f custom-resources.yaml
#
# Verify:
#   kubectl get nodes
#   kubectl get pods -n calico-system
