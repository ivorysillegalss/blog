#!/bin/bash

# 进入 hexo 目录（强制确保路径正确）
cd /home/czc/hexo || exit 1

# 生成静态文件
echo "正在生成 Hexo 静态文件..."
hexo g

# 检查 blog/public 是否存在，若存在则清除内容
TARGET_DIR="/home/czc/blog"
if [ -d "$TARGET_DIR" ]; then
    echo "发现旧的 public 目录，正在清理..."
    rm -rf "${TARGET_DIR:?}/"*  # 安全删除（防止误删根目录）
fi

# 移动新生成的 public 到 blog 目录
echo "正在移动新 public 目录..."
mv public "$TARGET_DIR"

echo "操作完成！"
