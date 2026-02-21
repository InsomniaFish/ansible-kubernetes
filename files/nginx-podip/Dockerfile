FROM nginx:1.27.0
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY default.conf /etc/nginx/conf.d/default.conf
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

