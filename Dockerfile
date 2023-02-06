FROM alpine:3.17.1
RUN apk update && \
apk upgrade && \
apk add curl jq nginx certbot certbot-nginx

