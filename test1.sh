#!/usr/bin/env bash
rm -f $0

# 安装必要工具
if ! command -v curl &> /dev/null; then
    yum install -y curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null 2>&1
fi

# 配置文件路径
CONFIG_FILE="/etc/sk5/sk5_configs.txt"

# 菜单显示函数
show_menu() {
    clear
    echo "###############################################################"
    echo "#            Socks5 代理管理工具                               #"
    echo "###############################################################"
    echo "#  1. 安装 Socks5 代理                                        #"
    echo "#  2. 卸载 Socks5 代理                                        #"
    echo "#  3. 查看代理配置信息                                         #"
    echo "#  4. Bug反馈                                                 #"
    echo "#  5. 退出                                                    #"
    echo "###############################################################"
    echo
}

# 卸载函数
uninstall_sk5() {
    clear
    echo ">>> 正在卸载 Socks5 代理服务..."
    
    # 停止服务
    systemctl stop sk5 >/dev/null 2>&1
    systemctl disable sk5 >/dev/null 2>&1
    
    # 删除文件
    rm -f /usr/local/bin/sk5
    rm -rf /etc/sk5
    rm -f /etc/systemd/system/sk5.service
    rm -f $CONFIG_FILE
    
    # 重载系统服务
    systemctl daemon-reload >/dev/null 2>&1
    
    # 防火墙规则
    iptables -F >/dev/null 2>&1
    iptables -X >/dev/null 2>&1
    iptables -t nat -F >/dev/null 2>&1
    iptables -t mangle -F >/dev/null 2>&1
    
    echo ">>> Socks5 代理服务已成功卸载!"
    echo
    read -p "按回车键返回主菜单..." -r
}

