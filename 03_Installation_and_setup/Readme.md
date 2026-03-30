Tools to use for Setup
<br>
-Docker Desktop-->I already have this installed
-Devbox-->it is dev environment which happens to be a wrapper for different dependencies,Devbox is a commandline tool that provides you an Isoltaed environment to work on

```
Course repo
https://github.com/sidpalas/devops-directive-kubernetes-course
```

```
devbox installation,I installed devbox with below command via terminal to my home(~) directory and did devbox init to begin 
curl -fsSL https://get.jetify.com/devbox | bash
```
-- run devbox init to initialize,when You want initialize the devbox in a new terminal just navigate to Kubernetes and type "devbox shell"
<br>
-- run devbox shell,to install required packages and open a new shell for you to work on.for this first time,note that this will take some time and in the future it would just
cache does dependencies
With Devbox,you can activate a particular shell system and deactivate it when you are done.
<br>
**KinD**
KinD stands for Kubernetes in Docker,KinD is a tool used to run local Kubernetes in Docker,thereby using Docker container as the node

![Screenshot 2025-12-06 at 1 55 12 PM](https://github.com/user-attachments/assets/ac3b0f75-902b-4e78-8f70-3b42f772f5fe)
<br>
Each node in KinD is a container,and it supports multiple nodes
<br>
So basically,I will setup a KinD cluster with a control plane and two worker nodes

**Aliases set below for my easy usage**
```
so basically i set the alises by identifying my current shell for config file and its zsh,
so I did 
# Open the file

and copied below and save and did source ~/.zshrc

k=kubectl
t=task
tl='task --list-all'
```

**About CIVO**
<br>
CIVO is a cloud native service provider that can be used for deploying Kubernetes in seconds,CIVO is CNCF(Cloud native computing foundation) certfied.
- CIVO is designed for rapid deployment of cloud native applications.
- CIVO has tools such as CIVO CLI and  Terraform.
- In CIVO you can create a free account $250 in credits valid for 1month and account must be verified before  Kubernetes cluster can be deployed.
- Finally credit usage can be tracked on CIVO dashboard
<br>

**Differences Btw CIVO and AWS**
<br>
Its important to note that AWS is already providing same services CIVO is providing,the difference is that CIVO is more simple and cheaper,useful for statups.While AWS is more complex,more secured basically for enterprise or big companies and its more expensive.
