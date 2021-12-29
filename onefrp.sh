#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --email)
                email="$2"
                shift
                shift
                ;;
            --number)
                docker_num="$2"
                shift
                shift
                ;;
            --debug-output)
                set -x
                shift
                ;;
            *)
                error "Unknown argument: $1"
                display_help
                exit 1
        esac
    done
}

mk_swap() {
    #检查是否存在swapfile
    grep -q "swapfile" /etc/fstab

    #如果不存在将为其创建swap
    if [ $? -ne 0 ]; then
        mem_num=$(awk '($1 == "MemTotal:"){print $2/1024}' /proc/meminfo|sed "s/\..*//g"|awk '{print $1*2}')
        echo -e "${Green}swapfile未发现，正在为其创建swapfile${Font}"
        fallocate -l ${mem_num}M /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >> /etc/fstab
            echo -e "${Green}swap创建成功，并查看信息：${Font}"
            cat /proc/swaps
            cat /proc/meminfo | grep Swap
    else
        echo -e "${Red}swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！${Font}"
    fi
    
}

del_swap(){
    #检查是否存在swapfile
    grep -q "swapfile" /etc/fstab

    #如果存在就将其移除
    if [ $? -eq 0 ]; then
        echo -e "${Green}swapfile已发现，正在将其移除...${Font}"
        sed -i '/swapfile/d' /etc/fstab
        echo "3" > /proc/sys/vm/drop_caches
        swapoff -a
        rm -f /swapfile
        echo -e "${Green}swap已删除！${Font}"
    else
        echo -e "${Red}swapfile未发现，swap删除失败！${Font}"
    fi
}

#检查docker程序是否存在不存在就安装
install_docker() {
    if which docker >/dev/null; then
        echo "Docker has been installed, skipped"
    else
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        check_docker_version=$(docker version &>/dev/null; echo $?)
        if [[ $check_docker_version -eq 0 ]]; then
            echo "Docker installed successfully."
        else
            echo "Docker install failed."
            exit 1
        fi
        systemctl enable docker || service docker start
        rm get-docker.sh
    fi
}

#判断防火墙
if_waf() {
    firewalld_a=$(systemctl status firewalld | grep "Active:" | awk '{print $2}')
    iptables_a=$(systemctl status firewalld | grep "Active:" | awk '{print $2}')
    if [ $firewalld_a = active ]; then
        echo "firewalld stoping"
        systemctl stop firewalld &>/dev/null
        echo "firewalld stop!"
    fi
    if [ $iptables_a = active ]; then
        echo "iptables stoping"
        systemctl stop iptables &>/dev/null
        echo "iptables stop!"
    fi
}
clear

stop_docker() {
    docker stop `docker ps -aq`
}

rm_docker() {
    docker rm `docker ps -aq`
}

start_all_docker() {
    docker start `docker ps -aq`
}

show_input() {
    #定义数据
    read -p "Your Mail:" email 
    read -p "Docker Num:" docker_num 

    clear

    #数据展示
    echo "The email you entered:"$email
    echo "Docker Num:":$docker_num
}

init_install() {
    # 清楚屏幕内容
    clear
    # 添加SWAP
    mk_swap
    # 安装Docker
    install_docker
    # 默认关闭防火墙
    if_waf
    clear
    echo "请自行添加docker节点"
}


init_frps() {
    # 初始化FPR服务端
    read -p "请输入Frp服务端版本【留空默认安装最新版】:" ver
    read -p "请输入Frp服务端对接TOKEN【留空默认freefrp.net】:" token
    read -p "请输入Frp服务端管理用户名【留空默认admin】:" username
    read -p "请输入Frp服务端管理密码【留空默认admin】:" password
    read -p "请输入Frp服务端WEB管理端口【留空默认7500】:" web_port
    read -p "请输入Frp服务端对接端口【留空默认7000】:" server_port

    clear
    # 查看参数是否默认



    #数据展示
    echo "Frp服务端对接TOKEN:"$token
    echo "Frp服务端管理用户名:"$username
    echo "Frp服务端管理密码:"$password
    echo "Frp服务端WEB管理端口:"$web_port
    echo "Frp服务端对接端口:"$server_port

    # --restart=on-failure只在容器非正常退出时（退出状态非0），才会重启容器
    # --restart=always,如需一直自动启动，则甚至为always
    # 创建frp配置存放目录
    mkdir /usr/local/frp
    # -v /usr/local/frp/frps.ini:/frp/frps.ini
    # 端口映射 -p 7000:7000 -p 7500:7500
    docker run --name frps -d --restart=on-failure -v /usr/local/frp/frps.ini:/frp/frps.ini -p $server_port:7000 -p $web_port:7500 -e type=server -e token=$token -e username=$username -e password=$password aricross/frp_docker
}

