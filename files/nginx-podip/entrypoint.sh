#!/bin/sh
set -e

POD_IP="${POD_IP:-$(hostname -i 2>/dev/null | awk '{print $1}')}"

cat > /usr/share/nginx/html/index.html <<EOF
pod ip: ${POD_IP}
EOF

exec "$@"

