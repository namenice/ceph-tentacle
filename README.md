# 🚀 Ceph Tenacle
Automated Host Preparation for Ceph RGW (S3 Service)

# Run
Prepare Host Ceph
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/prepare_host_ubuntu2204.sh | sudo bash
```
---
Install Haproxy
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_haproxy.sh | sudo bash
```
Destroy Haproxy
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/destroy_haproxy.sh | sudo bash
```
---
Install Keepalived
```text
wget https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_keepalived.sh
chmod +x install_keepalived.sh
vi install_keepalived.sh
```
```text
bash install_keepalived.sh
```
---

Install Hashicorp Vault Server
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_hashicorp_vault.sh | sudo bash
```
Install Hashicorp Vault Agent
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_hashicorp_vault_agent.sh | sudo bash
```
Destroy Hashicorp Vault Server
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_hashicorp_vault_server.sh | sudo bash
```
Destroy Hashicorp Vault Agent
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_hashicorp_vault_agent.sh | sudo bash
```