init_frpc() {
    # 初始化FPR客户端
    read -p "请输入Frp客户端版本【留空默认安装最新版】:" ver
    read -p "请输入Frp服务端服务器地址【留空默认frp.freefrp.net】:" frps_addr 
    read -p "请输入Frp服务端对接TOKEN【留空默认freefrp.net】:" token
    read -p "请输入Frp服务端对接端口【留空默认7000】:" frps_port

    clear

    #数据展示
    echo "Frp服务端服务器地址:"$frps_addr
    echo "Frp服务端对接TOKEN:"$token
    echo "Frp服务端对接端口:"$frps_port
    docker run --name frpc -d --restart=on-failure -e type=client -e token=$token -e frps_addr=$frps_addr -e token=$token -e frps_port=$frps_port aricross/frp_docker
}

init_frp() {
    # 初始化FPR服务端及客户端
    read -p "请输入Frp版本【留空默认安装最新版】:" ver
    read -p "请输入Frp对接TOKEN【留空默认freefrp.net】:" token
    echo "#######################服务端配置#######################"
    read -p "请输入Frp服务端管理用户名【留空默认admin】:" username
    read -p "请输入Frp服务端管理密码【留空默认admin】:" password
    read -p "请输入Frp服务端WEB管理端口【留空默认7500】:" web_port
    read -p "请输入Frp服务端对接端口【留空默认7000】:" server_port
    read -p "请输入Frp服务端对接端口【留空默认7000】:" frps_port
    echo "#######################客户端配置#######################"

    clear

    #数据展示
    echo "Frp版本:"$ver
    echo "Frp对接Token:"$token
    echo "#######################服务端配置#######################"
    echo "Frp服务端管理用户名:"$username
    echo "Frp服务端管理密码:"$password
    echo "Frp服务端WEB管理端口:"$web_port
    echo "Frp服务端对接端口:"$server_port

    echo "#######################客户端配置#######################"
    echo "Frp服务端服务器地址:"$frps_addr
    echo "Frp服务端对接端口:"$frps_port
    read -p "请检查以上参数是否正确，按任意键确认，Ctrl+C退出脚本重新配置:" comfirm
    docker run --name frp -d --restart=on-failure -e type=all -e token=$token -e frps_addr=$frps_addr -e token=$token -e frps_port=$frps_port aricross/frp_docker
}

start_docker() {
    #循环启动docker
    for ((i=1;i<=$docker_num;i++))
    do
        docker run -d --restart=on-failure -e DOCKER_ID=a$i -e email=$email luckysdream/p2pclient2
    done
}


show_menu() {
    echo -e "
  ${green}FRP一键部署脚本

  ${green}0.${plain} 退出脚本
————————————————
  ${green}1.${plain} 初始化安装Docker
  ${green}2.${plain} Docker安装并运行FPR服务端
  ${green}2.${plain} Docker安装并运行FPR客户端
  ${green}2.${plain} Docker安装并运行FPR服务端及客户端
  ${green}3.${plain} 删除所有Docker【慎用！！！】
————————————————
  ${green}4.${plain} 添加节点并启动
  ${green}5.${plain} 防火墙检测
  ${green}6.${plain} SWAP检测
  ${green}7.${plain} 删除SWAP
 "
    echo && read -p "请输入选择 [0-7]: " num

    case "${num}" in
        0) exit 0
        ;;
        1) init_install
        ;;
        2) start_all_docker
        ;;
        3) stop_docker && rm_docker
        ;;
        4) show_input  && start_docker
        ;;
        5) if_waf
        ;;
        6) mk_swap
        ;;
        7) del_swap
        ;;
        *) echo -e "${red}请输入正确的数字 [0-7]${plain}"
        ;;
    esac
}


if [[ $# > 0 ]]; then
    parse_args "$@"
    init_install
    start_docker
else
    show_menu
fi