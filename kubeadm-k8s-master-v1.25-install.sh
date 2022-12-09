sudo swapoff -a

echo "Setting up hostname...."
sudo hostnamectl set-hostname "k8s-master"
IP_ADDRESS=$(hostname -I|cut -d" " -f 1)
sudo echo "${IP_ADDRESS}  k8s-master" | sudo tee -a /etc/hosts

# Forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

sudo apt-get update
sudo apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Install containerd
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install containerd.io
sudo mkdir -p /etc/containerd
sudo bash -c 'containerd config default > /etc/containerd/config.toml'
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable containerd
sudo systemctl restart containerd

# Install kubeadm, kubelet and kubectl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt install -y kubeadm=1.25.0-00 kubelet=1.25.0-00 kubectl=1.25.0-00
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl start kubelet
sudo systemctl enable kubelet

# Remove missing `cni-dir` argument from kubelet if present
sed -i 's/KUBELET_ARGS=.*/KUBELET_ARGS=/' /etc/kubernetes/kubelet.env

#######################################################################
# Uncomment and change the advertise address accordingly if necessary #
#######################################################################
sudo kubeadm init --pod-network-cidr=10.244.0.0/16\
  --cri-socket unix:///run/containerd/containerd.sock\
  --apiserver-advertise-address=$IP_ADDRESS
  --kubernetes-version 1.25.0

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

sleep 5

kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-

# Install calico. Network is chosesn as `10.244.0.0/16` both in kubeadm and here to avoid
# overlap with other existing networks. Otherwise `192.168.0.0/16` can be used
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
curl -O https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
sed -i 's/cidr: 192.168.0.0\/16/cidr: 10.244.0.0\/16/' custom-resources.yaml
kubectl create -f custom-resources.yaml
