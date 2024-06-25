# Pool Server Preparation

the debian 11/12 system must be prepared for ssh access and github access. on a fresh install of debian 11/12
the ssh-packet has to be selected.


## SSH-Access on github

### create a github compatible ssh key

```BASH
ssh-keygen -f ~/.ssh/github -t ed25519 -N ''
cat <<EOF > /root/.ssh/config
Host github.com
  Hostname github.com
  IdentityFile ~/.ssh/github
EOF
```

### Deploy key on github

Sign in on github as rolix-it. Append the key from `~/.ssh/github` to the ssh keys under settings.

## Software deployment

```BASH
wget https://raw.githubusercontent.com/mietkamera/prep_servers/development/init-poolserver.sh
chmod +x init-poolserver.sh
uname -r

```
