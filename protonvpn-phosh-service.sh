#!/bin/bash

## Script to monitor and manage a protonvpn connection when using a phosh environment
#
## Version 1.0.0.1
## Working import and up commands
#
# Upstream-Name: berb-protonvpn-phosh-service
# Source: https://github.com/berbascum/berb-protonvpn-phosh-service
#
# Copyright (C) 2024 Berbascum <berbascum@ticv.cat>
# All rights reserved.
#
# BSD 3-Clause License
#
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Log
LOG_DIR="${HOME}/logs"
[ -d "${LOG_DIR}" ] || mkdir ${LOG_DIR}
LOG_FILE="protonvpn-phosh-service.log"
echo "$(date +'%Y-%m-%d %H:%M:%S') Executing droidian-berb-fix-appstreamcli-apt-glib-stdout..." | tee -a "${LOG_DIR}/${LOG_FILE}"

## Load user config
protonvpn_config_file="$HOME/.config/proton-me/protonvpn-phosh-service.conf"
[ -e "${protonvpn_config_file}" ] || echo "Missing ${protonvpn_config_file}"
source ${protonvpn_config_file}

## NM /Connections dir:
#/etc/NetworkManager/system-connections/protonvpn.tcp-1.nmconnection 
## DBUS doc
## (D-Bus active path sample:
## /org/freedesktop/NetworkManager/ActiveConnection/7)

###############
## Functions ##
###############

con_proton_check() {
    unset con_is_active con_dbus_path con_state con_type con_vpn_type
    con_found=$(nmcli con show \
        | grep ${VPN_CON_NAME})
    [ -z "${con_found}" ] && return
        #&& echo "Connection not previously exist" \
        #&& return
    con_is_active=$(nmcli connection show --active \
        | grep -c "^${VPN_CON_NAME} ")
    [ "${con_is_active}" -eq "0" ] && return
    con_dbus_path="$(nmcli -t -f GENERAL.DBUS-PATH \
        connection show ${VPN_CON_NAME} \
        | awk -F':' '{print $2}')"
    con_state=$(nmcli con show ${VPN_CON_NAME} \
        | grep '^GENERAL.STATE' \
        | awk '{print $2}')
    con_type=$(nmcli con show ${VPN_CON_NAME} \
        | grep '^connection.type:' \
        | awk '{print $2}')
    con_vpn_type=$(nmcli con show ${VPN_CON_NAME} \
        | grep '^vpn.service-type' \
        | awk -F'.' '{print $NF}')
}

con_proton_import() {
    ## Check connection
    con_proton_check
    if [ -n "${con_found}" ]; then
        ## Con status
        [ "${con_state}" == "activated" ] \
            && echo "Con exist and is up" && exit 1
        ## Ask Del previous connection if exist
        msg="Del existing con? [ y | any ]: "
        read -p  "${msg}" answer
        case "${answer}" in
            y)
                nmcli connection delete ${VPN_CON_NAME}
                ;;
            *)
                echo "Canceled by user"
                exit 2
        esac
    fi

    ## Import connection
    nmcli connection import type openvpn \
        file "${VPN_CON_FILE}"
    ## Set con username
    nmcli connection mod ${VPN_CON_NAME} \
        vpn.user-name "${VPN_USER_NAME}"
    ## Set con password-flags=0
    # password-flags:
      # 0>Disable ask and keyring use
      # 1>Allways ask for password
      # 0>Ask pwd 1st time, then use keyring?
    nmcli connection mod ${VPN_CON_NAME} \
        +vpn.data "password-flags=0"
    ## Set con user pass
    nmcli connection mod ${VPN_CON_NAME} \
        vpn.secrets "password=$(cat ${VPN_P_FILE})"
}


## Connect to protonvpn
con_proton_up() {
    ## Check proton conection
    con_proton_check
    ## Con exist
    [ -z "${con_found}" ] \
        && echo "Connection not exist" && exit 1
    ## Con status
    [ "${con_state}" == "activated" ] \
        && echo "Connection already up" && exit 1
    ## Check for internet connection
    connected_inet="false"
    while [ "$connected_inet" != "true" ]; do
        echo && echo "Waiting for inet connection..." | tee -a ${LOG_DIR}/${LOG_FILE}
        ping -c 1 8.8.8.8 > /dev/null 2>&1 \
            && connected_inet="true"
        sleep 5
    done
    echo && echo "Internet cnnection detected!" | tee -a ${LOG_DIR}/${LOG_FILE}
    ## Start connection
    echo && echo "Starting ProtonVPN connection ..." | tee -a ${LOG_DIR}/${LOG_FILE}
    nmcli connection up "${VPN_CON_NAME}"
    sleep 5

    connected_vpn="false"
    while [ "$connected_vpn" != "true" ]; do
        echo && echo "Waiting for vpn connection..." | tee -a ${LOG_DIR}/${LOG_FILE}
        ## Check proton conection
        con_proton_check
        [ "${con_state}" == "activated" ] \
            && connected_vpn="true"
        sleep 5
    done
    ## Apply iptables rules
    echo && echo "Applying itables rules..." | tee -a ${LOG_DIR}/${LOG_FILE}
    sudo /usr/sbin/firewall-droidian-berb-proton.sh
}

action_required() {
    echo ""
    echo "An action is required:"
    echo " import up"
    exit 10
}

if [ "$1" == "import" ]; then
    con_proton_import
elif [ "$1" == "up" ]; then
    con_proton_up
else
    action_required
fi

exit 0
