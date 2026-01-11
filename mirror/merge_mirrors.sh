#!/bin/bash
# 合并所有镜像配置文件为 all_mirror.json

set -e

# 获取脚本所在目录
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$CONFIG_DIR/all_mirror.json"

echo "🔄 开始合并镜像配置文件..."

# 收集所有需要合并的配置文件
config_files=(
  "$CONFIG_DIR/npm_mirror.json"
  "$CONFIG_DIR/maven_mirror.json"
  "$CONFIG_DIR/brew_mirror.json"
  "$CONFIG_DIR/orbstack_mirror.json"
  "$CONFIG_DIR/python_pip.json"
)

# 检查所有文件是否存在
for file in "${config_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "❌ 文件不存在: $file"
    exit 1
  fi
done

# 使用 jq 合并所有配置文件
jq -s '{
  version: "1.0.0",
  tools: ([.[].tools] | flatten)
}' "${config_files[@]}" > "$OUTPUT"

# 统计合并的工具数量
tool_count=$(jq '.tools | length' "$OUTPUT")

echo "✅ 已合并所有镜像配置到: $OUTPUT"
echo "📊 共包含 $tool_count 个工具配置"
