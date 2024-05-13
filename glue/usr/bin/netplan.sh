#!/bin/bash

if [ "${1}" =  "-h" ]; then
  echo -e "Reload netplan config and apply the changes"
  echo -e "$ sudo ${0} [interface name]"
  echo -e "Interface name is optional, otherwise all the interfaces are reloaded"
fi

if [ "0" != "${UID}" ]; then
  echo "This must be run as root"
  exit 0
fi

if [ ! "${1}" = "generate" ] && [ ! "${1}" = "apply" ]; then
  interface="${1}"
fi

echo "Removing netplan stamp"
rm /run/systemd/generator/netplan.stamp

echo "Reloading daemons..."
systemctl daemon-reload

if [ -n "${interface}" ]; then
  echo "Reconfiguring network..."
  networkctl reconfigure ${interface}
else
  echo "Restarting systemd-networkd..."
  systemctl restart systemd-networkd
fi

if [ -n "${interface}" ]; then
  if ls /run/systemd/system/netplan-wpa-${interface}.service 1> /dev/null 2>&1; then
    echo "Restarting netplan-wpa-${interface} services..."
    systemctl restart netplan-wpa-${interface}.service
  fi
else
  if ls /run/systemd/system/netplan-wpa-*.service 1> /dev/null 2>&1; then
    echo "Restating all netplan-wpa* services"
    systemctl restart netplan-wpa*.service
  fi
fi
