# 镜像源配置文件

本目录包含镜像源配置文件，可通过远程配置加载。

## 📁 文件说明

- `*_mirror.json` - 各工具的镜像配置文件
- `mirror_config.schema.json` - 镜像配置的 JSON Schema
- `README.md` - 本说明文档

## 🎯 目录用途

此目录专门用于存放镜像源配置，作为远程配置源使用。应用可以从远程 URL 加载此目录中的配置文件。

### 配置加载方式

1. **通过配置管理窗口**：
   - 打开应用菜单中的「⚙️ 配置...」
   - 添加远程配置源（URL 指向此目录或单个文件）
   - 启用配置源

2. **通过环境变量**：
   ```bash
   export MIRROR_SWITCH_CONFIG_URL="https://raw.githubusercontent.com/user/repo/main/configs/npm_mirror.json"
   ```

3. **通过本地文件**：
   - 将配置文件放到 `~/.mirror-switch/` 目录
   - 应用会自动加载

## 📋 添加新配置

要添加新的工具镜像配置：

1. 创建 `工具名_mirror.json` 文件
2. 按照 `mirror_config.schema.json` 定义配置结构
3. 在应用配置管理窗口中添加此配置源

## 🔧 配置文件格式

每个 `*_mirror.json` 文件应包含以下结构：

```json
{
  "version": "1.0.0",
  "tools": [
    {
      "id": "工具ID",
      "name": "工具名称",
      "description": "工具描述",
      "detection": {
        "command": "命令",
        "arguments": ["--version"]
      },
      "sources": [
        {
          "id": "源ID",
          "name": "源名称",
          "url": "镜像URL"
        }
      ],
      "strategy": {
        "type": "command",
        "set": {...},
        "get": {...}
      }
    }
  ]
}
```

## 📚 相关文档

- [mirror_config.schema.json](./mirror_config.schema.json) - 配置文件 Schema
- [npm_mirror.json](./npm_mirror.json) - 示例配置文件
