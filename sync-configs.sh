#!/bin/bash
# 同步配置文件脚本
# 将根目录的 configs/ 复制到 Sources/MirrorSwitch/configs/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/configs"
TARGET_DIR="$SCRIPT_DIR/Sources/MirrorSwitch/configs"

echo "🔄 同步配置文件..."
echo "   源: $SOURCE_DIR"
echo "   目标: $TARGET_DIR"

# 确保目标目录存在
mkdir -p "$TARGET_DIR"

# 复制所有 JSON 文件
for file in "$SOURCE_DIR"/*.json; do
    filename=$(basename "$file")
    echo "   复制: $filename"
    cp "$file" "$TARGET_DIR/$filename"
done

# 复制 README.md
if [ -f "$SOURCE_DIR/README.md" ]; then
    echo "   复制: README.md"
    cp "$SOURCE_DIR/README.md" "$TARGET_DIR/README.md"
fi

echo "✅ 配置文件同步完成！"
