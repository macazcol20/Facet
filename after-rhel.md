dnf install -y iproute-tc
firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=10250/tcp --permanent
firewall-cmd --reload
kubeadm init --pod-network-cidr=192.168.0.0/16


kubeadm init --pod-network-cidr=192.168.0.0/16 \
  --ignore-preflight-errors=SystemVerification


# as root
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

### Section 11: Setup Calico Network

see Link: [calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico-with-etcd-datastore)

```sh
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/tigera-operator.yaml

curl https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/custom-resources.yaml -O

kubectl create -f custom-resources.yaml

kubectl get pods -n calico-system
```

### get the pods

```sh
kubectl get nodes
kubectl get pods -n calico-system
```

kubeadm join 10.0.0.40:6443 --token n1hdi3.rueid4uh2eztadn6 \
        --discovery-token-ca-cert-hash sha256:d413284ea655766c091e7947ec54ff0016aa541b2210c548d241b295076f1ad2 

## give access to user        
```sh
# create kube dir for the user
install -d -m 700 -o cafanwii -g cafanwii /home/cafanwii/.kube

# copy the admin kubeconfig
cp -i /etc/kubernetes/admin.conf /home/cafanwii/.kube/config

# set ownership and safe perms
chown cafanwii:cafanwii /home/cafanwii/.kube/config
chmod 600 /home/cafanwii/.kube/config
```