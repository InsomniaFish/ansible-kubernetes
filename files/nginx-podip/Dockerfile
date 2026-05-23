FROM nginx:1.27.0

RUN apt-get update && apt-get install -y \
    iputils-ping \
    net-tools \
    iproute2 \
    curl \
    wget \
    telnet \
    dnsutils \
    tcpdump \
    netcat-traditional \
    traceroute \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY default.conf /etc/nginx/conf.d/default.conf
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

