#!/bin/bash

# Variables
BR_IFACE="br0"
WAN_IFACE="eth0"
LAN_IFACE="eth1"
WIFI_IFACE="wlan0"
WIFI_SSID="setec_astronomy"
WIFI_PASSWORD="mypassword"

LAN_IP="192.168.200.1"
LAN_SUBNET="255.255.255.0"
LAN_DHCP_START="192.168.200.10"
LAN_DHCP_END="192.168.200.100"
LAN_DNS_SERVER="1.1.1.1"

DNSMASQ_CONF="tmp_dnsmasq.conf"
HOSTAPD_CONF="tmp_hostapd.conf"

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit
fi

if [ "$1" != "up" ] && [ "$1" != "down" ] || [ $# != 1 ]; then
    echo -e "missing required argument\n$0: <up/down>"
    exit
fi

SCRIPT_RELATIVE_DIR=$(dirname "${BASH_SOURCE[0]}")
cd $SCRIPT_RELATIVE_DIR

echo "[*] Stop router services"
killall wpa_supplicant
killall dnsmasq

echo "[*] Reset all network interfaces"
ifconfig $LAN_IFACE 0.0.0.0
ifconfig $LAN_IFACE down
ifconfig $BR_IFACE 0.0.0.0
ifconfig $BR_IFACE down
ifconfig $WIFI_IFACE 0.0.0.0
ifconfig $WIFI_IFACE down
brctl delbr $BR_IFACE

if [ "$1" == "up" ]; then
    echo "[*] Creating dnsmasq config file"
    cat << __EOF__ > $DNSMASQ_CONF
interface=${BR_IFACE}
dhcp-range=${LAN_DHCP_START},${LAN_DHCP_END},${LAN_SUBNET},12h
dhcp-option=6,${LAN_DNS_SERVER}
__EOF__

    echo "[*] Creating hostapd config file"
    cat << __EOF__ > $HOSTAPD_CONF
interface=${WIFI_IFACE}
bridge=${BR_IFACE}
ssid=${WIFI_SSID}
country_code=US
hw_mode=g
channel=11
wpa=2
wpa_passphrase=${WIFI_PASSWORD}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
ieee80211n=1
__EOF__
    #echo "ieee80211w=1" >> $HOSTAPD_CONF # PMF

    echo "[*] Bring up interfaces and bridge"
    ifconfig $WIFI_IFACE up
    ifconfig $WAN_IFACE up
    ifconfig $LAN_IFACE up
    brctl addbr $BR_IFACE
    brctl addif $BR_IFACE $LAN_IFACE
    ifconfig $BR_IFACE up

    echo "[*] Setup iptables"
    iptables --flush
    iptables -t nat --flush
    iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i $BR_IFACE -o $WAN_IFACE -j ACCEPT
    # optional mitm rules
    #iptables -t nat -A PREROUTING -i $BR_IFACE -p tcp -d 1.2.3.4 --dport 443 -j REDIRECT --to-ports 8081

    echo "[*] Setting static IP on bridge interface"
    ifconfig br0 inet $LAN_IP netmask $LAN_SUBNET

    echo "[*] Starting dnsmasq"
    dnsmasq -C $DNSMASQ_CONF

    echo "[*] Starting hostapd"
    hostapd $HOSTAPD_CONF
fi
