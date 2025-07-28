#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

# 检查并安装依赖
check_dependencies() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo "检测到未安装unzip，正在安装..."
        apt-get update && apt-get install -y unzip
        if [ $? -ne 0 ]; then
            echo "安装unzip失败！"
            exit 1
        fi
    fi

    if ! command -v zip >/dev/null 2>&1; then
        echo "检测到未安装zip，正在安装..."
        apt-get install -y zip
        if [ $? -ne 0 ]; then
            echo "安装zip失败！"
            exit 1
        fi
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "检测到未安装python3，正在安装..."
        apt-get install -y python3
        if [ $? -ne 0 ]; then
            echo "安装python3失败！"
            exit 1
        fi
    fi
}

# 查找egg文件
find_egg_file() {
    EGG_PATH="/usr/local/openvpn_as/lib/python"
    EGG_FILE=$(find $EGG_PATH -name "pyovpn-2.0-py3.*.egg" | head -n 1)
    
    if [ -z "$EGG_FILE" ]; then
        echo "错误：未在$EGG_PATH目录下找到pyovpn-2.0-py3.*.egg文件"
        exit 1
    fi
    
    echo "找到egg文件: $EGG_FILE"
    EGG_NAME=$(basename "$EGG_FILE")
}

# 主函数
main() {
    check_dependencies
    find_egg_file

    # 1. 备份源文件
    echo "正在备份源文件..."
    cp "$EGG_FILE" "$EGG_FILE.bak"
    if [ $? -ne 0 ]; then
        echo "备份失败！"
        exit 1
    fi

    # 2. 复制到当前目录
    echo "正在复制文件到当前目录..."
    cp "$EGG_FILE" .
    if [ $? -ne 0 ]; then
        echo "复制失败！"
        exit 1
    fi

    # 3. 解压
    echo "正在解压文件..."
    unzip -q "$EGG_NAME"
    if [ $? -ne 0 ]; then
        echo "解压失败！"
        exit 1
    fi

    # 4. 进入lic目录
    cd ./pyovpn/lic/ || {
        echo "进入lic目录失败！"
        exit 1
    }

    # 5. 备份uprop.pyc
    echo "正在备份uprop.pyc..."
    if [ -f "uprop.pyc" ]; then
        mv uprop.pyc uprop2.pyc
    else
        echo "警告：未找到uprop.pyc文件，继续执行..."
    fi

    # 6. 创建uprop.py
    echo "正在创建uprop.py..."
    cat > uprop.py << 'EOF'
from pyovpn.lic import uprop2
old_figure = None
 
def new_figure(self, licdict):
      ret = old_figure(self, licdict)
      ret['concurrent_connections'] = 2048
      return ret
 
for x in dir(uprop2):
      if x[:2] == '__':
         continue
      if x == 'UsageProperties':
         exec('old_figure = uprop2.UsageProperties.figure')
         exec('uprop2.UsageProperties.figure = new_figure')
      exec('%s = uprop2.%s' % (x, x))
EOF

    # 7. 重新编译
    echo "正在重新编译..."
    python3 -O -m compileall uprop.py && mv __pycache__/uprop.*.pyc uprop.pyc
    if [ $? -ne 0 ]; then
        echo "编译失败！"
        exit 1
    fi

    # 8. 返回上级目录
    cd ../../ || {
        echo "返回上级目录失败！"
        exit 1
    }

    # 9. 重新打包
    echo "正在重新打包..."
    zip -rq "$EGG_NAME" ./pyovpn ./EGG-INFO ./common
    if [ $? -ne 0 ]; then
        echo "打包失败！"
        exit 1
    fi

    # 10. 移动回原目录
    echo "正在移动文件回原目录..."
    mv -f "$EGG_NAME" "$EGG_FILE"
    if [ $? -ne 0 ]; then
        echo "移动失败！"
        exit 1
    fi

    # 11. 重启服务
    echo "正在重启openvpnas服务..."
    systemctl restart openvpnas
    if [ $? -ne 0 ]; then
        echo "重启服务失败！请手动检查。"
        exit 1
    fi

    echo "操作完成！"
}

# 执行主函数
main
