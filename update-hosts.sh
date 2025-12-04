#    sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/update-hosts.sh)"
#!/bin/bash
# update-hosts.sh
# Debian 12 更新 hosts 脚本（覆盖 /etc/hosts，无备份）

TMP_HOSTS="/tmp/merged_hosts.tmp"
HOSTS_FILE="/etc/hosts"

# 清空临时文件
> "$TMP_HOSTS"

# 下载并添加内容
for url in \
"https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt" \
"https://raw.githubusercontent.com/jinpaipai/host/refs/heads/main/host.txt" \
"https://raw.githubusercontent.com/jinpaipai/host/refs/heads/main/zidingyi.txt"
do
    echo "Downloading $url ..."
    curl -sSL "$url" >> "$TMP_HOSTS"
    echo -e "\n\n" >> "$TMP_HOSTS"
done

# 去重空行
awk '!seen[$0]++' "$TMP_HOSTS" > "${TMP_HOSTS}.dedup"

# 覆盖写入 hosts
sudo cp "${TMP_HOSTS}.dedup" "$HOSTS_FILE"

# 清理临时文件
rm -f "$TMP_HOSTS" "${TMP_HOSTS}.dedup"

echo "Hosts updated successfully!"
