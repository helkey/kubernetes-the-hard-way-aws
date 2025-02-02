[//]: # (insert files: $ embedmd -w README.md)

# Kubernetes The Hard Way - AWS

Kubernetes is a powerful ecosystem for scaling cloud applications, but to
  [use it well](https://medium.com/@Instaclustr/anomalia-machina-7-kubernetes-cluster-creation-and-application-deployment-e10f19132809),
requires familiarity with a mixture of cloud computing (e.g. AWS), networking, security, linux, grid computing,
systems administration, resource management and performance engineering.
  
[Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way/) guide by Kelsey Hightower guides you through
manually building Kubernetes infrastrure for improved understanding. That project  originally supported both Google Cloud Platform (GCP)
and Amazon Web Services (AWS), but AWS support was later dropped.

This version of the project is based on [Slawekzachcial's fork)](https://github.com/slawekzachcial/kubernetes-the-hard-way-aws)
which continued support of AWS.

The intent of this project remains for learning about Kubernetes and AWS deployment,
while including the advantages of using Terraform and Packer to simplify configuration.
In addition, using Terraform and Packer significantly improves the speed at which resources can be launched,
allowing for faster testing.

Another goal of this project is to use Terraform to make the Kubernetes material more platform independant,
and more easily support AWS, GCP, and Microsoft Azure platforms (in future work).


## Labs

* [Prerequisites](#prerequisites)
* [Installing the Client Tools](#installing-the-client-tools)
* [Provisioning Compute Resources](#provisioning-compute-resources)
* [Provisioning a CA and Generating TLS Certificates](#provisioning-a-ca-and-generating-tls-certificates)
* [Generating Kubernetes Authentication Files for Authentication](#generating-kubernetes-authentication-files-for-authentication)
* [Generating the Data Encryption Config and Key](#generating-the-data-encryption-config-and-key)
* [Bootstrapping the etcd Cluster](#bootstrapping-the-etcd-cluster)
* [Bootstrapping the Kubernetes Control Plane](#bootstrapping-the-kubernetes-control-plane)
* [Bootstrapping the Kubernetes Worker Nodes](#bootstrapping-the-kubernetes-worker-nodes)
* [Configuring kubectl for Remote Access](#configuring-kubectl-for-remote-access)
* [Provisioning Pod Network Routes](#provisioning-pod-network-routes)
* [Deploying the DNS Cluster Add-on](#deploying-the-dns-cluster-add-on)
* [Smoke Test](#smoke-test)
* [Cleaning Up](#cleaning-up)

# Prerequisites

## Amazon Web Services

The commands below deploy Kubernetes cluster into [Amazon Web
Services](https://aws.amazon.com). I was able to run them using [AWS Free
Tier](https://aws.amazon.com/free/), at no cost.

## Amazon Web Services CLI

Install AWS CLI following instructions at https://aws.amazon.com/cli/.

# Installing the Client Tools

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-client-tools.md).

**OS X**: If you run into issues with `cfssl` install it using brew:

```sh
brew install cfssl
```

# Provisioning Compute Resources

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md)

## Networking

[embedmd]:# (terraform/variables.tf)

[embedmd]:# (terraform/aws_provider.tf)

## Load Balancer

[embedmd]:# (terraform/elb_aws.tf)

## Compute Instances

### SSH Key Pair

```sh
mkdir -p ssh

aws ec2 create-key-pair \
  --key-name kubernetes \
  --output text --query 'KeyMaterial' \
  > ssh/kubernetes.id_rsa
chmod 600 ssh/kubernetes.id_rsa
```

### Kubernetes Controller Image (Packer)
[embedmd]:# (packer/controller.json)
```json
{
    "variables": {
	"aws_access_key": "{{env `AWS_ACCESS_KEY_ID`}}",
	"aws_secret_key": "{{env `AWS_SECRET_ACCESS_KEY`}}",
	"db_password": "{{env `TF_VAR_db_password`}}"
    },
    "builders": [{
	"type": "amazon-ebs",
	"access_key": "{{user `aws_access_key`}}",
	"secret_key": "{{user `aws_secret_key`}}",
	"region": "us-west-1",
	"source_ami_filter": {
	    "filters": {
		"virtualization-type": "hvm",
		"name": "amzn2-ami-hvm-2.0.*-x86_64-gp2",
		"root-device-type": "ebs"
	    },
	    "owners": ["137112412989"],
	    "most_recent": true
	},
	"instance_type": "t2.micro",
	"ssh_username": "ec2-user",
	"ami_name": "ami-addr {{timestamp}}"
    }],
      "provisioners": [
      {
      // Encryption Config File
      "type": "file",
      "source": "cfg/encryption-config.yaml",
      "destination": "~/"
      },
	        "type": "file",
      "source": "kube-apiserver.service",
      "destination": "~/"
      },
          "type": "file",
      "source": "kube-controller-manager.service",
      "destination": "~/"
},
      "type": "file",
      "source": "kube-scheduler.service",
      "destination": "~/"
      },
    {	  
      "type": "shell",
      "inline": [
	  "sudo mv kube-apiserver.service kube-scheduler.service kube-controller-manager.service /etc/systemd/system/",
          "sudo systemctl daemon-reload",
	  "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
	  "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler"
      ]
    }]
}

```

### Kubernetes Worker Image (Packer)
[embedmd]:# (packer/worker.json)
```json
{
    "variables": {
	"aws_access_key": "{{env `AWS_ACCESS_KEY_ID`}}",
	"aws_secret_key": "{{env `AWS_SECRET_ACCESS_KEY`}}",
	"db_password": "{{env `TF_VAR_db_password`}}"
    },
    "builders": [{
	"type": "amazon-ebs",
	"access_key": "{{user `aws_access_key`}}",
	"secret_key": "{{user `aws_secret_key`}}",
	"region": "us-west-1",
	"source_ami_filter": {
	    "filters": {
		"virtualization-type": "hvm",
		"name": "amzn2-ami-hvm-2.0.*-x86_64-gp2",
		"root-device-type": "ebs"
	    },
	    "owners": ["137112412989"],
	    "most_recent": true
	},
	"instance_type": "t2.micro",
	"ssh_username": "ec2-user",
	"ami_name": "ami-addr {{timestamp}}"
    }],
      "provisioners": [
    {
      "type": "file",
      "source": "../ReqAddr",
      "destination": "/tmp/ReqAddr"
    },
    {	  
    "type": "shell",
      // Bootstrapping the Kubernetes Worker Nodes
      "inline": [
        "sudo apt-get update",
        "sudo apt-get -y install socat"
        "wget -q --show-progress --https-only --timestamping \
           https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
           https://github.com/containerd/cri-containerd/releases/download/v1.0.0-beta.1/cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz \
           https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl \
           https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-proxy \
           https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubelet",
	"sudo mkdir -p \
          /etc/cni/net.d \
          /opt/cni/bin \
          /var/lib/kubelet \
          /var/lib/kube-proxy \
          /var/lib/kubernetes \
          /var/run/kubernetes",
        "sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/",
        "sudo tar -xvf cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz -C /",
        "chmod +x kubectl kube-proxy kubelet",
        "sudo mv kubectl kube-proxy kubelet /usr/local/bin/"
      ]
    }]
}

```


### Instantiating Kubernetes Controllers

Using `t2.micro` instead of `t2.small` as `t2.micro` is covered by AWS free tier

```sh
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.1${i} \
    --user-data "name=controller-${i}" \
    --subnet-id ${SUBNET_ID} \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
  aws ec2 create-tags \
    --resources ${instance_id} \
    --tags "Key=Name,Value=controller-${i}"
done
```

### Instantiating Kubernetes Workers

```sh
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.2${i} \
    --user-data "name=worker-${i}|pod-cidr=10.200.${i}.0/24" \
    --subnet-id ${SUBNET_ID} \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
  aws ec2 create-tags \
    --resources ${instance_id} \
    --tags "Key=Name,Value=worker-${i}"
done
```

# Provisioning a CA and Generating TLS Certificates

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md)

## Certificate Authority

```sh
mkdir -p tls
```

```sh
cat > tls/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > tls/ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert -initca tls/ca-csr.json | cfssljson -bare tls/ca
```

## Client and Server Certificates

### Admin Client Certificate

```sh
cat > tls/admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -profile=kubernetes \
  tls/admin-csr.json | cfssljson -bare tls/admin
```

### Kubelet Client Certificates

```sh
for i in 0 1 2; do
  instance="worker-${i}"
  instance_hostname="ip-10-240-0-2${i}"
  cat > tls/${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance_hostname}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  internal_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PrivateIpAddress')

  cfssl gencert \
    -ca=tls/ca.pem \
    -ca-key=tls/ca-key.pem \
    -config=tls/ca-config.json \
    -hostname=${instance_hostname},${external_ip},${internal_ip} \
    -profile=kubernetes \
    tls/worker-${i}-csr.json | cfssljson -bare tls/worker-${i}
done
```

### kube-proxy Client Certificate

```sh
cat > tls/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -profile=kubernetes \
  tls/kube-proxy-csr.json | cfssljson -bare tls/kube-proxy
```

### Kubernetes API Server Certificate

```sh
cat > tls/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,ip-10-240-0-10,ip-10-240-0-11,ip-10-240-0-12,${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  tls/kubernetes-csr.json | cfssljson -bare tls/kubernetes
```

## Distribute the Client and Server Certificates

```sh
for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    tls/ca.pem tls/${instance}-key.pem tls/${instance}.pem \
    ubuntu@${external_ip}:~/
done
```

```sh
for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    tls/ca.pem tls/ca-key.pem tls/kubernetes-key.pem tls/kubernetes.pem \
    ubuntu@${external_ip}:~/
done
```

# Generating Kubernetes Authentication Files for Authentication

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/05-kubernetes-configuration-files.md)

## Client Authentication Configs

### Kubernetes Public IP Address

```sh
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[0].DNSName')
```

### The kubelet Kubernetes Configuration Files

```sh
mkdir -p cfg

for i in 0 1 2; do
  instance="worker-${i}"
  instance_hostname="ip-10-240-0-2${i}"
  bin/kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=tls/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config set-credentials system:node:${instance_hostname} \
    --client-certificate=tls/${instance}.pem \
    --client-key=tls/${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance_hostname} \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config use-context default \
    --kubeconfig=cfg/${instance}.kubeconfig
done
```

### The kube-proxy Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config set-credentials kube-proxy \
  --client-certificate=tls/kube-proxy.pem \
  --client-key=tls/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config use-context default \
  --kubeconfig=cfg/kube-proxy.kubeconfig
```

## Distribute the Kubernetes Configuration Files

```sh
for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    cfg/${instance}.kubeconfig cfg/kube-proxy.kubeconfig \
    ubuntu@${external_ip}:~/
done
```

# Generating the Data Encryption Config and Key

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/06-data-encryption-keys.md)

## The Encryption Key

```sh
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

## The Encryption Config File

```sh
cat > cfg/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

```sh
for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa cfg/encryption-config.yaml ubuntu@${external_ip}:~/
done
```

# Bootstrapping the etcd Cluster

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md)

SSH to controller-0, controller-1, controller-2 (replace `controller-N`
accordingly):

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

Execute on each controller:

```sh
```

```sh
ETCD_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)
echo "${ETCD_NAME}"
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
```

```sh
cat > etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv etcd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
```

```sh
ETCDCTL_API=3 etcdctl member list
```

# Bootstrapping the Kubernetes Control Plane

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/08-bootstrapping-kubernetes-controllers.md)

SSH to controller-0, controller-1, controller-2 (replace `controller-N`
accordingly):


```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

Execute on each controller:

```sh
sudo mkdir -p /var/lib/kubernetes/
sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --insecure-bind-address=127.0.0.1 \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-apiserver.service kube-scheduler.service kube-controller-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
```

```sh
kubectl get componentstatuses
```

## RBAC for Kubelet Authorization

SSH to controller-0:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

```sh
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
```

## The Kubernetes Frontend Load Balancer

Nothing to do - already setup in [previous section](#kubernetes-public-address)

# Bootstrapping the Kubernetes Worker Nodes

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/09-bootstrapping-kubernetes-workers.md)

SSH to worker-0, worker-1, worker-2 (replace `worker-N` accordingly):

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

Execute on each worker:

```sh
POD_CIDR=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^pod-cidr" | cut -d"=" -f2)
echo "${POD_CIDR}"

cat > 10-bridge.conf <<EOF
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat > 99-loopback.conf <<EOF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/
```

```sh
WORKER_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)
echo "${WORKER_NAME}"
```

```sh
sudo mv ${WORKER_NAME}-key.pem ${WORKER_NAME}.pem /var/lib/kubelet/
sudo mv ${WORKER_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo mv ca.pem /var/lib/kubernetes/

cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=cri-containerd.service
Requires=cri-containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --authorization-mode=Webhook \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --cloud-provider= \\
  --cluster-dns=10.32.0.10 \\
  --cluster-domain=cluster.local \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/cri-containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --pod-cidr=${POD_CIDR} \\
  --register-node=true \\
  --runtime-request-timeout=15m \\
  --tls-cert-file=/var/lib/kubelet/${WORKER_NAME}.pem \\
  --tls-private-key-file=/var/lib/kubelet/${WORKER_NAME}-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --cluster-cidr=10.200.0.0/16 \\
  --kubeconfig=/var/lib/kube-proxy/kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kubelet.service kube-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable containerd cri-containerd kubelet kube-proxy
sudo systemctl start containerd cri-containerd kubelet kube-proxy
```

# Configuring kubectl for Remote Access

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/10-configuring-kubectl.md)

## The Admin Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443
bin/kubectl config set-credentials admin \
  --client-certificate=tls/admin.pem \
  --client-key=tls/admin-key.pem
bin/kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin
bin/kubectl config use-context kubernetes-the-hard-way
```

## Verification

```sh
kubectl get componentstatuses
```

```sh
kubectl get nodes
```

# Provisioning Pod Network Routes

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/11-pod-network-routes.md)

## The Routing Table

```sh
for instance in worker-0 worker-1 worker-2; do
  instance_id_ip="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress]')"
  instance_id="$(echo "${instance_id_ip}" | cut -f1)"
  instance_ip="$(echo "${instance_id_ip}" | cut -f2)"
  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"
  echo "${instance_ip} ${pod_cidr}"

  aws ec2 create-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${pod_cidr}" \
    --instance-id "${instance_id}"
done
```

## Routes

The last command above (i.e. `aws ec2 create-route`) creates the route for each
worker.

```sh
aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query 'RouteTables[].Routes'
```

# Deploying the DNS Cluster Add-on

## The DNS Cluster Add-On

Run commands from [The DNS Cluster
Add-On section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/12-dns-addon.md)

# Smoke Test

## Data Encryption

Run commands from [Data Encryption
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#data-encryption)

Print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa \
  ubuntu@${external_ip} \
  "ETCDCTL_API=3 etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"
```

## Deployments

Run commands from [Deployments
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#deployments)

### Port Forwarding

Run commands from [Port Forwarding
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#port-forwarding)

### Logs

Run commands from [Logs
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#logs)

### Exec

Run commands from [Exec
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#exec)

## Services

Run commands from [Services
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#services)

To create a firewall rule that allows remote access to the `nginx` node port:

```sh
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')

aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port ${NODE_PORT} \
  --cidr 0.0.0.0/0
```

To retrieve the external IP address of a worker instance:

```sh
EXTERNAL_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
```

# Cleaning Up

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/14-cleanup.md)

Terraform makes resource cleanup  trivial
```sh
    terraform destroy
```


