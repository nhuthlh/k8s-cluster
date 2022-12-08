#!/bin/bash
echo "Disabling swap...."
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Installing necessary dependencies...."
sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y

echo "Setting up hostname...."
sudo hostnamectl set-hostname "k8s-worker1"
IP_ADDRESS=`hostname -I|cut -d" " -f 1`
sudo echo "${IP_ADDRESS}  k8s-worker1" >> /etc/hosts

#Enable some kernel modules
cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF		

sudo modprobe overlay
sudo modprobe br_netfilter

#Setting networking for K8s
cat << EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

#Install containerd
sudo apt-get update && sudo apt-get install -y containerd
		
#Make a folder to keep configuration files
sudo mkdir -p /etc/containerd
			
#Generate the default config file
sudo containerd config default | sudo tee /etc/containerd/config.toml

#Restart the containerd to ensure the new config file is used.
sudo systemctl restart containerd
			
#Check the fstab file to confirm swap is disabled
sudo cat /etc/fstab

#Install K8s
sudo apt-get update && sudo apt-get install -y apt-transport-https curl

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io kubernetes-xenial main
EOF

sudo apt-get update

sudo apt-get install -y kubelet=1.25.0-00 kubeadm=1.25.0-00 kubectl=1.25.0-00
sudo apt-mark hold kubelet kubeadm kubectl
