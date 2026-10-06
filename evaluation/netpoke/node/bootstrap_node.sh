#!/bin/bash
# Runs ON a VM. Mirrors the authors' init_control.sh / init_worker.sh (Docker CE +
# cri-dockerd 0.3.1 + Kubernetes 1.29), minus Istio (not used by any experiment).
set -Eeuo pipefail
ROLE="${1:?control|worker}"
CRI_DOCKER_VER=0.3.1
K8S_MINOR=v1.29
K8S_PATCH=1.29.14           # the paper's version
export DEBIAN_FRONTEND=noninteractive
log(){ echo "[bootstrap:$(hostname)] $*"; }
# Safety net: if ANY command fails, say which one (v1 died silently on 4 nodes with no message).
trap 'rc=$?; echo "[bootstrap:$(hostname)] FAILED at line $LINENO (exit $rc): $BASH_COMMAND" >&2' ERR
# apt on a fresh cloud VM can collide with unattended-upgrades holding the lock: wait for it, never prompt.
APT="sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=300 -y"

log "swap off, kernel modules, sysctls"
sudo swapoff -a || true
sudo sed -i '/ swap / s/^/#/' /etc/fstab || true
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
sudo modprobe overlay; sudo modprobe br_netfilter
printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
sudo sysctl --system >/dev/null

log "base packages"
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
$APT update
$APT install ca-certificates curl gnupg wget apt-transport-https \
     tcpdump ethtool iproute2 bc gettext-base jq git \
     python3 python3-pip python3-yaml python3-matplotlib python3-progress screen

if ! command -v docker >/dev/null; then
  log "docker"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  $APT update
  $APT install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker "$USER" || true

if [ ! -x /usr/local/bin/cri-dockerd ]; then
  log "cri-dockerd $CRI_DOCKER_VER"
  cd /tmp
  wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKER_VER}/cri-dockerd-${CRI_DOCKER_VER}.amd64.tgz
  tar xf cri-dockerd-${CRI_DOCKER_VER}.amd64.tgz
  sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
  wget -q https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
  wget -q https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
  sudo mv cri-docker.socket cri-docker.service /etc/systemd/system/
  sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
  sudo systemctl daemon-reload
  sudo systemctl enable cri-docker.service
  sudo systemctl enable --now cri-docker.socket
fi

if ! command -v kubeadm >/dev/null; then
  log "kubernetes $K8S_PATCH"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  $APT update
  MAD="$(apt-cache madison kubeadm 2>&1 || true)"
  log "kubeadm versions apt can see (top 4):"; echo "$MAD" | head -n 4
  VER="$(echo "$MAD" | awk -v p="$K8S_PATCH" '$3 ~ "^"p && !f {print $3; f=1}' || true)"
  if [ -z "$VER" ]; then VER="$(echo "$MAD" | awk '!f && $3 != "" {print $3; f=1}' || true)"; log "WARN: $K8S_PATCH not in repo, using '${VER}'"; fi
  [ -n "$VER" ] || { log "ERROR: apt cannot see a kubeadm package. sources: $(cat /etc/apt/sources.list.d/kubernetes.list)"; apt-cache policy kubeadm; exit 1; }
  log "installing kubelet/kubeadm/kubectl = $VER"
  $APT install kubelet="$VER" kubeadm="$VER" kubectl="$VER"
  sudo apt-mark hold kubelet kubeadm kubectl
  sudo systemctl enable --now kubelet
fi

log "kernel qdisc modules (sch_plug is required by NetPoke)"
$APT install "linux-modules-extra-$(uname -r)" || log "WARN: linux-modules-extra-$(uname -r) not installable (see Day-0 checks)"
for m in sch_plug sch_netem sch_tbf; do sudo modprobe $m 2>/dev/null && log "module $m: loaded" || log "module $m: MISSING"; done
log "BOOTSTRAP OK"
