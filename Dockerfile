FROM ubuntu:16.04

ENV TG_VERSION 3.1.0

RUN echo "Adding tigergraph user" && \
  useradd -ms /bin/bash tigergraph

RUN echo "Updating & install deps package " && \
  apt-get -qq update && \
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections && \
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections && \
  apt-get install -y --no-install-recommends \
      sudo curl iproute2 net-tools cron ntp locales \
      vim emacs wget git tar unzip jq uuid-runtime \
      openssh-client openssh-server apt-transport-https \
      ca-certificates gnupg lsb-release iptables-persistent && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
       tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io && \
  usermod -aG docker tigergraph

COPY ./resources/* /tmp/

RUN echo "Setting root & tigergraph user" && \
  mkdir /var/run/sshd && \
  echo 'root:root' | chpasswd && \
  echo 'tigergraph:tigergraph' | chpasswd && \
  sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd && \
  echo "tigergraph    ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers && \
  mkdir -p /home/tigergraph/.ssh && \
  mv /tmp/id_rsa /home/tigergraph/.ssh/ && \
  chmod 600 /home/tigergraph/.ssh/id_rsa && \
  cat /tmp/id_rsa.pub >> /home/tigergraph/.ssh/authorized_keys && \
  cp /tmp/entrypoint.sh / && \
  chmod 755 /entrypoint.sh && \
  chown -R tigergraph:tigergraph /home/tigergraph && \
  chmod -R 777 /tmp/

RUN echo "Clean up apt cache" && apt-get clean -y

EXPOSE 22
EXPOSE 9000
EXPOSE 14240

HEALTHCHECK --interval=5s --timeout=10s --start-period=120s \  
    CMD curl --fail http://localhost:9000/echo || exit 1

#ENTRYPOINT tail -f /dev/null 2>&1
ENTRYPOINT /entrypoint.sh

