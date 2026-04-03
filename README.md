# 🚀 Ceph Tenacle
Automated Host Preparation for Ceph RGW (S3 Service)

# Run
Prepare Host Ceph
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/prepare_host_ubuntu2204.sh | sudo bash
```

Install Haproxy
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_haproxy.sh | sudo bash
```

Install Keepalived
```text
wget https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_keepalived.sh
chmod +x install_keepalived.sh
vi install_keepalived.sh
```
```text
bash install_keepalived.sh
```

Install Hashicorp Vault
```text
curl -sSL https://raw.githubusercontent.com/namenice/ceph-tentacle/main/install_hashicorp_vault.sh | sudo bash
```

