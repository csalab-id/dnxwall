#!/bin/sh

rm -rf /etc/nginx/http.d/*
cat /data/conf.d/default.conf > /etc/nginx/http.d/default.conf
nginx
sleep 10

isnum() {
  awk -v a="$1" 'BEGIN {print (a == a + 0)}'
}

chkenv() {
  cat /data/container.json | jq -r '.Config.Env[]' | while read z; do
    if [[ "$(echo ${z} | grep 'DNXWALL_DSTPORT')" != "" ]]; then
      DSTPORT=$(echo "${z}" | cut -d "=" -f 2)
      if [[ "$(isnum ${DSTPORT})" == "1" ]]; then
        echo "DNXWALL_DSTPORT=${DSTPORT}" >> /data/export
      else
        echo "DNXWALL_DSTPORT=80" >> /data/export
      fi
    elif [[ "$(echo ${z} | grep 'DNXWALL_EMAIL')" != "" ]]; then
      EMAIL=$(echo "${z}" | cut -d "=" -f 2)
      if [[ "$EMAIL" =~ "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$" ]]; then
        echo "DNXWALL_EMAIL=${EMAIL}" >> /data/export
      else
        echo "DNXWALL_EMAIL=changeme@example.com" >> /data/export
      fi
    elif [[ "$(echo ${z} | grep 'DNXWALL_SSL')" != "" ]]; then
      SSL=$(echo "${z}" | cut -d "=" -f 2)
      if [ "${SSL}" = true ]; then
        echo "DNXWALL_SSL=true" >> /data/export
      else
        echo "DNXWALL_SSL=false" >> /data/export
      fi
    elif [[ "$(echo ${z} | grep 'DNXWALL_FORCE_SSL')" != "" ]]; then
      FORCE_SSL=$(echo "${z}" | cut -d "=" -f 2)
      if [ "${FORCE_SSL}" = true ]; then
        echo "DNXWALL_FORCE_SSL=true" >> /data/export
      else
        echo "DNXWALL_FORCE_SSL=false" >> /data/export
      fi
    fi
  done
  
  cat /data/export
  rm -rf /data/export
}

chkpem() {
  if [[ "${1}" == "true" ]]; then
    if [[ ! -f "/etc/letsencrypt/live/${2}/fullchain.pem" || ! -f "/etc/letsencrypt/live/${2}/privkey.pem" ]]; then
      # belum validasi cert jika expire (MISC)
      if [[ "${1}" == "true" ]]; then
        certbot certonly -d "${2}" -d "www.${2}" --no-eff-email --agree-tos -m "${3}" --nginx
      else
        certbot certonly -d "${2}" --no-eff-email --agree-tos -m "${3}" --nginx
      fi
    fi
  fi
}

curl --unix-socket /data/docker.sock http://localhost/containers/json -s | jq -r '.[].Id' | while read x; do
  data=$(curl --unix-socket /data/docker.sock http://localhost/containers/${x}/json -s -o /data/container.json)
  status=$(cat /data/container.json | jq -r '.State.Status')
  hostname=$(cat /data/container.json | jq -r '.Config.Hostname')
  cat /data/container.json | jq -r '.NetworkSettings.Networks[] | .IPAddress' | while read y; do
    if [[ "$y" != "" ]]; then
      if [[ "${status}" == "running" ]]; then
        if [[ "$(echo ${hostname} | grep '\.')" != "" ]]; then
          DNXWALL_DSTPORT="80"
          DNXWALL_EMAIL="changeme@example.com"
          DNXWALL_SSL="false"
          DNXWALL_FORCE_SSL="false"
          DNXWALL_FORCE_WWW="false"
          eval "$(chkenv)"
          chkpem "${DNXWALL_SSL}" "${hostname}" "${DNXWALL_EMAIL}" "${DNXWALL_FORCE_WWW}"
          echo "====================================================="
          echo "Email     : ${DNXWALL_EMAIL}"
          echo "Domain    : ${hostname}"
          echo "Dst IP    : ${y}"
          echo "Dst Port  : ${DNXWALL_DSTPORT}"
          echo "SSL       : ${DNXWALL_SSL}"
          echo "Force SSL : ${DNXWALL_FORCE_SSL}"
          if [[ "${DNXWALL_SSL}" == "false" ]]; then
            cat /data/conf.d/vhost.conf | \
            sed "s/gatexwallport/${DNXWALL_DSTPORT}/g" | \
            sed "s/gatexwallip/${y}/g" | \
            sed "s/gatexwalldomain/${hostname}/g" > /etc/nginx/http.d/${hostname}.conf
          elif [[ "${DNXWALL_SSL}" == "true" ]]; then
            if [[ "${DNXWALL_FORCE_SSL}" == "true" ]]; then
              cat /data/conf.d/vhost.conf | \
              sed "s/# if/if/g" | \
              sed "s/# listen/listen/g" | \
              sed "s/# ssl/ssl/g" | \
              sed "s/gatexwallport/${DNXWALL_DSTPORT}/g" | \
              sed "s/gatexwallip/${y}/g" | \
              sed "s/gatexwalldomain/${hostname}/g" > /etc/nginx/http.d/${hostname}.conf
            elif [[ "${DNXWALL_FORCE_SSL}" == "false" ]]; then
              cat /data/conf.d/vhost.conf | \
              sed "s/# listen/listen/g" | \
              sed "s/# ssl/ssl/g" | \
              sed "s/gatexwallport/${DNXWALL_DSTPORT}/g" | \
              sed "s/gatexwallip/${y}/g" | \
              sed "s/gatexwalldomain/${hostname}/g" > /etc/nginx/http.d/${hostname}.conf
            fi
          fi
          nginx -s reload
        fi
      fi
    fi
  done
done

echo "====================================================="
while true; do sleep 1000 ; done
# tail -f /var/log/nginx/*
