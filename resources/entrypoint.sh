#!/bin/bash

# start the sshd - always
/usr/sbin/sshd

#TG Config
AppRoot=/home/tigergraph/tigergraph/app
LogRoot=/home/tigergraph/tigergraph/log

check_myrole(){
  self_id=$(cat /proc/self/cgroup | head -1 | sed 's@.*/docker/@@g')
  self_conf=($(docker inspect ${self_id} | jq -r '.[0] | "\(.Name) \(.Image) \(.NetworkSettings.Networks | keys | first)"' | sed -e 's@^/@@g'))
  thename=$(echo ${self_conf[0]} | sed -e 's@_[0-9]\+$@@g')
  themaster=$(docker network inspect ${self_conf[2]} | \
    jq -r '.[0].Containers[] | select(.Name | contains("'${thename}'")) | "\(.Name)\/\(.IPv4Address)"' | sort | head -1 | awk -F "/" '{print $1}')
  my_role=$([ "${self_conf[0]}" == "${themaster}" ] && echo "master" || echo "worker")
}

build_config(){
  self_id=$(cat /proc/self/cgroup | head -1 | sed 's@.*/docker/@@g')
  self_conf=($(docker inspect ${self_id} | jq -r '.[0] | "\(.Name) \(.Image) \(.NetworkSettings.Networks | keys | first)"' | sed -e 's@^/@@g'))
  thename=$(echo ${self_conf[0]} | sed -e 's@_[0-9]\+$@@g')

  default_conf=$(cat /tmp/install_conf.json)
  LICENSE_KEY="${LICENSE_KEY:-$(echo "${default_conf}" | jq -r '.BasicConfig.License')}"

  server_config=$(docker network inspect ${self_conf[2]} | \
    jq -r '.[0].Containers[] | select(.Name | contains("'${thename}'")) | "\(.Name)\/\(.IPv4Address)"' | sort | \
    awk -F '/' '{print "\"m" NR ": " $2 "\""}' | \
    tr '\n' ',' | sed 's/,$/\n/')
  cfg_content=$(echo "${default_conf}" | jq ".BasicConfig.License=\"${LICENSE_KEY}\" | .BasicConfig.NodeList=[${server_config}]")
  echo "${cfg_content}" > ${EXTRACT_DIR}/install_conf.json
}

grace_shutdown(){
  check_myrole
  if [[ ${my_role} == "master" ]]; then
    su - tigergraph bash -c "${AppRoot}/cmd/gadmin stop all <<<y"
  fi

  kill -SIGTERM ${logtail_pid}

  echo "
  ============================================
         System gracefully shutted down       
  ============================================
  "
}

check_myrole
if [[ ${my_role} == "master" ]]; then
  if [[ ! -f ${AppRoot}/cmd/gadmin ]]; then
    # extract installer
    mkdir -p /tmp/install
    tar -xzvf /tmp/tigergraph-*.tar.gz -C /tmp/install/
    EXTRACT_DIR=/tmp/install/$(ls -trh /tmp/install | head -1)
    build_config
    # running the installer
    su - tigergraph bash -c "sudo ${EXTRACT_DIR}/install.sh -n -N -F"
  else
    su - tigergraph bash -c "${AppRoot}/cmd/gadmin status all > /dev/null 2>&1"
    if [ $? -ne 0 ]; then
      echo -n "Waiting all nodes to be up"
      for h in $(jq -r '.System.HostList[] | select(.ID != "m1") | .Hostname' $(find ${AppRoot} -name ".tg.cfg")); do
        while ! su - tigergraph bash -c "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null tigergraph@${h} 'uptime' > /dev/null 2>&1"; do
          sleep 1
          echo -n "."
        done
      done
      echo ""
      echo "All nodes up"
      su - tigergraph bash -c "${AppRoot}/cmd/gadmin start all"
    fi
  fi
else
  echo $my_role
  sudo rm -rf /tmp/*
fi

trap grace_shutdown SIGTERM

# show admin log
log_file=${LogRoot}/admin/ADMIN.INFO

while [[ ! -f "${log_file}" ]]; do
  echo "Waiting for installation"
  sleep 1
done

tail -f ${log_file} &
logtail_pid="$!"

wait ${logtail_pid}

