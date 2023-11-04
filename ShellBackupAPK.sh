#!/bin/bash

# 函数：检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null
    then
        echo "命令未找到：$1"
        exit 1
    fi
}

# 检查关键命令
check_command tar
check_command mkdir
check_command grep
check_command find
check_command pm

# 函数：压缩指定目录
backup_directory() {
    if [ -d "$1" ] && [ "$(ls -A $1)" ]; then
        echo "压缩 $1"
        tar -cf "$2" -C "$1" . > /dev/null 2>&1
    else
        echo "跳过 $1"
    fi
}
# 函数：复制 APK 文件到备份目录
backup_apk() {
    pm path $1 | while read -r line; do
        local pkg_apk_path=$(echo $line | cut -d':' -f2)
        if [ ! -z "$pkg_apk_path" ]; then
            local apk_file_name=$(basename "$pkg_apk_path")
            echo "复制 APK $1 ($apk_file_name)"
            cp "$pkg_apk_path" "$2/$apk_file_name" || echo "复制 APK 失败：$pkg_apk_path" >&2
        else
            echo "找不到 APK $1"
        fi
    done
}

# 读取用户输入的包名
echo "请输入包名（输入'all'或'ALL'备份所有非系统应用）："
read package_name

# 备份目录
backup_base="/sdcard/ShellBackupAPK"

# 如果用户输入 all 或 ALL，备份所有非系统应用
if [ "$package_name" = "all" ] || [ "$package_name" = "ALL" ]; then
    # 获取所有非系统应用包名，排除部分包名
    packages=$(pm list packages -3 | grep -v "com.miui" | grep -v "com.xiaomi" | grep -v "com.mi." | cut -d':' -f2)
else
    packages=$package_name
fi

#由于数组$packages只有一个成员，所以用这种方式获取它的成员数量
size=0
for pkg in $packages
do
((size++))
done


# 循环备份每个包名
i=0
for pkg in $packages
do
    ((i++))
    echo "===== $i/$size ========== $pkg"

    # 创建备份目录
    backup_dir="$backup_base/$pkg"
    mkdir -p "$backup_dir"

    # 定义备份文件路径
    user0_backup="$backup_dir/data_user_0.tar"
    user999_backup="$backup_dir/data_user_999.tar"
    data_backup="$backup_dir/sdcard_Android_data.tar"
    obb_backup="$backup_dir/sdcard_Android_obb.tar"
    apk_backup="$backup_dir/"

    # 备份 APK
    backup_apk "$pkg" "$apk_backup"

    # 备份每个目录
    backup_directory "/data/user/0/$pkg" "$user0_backup"
    backup_directory "/data/user/999/$pkg" "$user999_backup"
    backup_directory "/sdcard/Android/data/$pkg" "$data_backup"
    backup_directory "/sdcard/Android/obb/$pkg" "$obb_backup"
done

echo "===== END ====="
echo "备份操作完成。"
