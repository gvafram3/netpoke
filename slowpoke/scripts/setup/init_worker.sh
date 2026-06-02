#!/bin/bash
CRI_DOCKER_VER=0.3.1

docker_install () {
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get -y install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
}

cri_dockerd_install () {
    wget https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKER_VER}/cri-dockerd-${CRI_DOCKER_VER}.amd64.tgz
    tar xvf cri-dockerd-${CRI_DOCKER_VER}.amd64.tgz
    sudo mv cri-dockerd/cri-dockerd /usr/local/bin/

    wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
    wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
    sudo mv cri-docker.socket cri-docker.service /etc/systemd/system/
    sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

    sudo systemctl daemon-reload
    sudo systemctl enable cri-docker.socket cri-docker.service
    sudo systemctl enable --now cri-docker.socket
    sudo systemctl enable --now cri-docker.service
}

kube_install () {
    sudo apt-get update
    # apt-transport-https may be a dummy package; if so, you can skip that package
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    # Non-interactive key install (gcloud ssh has no TTY; "sudo gpg" fails with /dev/tty errors)
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
      | gpg --dearmor --yes 2>/dev/null \
      | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null
    # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl kubelet kubeadm
    sudo systemctl enable kubelet
}

# Required for kubeadm join preflight (matches control-node networking).
k8s_node_sysctl () {
    sudo modprobe overlay || true
    sudo modprobe br_netfilter || true
    cat <<'EOF' | sudo tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system
}

wait_for_cri () {
    local i
    for i in $(seq 1 30); do
        if [[ -S /var/run/cri-dockerd.sock ]]; then
            return 0
        fi
        sleep 2
    done
    echo "ERROR: cri-dockerd socket not ready" >&2
    sudo systemctl status cri-docker.service --no-pager || true
    return 1
}

docker_install
cri_dockerd_install
kube_install
k8s_node_sysctl
sudo swapoff -a
sudo systemctl restart docker
sudo systemctl restart cri-docker.service
wait_for_cri
sudo systemctl restart kubelet || true
