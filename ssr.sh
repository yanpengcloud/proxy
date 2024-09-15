#!/bin/bash
# shadowsocksR/SSR Ubuntu一键安装教程

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

V6_PROXY=""
IP=$(curl -sL -4 ip.sb)
if [[ "$?" != "0" ]]; then
    IP=$(curl -sL -6 ip.sb)
    V6_PROXY="https://gh.hijk.art/"
fi

FILENAME="ShadowsocksR-v3.2.2"
URL="${V6_PROXY}https://github.com/shadowsocksrr/shadowsocksr/archive/3.2.2.tar.gz"
BASE=$(pwd)
OS=$(hostnamectl | grep -i system | cut -d: -f2)

CONFIG_FILE="/etc/shadowsocksR.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ "$result" != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=$(lsb_release -d | grep -i ubuntu)
    if [ "$?" != "0" ]; then
        res=$(which apt)
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是Ubuntu"
            exit 1
        fi
    else
        result=$(lsb_release -d | grep -oE "[0-9.]+")
        main=${result%%.*}
        if [ $main -lt 16 ]; then
            colorEcho $RED " 不受支持的Ubuntu版本"
            exit 1
        fi
    fi
}

is_amazon() {
    # Example check for Amazon Linux
    if [[ $(lsb_release -a 2>/dev/null | grep -i amazon) ]]; then
        return 0
    else
        return 1
    fi
}

install_net_tools() {
    echo "Installing net-tools..."
    apt update
    apt install -y net-tools
}

getData() {
    PASSWORD="123111"
    PORT=$(shuf -i 1024-65535 -n 1)
    METHOD="aes-256-cfb"
    PROTOCOL="origin"
    OBFS="plain"
    
    echo ""
    colorEcho $BLUE " 密码： $PASSWORD"
    echo ""
    colorEcho $BLUE " 端口号： $PORT"
    echo ""
    colorEcho $BLUE " 加密方式： $METHOD"
    echo ""
    colorEcho $BLUE " 协议： $PROTOCOL"
    echo ""
    colorEcho $BLUE " 混淆模式： $OBFS"
    echo ""
}

preinstall() {
    colorEcho $BLUE " 更新系统"
    apt update
    apt autoremove -y
    res=$(which python3.8)
    if [ "$?" != "0" ]; then
        add-apt-repository -y ppa:deadsnakes/ppa
        apt update
        apt install -y python3.8
    fi
    ln -sf /usr/bin/python3.8 /usr/bin/python

    # Check and install net-tools if in Amazon environment
    if is_amazon; then
        install_net_tools
    fi
}

installSSR() {
    if [ ! -d /usr/local/shadowsocks ]; then
        colorEcho $BLUE " 下载安装文件"
        if ! wget --no-check-certificate -O ${FILENAME}.tar.gz ${URL}; then
            echo -e "[${RED}Error${PLAIN}] 下载文件失败!"
            exit 1
        fi

        tar -zxf ${FILENAME}.tar.gz
        mv shadowsocksr-3.2.2/shadowsocks /usr/local
        if [ ! -f /usr/local/shadowsocks/server.py ]; then
            colorEcho $RED " $OS 安装SSR失败，请到 https://hijk.art 网站反馈"
            cd ${BASE} && rm -rf shadowsocksr-3.2.2 ${FILENAME}.tar.gz
            exit 1
        fi
        cd ${BASE} && rm -rf shadowsocksr-3.2.2 ${FILENAME}.tar.gz
    fi

    cat > $CONFIG_FILE <<-EOF
{
    "server":"0.0.0.0",
    "server_ipv6":"::",
    "server_port":${PORT},
    "local_port":1080,
    "password":"${PASSWORD}",
    "timeout":600,
    "method":"${METHOD}",
    "protocol":"${PROTOCOL}",
    "protocol_param":"",
    "obfs":"${OBFS}",
    "obfs_param":"",
    "redirect":"",
    "dns_ipv6":false,
    "fast_open":false,
    "workers":1
}
EOF

    cat > /lib/systemd/system/shadowsocksR.service <<-EOF
[Unit]
Description=shadowsocksR
Documentation=https://hijk.art/
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
LimitNOFILE=32768
ExecStart=/usr/local/shadowsocks/server.py -c $CONFIG_FILE -d start
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocksR && systemctl restart shadowsocksR
    sleep 3
    res=$(ss -nltp | grep ${PORT} | grep python)
    if [ "${res}" = "" ]; then
        colorEcho $RED " $OS ssr启动失败，请检查端口是否被占用！"
        exit 1
    fi
}

setFirewall() {
    res=$(ufw status | grep -i inactive)
    if [ "$res" = "" ]; then
        ufw allow ${PORT}/tcp
        ufw allow ${PORT}/udp
    fi
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        colorEcho $BLUE " BBR模块已安装"
        INSTALL_BBR=false
        return
    fi

    res=$(hostnamectl | grep -i openvz)
    if [ "$res" != "" ]; then
        colorEcho $YELLOW " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $GREEN " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    apt install -y --install-recommends linux-generic-hwe-16.04
    grub-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    INSTALL_BBR=false
}

info() {
    port=$(grep server_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    res=$(ss -nltp | grep ${port} | grep python)
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    password=$(grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    method=$(grep method $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    protocol=$(grep protocol $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    obfs=$(grep obfs $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    
    p1=$(echo -n ${password} | base64 -w 0)
    p1=$(echo -n ${p1} | tr -d =)
    res=$(echo -n "${IP}:${port}:${protocol}:${method}:${obfs}:${p1}/?remarks=&protoparam=&obfsparam=" | base64 -w 0)
    res=$(echo -n ${res} | tr -d =)
    link="ssr://${res}"

    echo ============================================
    echo -e " ${BLUE}ssr运行状态：${PLAIN}${status}"
    echo -e " ${BLUE}ssr配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}ssr配置信息：${PLAIN}"
    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
    echo -e "   ${BLUE}加密方式(method)：${PLAIN} ${RED}${method}${PLAIN}"
    echo -e "   ${BLUE}协议(protocol)：${PLAIN} ${RED}${protocol}${PLAIN}"
    echo -e "   ${BLUE}混淆模式(obfs)：${PLAIN} ${RED}${obfs}${PLAIN}"
    echo -e " ${BLUE}链接地址：${PLAIN}${RED}${link}${PLAIN}"
    echo -e " ${BLUE}配置信息请保管好！${PLAIN}"
    echo ============================================
}

checkSystem
preinstall
getData
installSSR
setFirewall
installBBR
info