# 查看代理配置信息函数
view_configs() {
    clear
    echo "###############################################################"
    echo "#               Socks5 代理配置信息                           #"
    echo "###############################################################"
    echo
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ">>> 未找到代理配置信息!"
        echo ">>> 请先安装 Socks5 代理服务"
        echo
        read -p "按回车键返回主菜单..." -r
        return
    fi

    echo "【标准连接格式：公网地址/端口/账号/密码】"
    echo "---------------------------------------"
    while read -r line; do
        arr=($line)
        local_ip=${arr[0]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        public_ip=${arr[4]}
        # 按照你要求格式输出
        echo "${public_ip}/${port}/${user}/${pass}"
    done < "$CONFIG_FILE"
    
    echo
    read -p "按回车键返回主菜单..." -r
}

# Bug反馈函数
bug_feedback() {
    clear
    echo "###############################################################"
    echo "#                    Bug 反馈                                 #"
    echo "###############################################################"
    echo
    
    while true; do
        read -e -p "请输入您的问题描述: " feedback
        if [ -z "$feedback" ]; then
            echo "错误：反馈内容不能为空!"
            continue
        fi
        break
    done
    
    while true; do
        read -e -p "请输入您的联系方式: " lxfs
        if [ -z "$lxfs" ]; then
            echo "错误：联系方式不能为空!"
            continue
        fi
        break
    done

    os_info=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_info="$NAME $VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        os_info=$(cat /etc/redhat-release)
    else
        os_info=$(uname -s -r)
    fi
    
    public_ip=$(curl -Ls --connect-timeout 3 --max-time 5 ifconfig.me || curl -Ls --connect-timeout 3 --max-time 5 shturl.cc/7Y)
    date_info=$(date)
    
    FEEDBACK_SERVER="http://43.163.94.138:8000"
    API_ENDPOINT="/feedback"
    
    if command -v jq >/dev/null 2>&1; then
        json_data=$(jq -n \
            --arg fb "$feedback" \
            --arg lf "$lxfs" \
            --arg os "$os_info" \
            --arg ip "$public_ip" \
            --arg ts "$date_info" \
            '{feedback: $fb, lxfs: $lf, os_info: $os, public_ip: $ip, timestamp: $ts}')
    else
        json_data=$(cat <<EOF
{
    "feedback": "$feedback",
    "lxfs": "$lxfs",
    "os_info": "$os_info",
    "public_ip": "$public_ip",
    "timestamp": "$date_info"
}
EOF
        )
    fi
    
    echo ">>> 正在发送反馈到服务器..."
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --connect-timeout 3 --max-time 6 \
        -d "$json_data" "$FEEDBACK_SERVER$API_ENDPOINT" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        if echo "$response" | grep -q "success"; then
            echo ">>> 反馈已成功发送! 感谢您的支持!"
        else
            echo ">>> 服务器处理反馈时出错: $response"
        fi
    else
        echo ">>> 错误：无法连接到反馈服务器!"
        echo "操作系统: $os_info"
        echo "公网IP: $public_ip"
        echo "问题描述: $feedback"
        echo "联系方式: $lxfs"
    fi
    
    echo
    read -p "按回车键返回主菜单..." -r
}

# 获取指定IP出口公网IP
get_public_ip_for_interface() {
    local ip=$1
    public_ip=$(curl --interface $ip -Ls --connect-timeout 3 --max-time 5 ifconfig.me 2>/dev/null)
    if [ -z "$public_ip" ] || [[ "$public_ip" == *error* ]]; then
        public_ip=$(curl --interface $ip -Ls --connect-timeout 3 --max-time 5 shturl.cc/7Y 2>/dev/null)
    fi
    if [ -z "$public_ip" ]; then
        public_ip=$(curl -Ls --connect-timeout 3 --max-time 5 ifconfig.me 2>/dev/null)
    fi
    echo "$public_ip"
}

# 安装函数
install_sk5() {
    clear
    echo "###############################################################"
    echo "#                 Socks5 代理安装向导                         #"
    echo "###############################################################"
    echo
    
    read -p "请输入起始端口号 (默认: 55620): " base_port
    base_port=${base_port:-55620}

    ips=( $(hostname -I) )
    
    echo "检测到以下服务器IP地址:"
    for ((i = 0; i < ${#ips[@]}; i++)); do
        echo "  $((i+1)). ${ips[i]}"
    done
    echo

    read -p "是否手动设置用户名和密码? (y/n, 默认n): " manual_set
    same_credentials=false
    base_user=""
    base_pass=""
    if [ "$manual_set" = "y" ] || [ "$manual_set" = "Y" ]; then
        echo
        read -p "请选择密码生成方式: 
        1) 所有代理使用相同用户名密码
        2) 为每个代理生成随机用户名密码
        请选择 (1/2): " pass_choice

        if [ "$pass_choice" = "1" ]; then
            read -p "请输入统一用户名: " base_user
            read -p "请输入统一密码: " base_pass
            echo "所有代理将使用统一用户名: $base_user 和密码: $base_pass"
            same_credentials=true
        fi
    fi

    echo
    echo ">>> 正在安装 Socks5 服务..."
    wget --connect-timeout 8 -O /usr/local/bin/sk5 https://github.com/yanpeng997995/prxoy/raw/main/sk5 >/dev/null 2>&1
    chmod +x /usr/local/bin/sk5
    cat <<EOF > /etc/systemd/system/sk5.service
[Unit]
Description=The sk5 Proxy Server
After=network-online.target
[Service]
ExecStart=/usr/local/bin/sk5 -c /etc/sk5/serve.toml
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=always
RestartSec=15s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sk5 >/dev/null 2>&1

    mkdir -p /etc/sk5
    echo -n "" > /etc/sk5/serve.toml
    echo -n "" > $CONFIG_FILE

    gen_random_string() {
        LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$1" | head -n 1
    }

    # 并发批量获取出口IP
    declare -A ip_map
    tmpdir=$(mktemp -d)
    for local_ip in "${ips[@]}"; do
    (
        pub_ip=$(get_public_ip_for_interface "$local_ip")
        echo "$local_ip|$pub_ip" > "${tmpdir}/${local_ip//./_}.tmp"
    ) &
    done
    wait
    for f in "${tmpdir}"/*.tmp;do
        [ -f "$f" ] || continue
        line=$(cat "$f")
        local_ip="${line%%|*}"
        pub_ip="${line#*|}"
        ip_map["$local_ip"]="$pub_ip"
    done
    rm -rf "$tmpdir"

    # 写入配置
    for ((i = 0; i < ${#ips[@]}; i++)); do
        socks_port=$((base_port + i))
        local_ip="${ips[i]}"
        public_ip="${ip_map[$local_ip]}"

        if [ "$manual_set" = "y" ] && [ "$same_credentials" = "true" ]; then
            socks_user="$base_user"
            socks_pass="$base_pass"
        else
            socks_user="$(gen_random_string 8)"
            socks_pass="$(gen_random_string 12)"
        fi

        echo "$local_ip $socks_port $socks_user $socks_pass $public_ip" >> $CONFIG_FILE

        cat <<EOF >> /etc/sk5/serve.toml
[[inbounds]]
listen = "$local_ip"
port = $socks_port
protocol = "socks"
tag = "$((i+1))"
[inbounds.settings]
auth = "password"
udp = true
ip = "$local_ip"
[[inbounds.settings.accounts]]
user = "$socks_user"
pass = "$socks_pass"
[[routing.rules]]
type = "field"
inboundTag = "$((i+1))"
outboundTag = "$((i+1))"
[[outbounds]]
sendThrough = "$local_ip"
protocol = "freedom"
tag = "$((i+1))"
EOF
    done

    systemctl stop sk5 >/dev/null 2>&1
    systemctl start sk5

    clear
    echo "==================== 安装完成 ===================="
    echo "输出格式：公网地址/端口/账号/密码"
    echo "------------------------------------------------"
    # 【重点】直接输出你要求格式的文本
    while read -r line; do
        arr=($line)
        public_ip=${arr[4]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        echo "${public_ip}/${port}/${user}/${pass}"
    done < $CONFIG_FILE
    echo "------------------------------------------------"

    echo
    echo ">>> 并发测试代理连通性"
    test_tmp=$(mktemp -d)
    while read -r line; do
    (
        arr=($line)
        ip=${arr[0]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        expected_public_ip=${arr[4]}
        export_ip=$(curl -s --connect-timeout 3 --max-time 6 --socks5 "$user:$pass@$ip:$port" ifconfig.me 2>/dev/null)
        if [ -z "$export_ip" ]; then
            echo "$ip:$port ❌ 连接失败" >> "${test_tmp}/result.log"
        else
            if [ "$export_ip" == "$expected_public_ip" ]; then
                echo "$ip:$port ✅ 成功 出口IP:$export_ip" >> "${test_tmp}/result.log"
            else
                echo "$ip:$port ✅ 成功 出口IP:$export_ip(预期:$expected_public_ip)" >> "${test_tmp}/result.log"
            fi
        fi
    ) &
    done < $CONFIG_FILE
    wait
    cat "${test_tmp}/result.log"
    rm -rf "$test_tmp"

    echo
    echo "###############################################################"
    echo "#        可在菜单【3.查看代理配置信息】重新读取连接信息         #"
    echo "###############################################################"
    echo
    read -p "按回车键返回主菜单..." -r
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入选项 (1-5): " choice
    
    case $choice in
        1) install_sk5 ;;
        2) uninstall_sk5 ;;
        3) view_configs ;;
        4) bug_feedback ;;
        5) 
            clear
            echo "感谢使用，再见!"
            exit 0
            ;;
        *) 
            echo "无效选项，请重新输入!"
            sleep 0.5
            ;;
    esac
done
