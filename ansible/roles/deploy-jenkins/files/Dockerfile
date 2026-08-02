FROM jenkins/jenkins:lts

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg ansible \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && ansible-galaxy collection install community.docker ansible.posix

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

