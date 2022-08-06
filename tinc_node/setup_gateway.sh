#!/bin/sh

#
# まちかどネットワークtincノードセットアップスクリプト
#
# 使い方
#   chmod +x setup_gateway.sh
#   sudo ./setup_gateway.sh.sh <tincノード名> <まちかどネットワーク側IPアドレス>
#
# forked from https://gist.github.com/miminashi/f83a967f8c1a74dcb927aeb90947d766
#

set -e

tinc_netname="mchkd"

# Debian系かどうかをチェックする
if ! test -f /etc/debian_version; then
  echo "Debian系のOSではありません. 終了します" >&2
  exit 1
fi

if test -d /etc/tinc/"${tinc_netname}"; then
  printf 'エラー: /etc/tinc/"${tinc_netname}" は既に存在します\n' >&2
  printf 'セットアップを中止します\n' >&2
  printf 'セットアップをやりなおす場合は sudo rm -rf /etc/tinc/"${tinc_netname}" してから再度セットアップスクリプトを実行してください\n' >&2
  exit 1
fi

node_name="${1}"
ip_address="${2}"

if echo "${node_name}" | grep -v '^[0-9a-z][0-9a-z]*$'; then
  printf 'エラー: ノード名に使える文字は [a-z0-9] のみです\n' >&2
  printf 'セットアップを中止します\n' >&2
  exit 1
fi

printf 'NODE_NAME: %s\n' "${node_name}"
printf 'IP_ADDRESS: %s\n' "${ip_address}"

# tinc,iptablesのインストール
apt-get update
apt-get install -y tinc iptables

# 設定用ディレクトリの作成
mkdir /etc/tinc/"${tinc_netname}"
mkdir /etc/tinc/"${tinc_netname}"/hosts

# 自ノードのノード定義の作成
# いまのところ特に設定する内容は無い
sed 's/{NODE_NAME}/'"${node_name}"'/' > /etc/tinc/"${tinc_netname}"/hosts/"${node_name}" <<'EOF'
# {NODE_NAME}
EOF

## 初期ルートノードの設定
##  - syami momo
#cat > /etc/tinc/"${tinc_netname}"/hosts/syamimomo <<'EOF'
## syamimomo
#Address = 52.194.124.212
#Port = 655
#Ed25519PublicKey = gK0Altm/AO+Zgj7EeFQ2Fi+bMQAKKwnY61r+wQk3AHG
#EOF

## tinc.conf の作成
#sed -e 's/{NODE_NAME}/'"${node_name}"'/' > /etc/tinc/"${tinc_netname}"/tinc.conf <<'EOF'
#Name = {NODE_NAME}
#Mode = switch
#Device = /dev/net/tun
#ConnectTo = syamimomo
#EOF
# tinc.conf の作成
sed -e 's/{NODE_NAME}/'"${node_name}"'/' > /etc/tinc/"${tinc_netname}"/tinc.conf <<'EOF'
Name = {NODE_NAME}
Mode = switch
Device = /dev/net/tun
EOF


# tinc-up スクリプトの作成
# このシェルスクリプトはVPNセッションの開始時に実行される
sed -e 's/{TINC_NETNAME}/'"${tinc_netname}"'/' -e 's/{IP_ADDRESS}/'"${ip_address}"'/' > /etc/tinc/"${tinc_netname}"/tinc-up <<'EOF'
#!/bin/sh
#ip link add br0 type bridge
#ip link set br0 up
ip link set $INTERFACE up
#ip link set dev $INTERFACE master br0
#ip link set dev eth1 master br0
#ip addr add {IP_ADDRESS}/8 dev br0
ip addr add {IP_ADDRESS}/8 dev $INTERFACE
echo 1 > /proc/sys/net/ipv4/ip_forward
#iptables-restore < /etc/tinc/{TINC_NETNAME}/nat.iptables
EOF
chmod +x /etc/tinc/"${tinc_netname}"/tinc-up

# iptables(NAT)の設定ファイルの作成
cat > /etc/tinc/"${tinc_netname}"/nat.iptables <<'EOF'
# Generated by xtables-save v1.8.2 on Thu Jul 15 00:21:02 2021
*filter
:INPUT ACCEPT [46687:11733996]
:FORWARD ACCEPT [1617:74797]
:OUTPUT ACCEPT [295135:228581507]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i br0 -o eth0 -j DROP
COMMIT
# Completed on Thu Jul 15 00:21:02 2021
# Generated by xtables-save v1.8.2 on Thu Jul 15 00:21:02 2021
*nat
:PREROUTING ACCEPT [15990:4356696]
:INPUT ACCEPT [12944:3533125]
:POSTROUTING ACCEPT [410:45315]
:OUTPUT ACCEPT [175:24583]
-A POSTROUTING -o br0 -j MASQUERADE
COMMIT
# Completed on Thu Jul 15 00:21:02 2021
# Generated by xtables-save v1.8.2 on Thu Jul 15 00:21:02 2021
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
# Completed on Thu Jul 15 00:21:02 2021
# Generated by xtables-save v1.8.2 on Thu Jul 15 00:21:02 2021
*raw
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
# Completed on Thu Jul 15 00:21:02 2021
EOF


# tinc-down スクリプトの作成
#   このシェルスクリプトはVPNセッションの終了時に実行される
cat > /etc/tinc/"${tinc_netname}"/tinc-down <<'EOF'
#!/bin/sh
#ip link set dev $INTERFACE nomaster
ip link set dev $INTERFACE down
#ip link set dev eth1 nomaster
#ip link set dev br0 down
#ip link del dev br0
EOF
chmod +x /etc/tinc/"${tinc_netname}"/tinc-down

# 鍵ペアの生成
#   tincの src/conf.c:541 を見ると標準入力と標準出力のどちらかが端末でない場合はデフォルトのファイル名を用いるようなので、`| cat` をつけている
sudo tincd -K -n "${tinc_netname}" | cat

# デバッグログの有効化
sed -i -e '/^# EXTRA="-d"$/ s/# //' /etc/default/tinc

# tincサービスの有効化
systemctl enable tinc@"${tinc_netname}".service
systemctl start tinc@"${tinc_netname}".service

## 完了メッセージを表示する
#cat /etc/tinc/"${tinc_netname}"/hosts/"${node_name}"

# 完了メッセージを表示する
printf '\n'
printf 'tincのセットアップが完了しました\n'
printf 'https://www.machikado.network/aptos/user の「公開鍵」の欄に以下の内容をコピペしてください\n'
printf '\n'
printf '\e[34m' # 青くする
printf '```\n'
cat /etc/tinc/"${tinc_netname}"/hosts/"${node_name}"
printf '```\n'
printf '\e[m' # 元の色にする
printf '\n'
