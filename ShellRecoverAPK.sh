#!/bin/bash

# 函数：检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null
    then
        echo "命令未找到：$1" >&2
        exit 1
    fi
}

# 检查关键命令
check_command tar
check_command pm
check_command ls

# 列出备份文件夹
echo "可恢复的应用列表："
backup_base="/sdcard/ShellBackupAPK"
i=0
declare -A app_list # 关联数组，用于存储序号和包名的映射

for entry in "$backup_base"/*
do
    if [ -d "$entry" ]; then
        app_name=$(basename "$entry")
        app_list[$((++i))]="$app_name" # 将包名与序号关联
        echo "$i. $app_name"
    fi
done

if [ $i -eq 0 ]; then
    echo "没有找到备份的应用。"
    exit 0
fi

# 用户选择恢复哪个应用
echo "请输入序号选择应用（输入'all'或'ALL'恢复所有应用）："
read user_choice

# 安装并恢复数据的函数
install_and_restore() {
    local app_name=$1
    local tmp_dir="/data/local/tmp"

    echo "开始恢复 $app_name ..."

    # 检查临时目录是否存在
    if [ ! -d "$tmp_dir" ]; then
        mkdir -p "$tmp_dir"
    fi

    # 安装 APK
    local base_apk="$backup_base/$app_name/base.apk"
    if [ -f "$base_apk" ]; then
        # 复制到临时目录
        cp "$base_apk" "$tmp_dir"
        local tmp_apk="$tmp_dir/$(basename "$base_apk")"
        pm install "$tmp_apk" || echo "安装失败：$tmp_apk" >&2
        # 删除临时 APK
        rm "$tmp_apk"

        # 安装 Split APKs 如果存在
        for split_apk in "$backup_base/$app_name"/split_*.apk; do
            if [ -f "$split_apk" ]; then
                # 复制到临时目录
                cp "$split_apk" "$tmp_dir"
                local tmp_split_apk="$tmp_dir/$(basename "$split_apk")"
                pm install "$tmp_split_apk" || echo "安装失败：$tmp_split_apk" >&2
                # 删除临时 Split APK
                rm "$tmp_split_apk"
            fi
        done
    fi
    
    # 恢复数据
    local user0_tar="$backup_base/$app_name/data_user_0.tar"
    if [ -f "$user0_tar" ]; then
        tar -xf "$user0_tar" -C "/data/user/0/$app_name" || echo "恢复失败：$user0_tar" >&2
    fi
    local user999_tar="$backup_base/$app_name/data_user_999.tar"
    if [ -f "$user999_tar" ]; then
        tar -xf "$user999_tar" -C "/data/user/999/$app_name" || echo "恢复失败：$user999_tar" >&2
    fi
    local data_tar="$backup_base/$app_name/sdcard_Android_data.tar"
    if [ -f "$data_tar" ]; then
        tar -xf "$data_tar" -C "/sdcard/Android/data/$app_name" || echo "恢复失败：$data_tar" >&2
    fi
    local obb_tar="$backup_base/$app_name/sdcard_Android_obb.tar"
    if [ -f "$obb_tar" ]; then
        tar -xf "$obb_tar" -C "/sdcard/Android/obb/$app_name" || echo "恢复失败：$obb_tar" >&2
    fi
    
    echo "恢复完成：$app_name"
}

# 根据用户的选择进行恢复
if [[ "$user_choice" == "all" || "$user_choice" == "ALL" ]]; then
    for app_name in "${app_list[@]}"; do
        install_and_restore "$app_name"
    done
else
    # 判断用户输入是否为数字并在范围内
    if [[ "$user_choice" =~ ^[0-9]+$ ]] && [ "$user_choice" -ge 1 ] && [ "$user_choice" -le $i ]; then
        install_and_restore "${app_list[$user_choice]}"
    else
        echo "无效的输入。" >&2
        exit 1
    fi
fi

echo "===== 恢复操作完成 ====="
