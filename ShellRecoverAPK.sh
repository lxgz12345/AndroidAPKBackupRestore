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
check_command cp
check_command mkdir
check_command grep
check_command cut
check_command chown
check_command awk

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

# 函数：恢复数据
restore_data() {
    local app_name=$1
    local user_id=$2
    local data_tar_path=$3
    local target_dir=$4

    if [ -f "$data_tar_path" ]; then
        mkdir -p "$target_dir"
        tar -xf "$data_tar_path" --exclude='./lib' -C "$target_dir" || echo "恢复失败：$data_tar_path" >&2
        chown -R $user_id:$user_id "$target_dir"
    fi
}

# 函数：安装 APKs
install_apks() {
    local app_name=$1
    local tmp_dir="/data/local/tmp"
    local session_id

    echo "开始安装 $app_name ..."

    # 检查是否有 Split APKs
    local apk_files=("$backup_base/$app_name"/*.apk)
    if [ ${#apk_files[@]} -eq 1 ]; then
        # 只有一个 APK 文件，使用 pm install
        pm install "${apk_files[0]}" || {
            echo "安装失败：${apk_files[0]}" >&2
            return 1
        }
    else
        # 多个 APK 文件，需要创建安装会话

        # 计算总大小
        local total_size=$(du -cb "$backup_base/$app_name"/*.apk | grep 'total$' | cut -f1)

        # 创建安装会话
        output=$(pm install-create -S $total_size)
        session_id=$(echo "$output" | grep -o '[0-9]*' | head -n 1)
        if [ -z "$session_id" ]; then
            echo "安装会话创建失败。输出为：$output" >&2
            return 1
        fi


        local file_index=0

        # 安装 base APK 和所有的 Split APKs
        for apk_file in "${apk_files[@]}"; do
            local file_size=$(stat -c%s "$apk_file")
            local file_name=$(basename "$apk_file")

            # 复制到临时目录
            cp "$apk_file" "$tmp_dir"
            local tmp_apk="$tmp_dir/$file_name"

            # 阶段性地写入 APK 文件
            pm install-write -S $file_size $session_id $file_index "$tmp_apk" || {
                echo "写入 APK 失败：$tmp_apk" >&2
                pm install-abandon $session_id
                rm "$tmp_apk"
                return 1
            }
            file_index=$((file_index + 1))

            # 删除临时 APK
            rm "$tmp_apk"
        done

        # 提交安装
        pm install-commit $session_id || {
            echo "安装提交失败。" >&2
            pm install-abandon $session_id
            return 1
        }
    fi

    echo "安装完成：$app_name"
}


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
    install_apks $app_name
    
    # 获取应用的用户ID
    local user_id=$(pm list packages -U | grep "$app_name" | cut -d':' -f3)
    
    # 恢复数据
    restore_data "$app_name" "$user_id" "$backup_base/$app_name/data_user_0.tar" "/data/user/0/$app_name"
    restore_data "$app_name" "$user_id" "$backup_base/$app_name/data_user_999.tar" "/data/user/999/$app_name"
    restore_data "$app_name" "$user_id" "$backup_base/$app_name/sdcard_Android_data.tar" "/sdcard/Android/data/$app_name"
    restore_data "$app_name" "$user_id" "$backup_base/$app_name/sdcard_Android_obb.tar" "/sdcard/Android/obb/$app_name"
    
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
