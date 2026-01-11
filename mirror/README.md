# 镜像源配置文件

本目录包含镜像源配置文件，用于定义各种开发工具的镜像源切换。

## 📁 文件列表

### 工具配置文件
| 文件 | 工具 | 镜像源数量 |
|------|------|-----------|
| `npm_mirror.json` | NPM | 11 |
| `maven_mirror.json` | Maven | 10 |
| `brew_mirror.json` | Homebrew | 8 |
| `orbstack_mirror.json` | OrbStack (Docker) | 8 |
| `python_pip.json` | Python pip2/pip3 | 9 x 2 |
| `all_mirror.json` | **所有工具合并** | 55 |

### 脚本工具
- `merge_mirrors.sh` - 合并所有镜像配置为 `all_mirror.json`

### 其他文件
- `mirror_config.schema.json` - 镜像配置的 JSON Schema
- `README.md` - 本说明文档

## 🚀 快速开始

### 合并所有配置

运行合并脚本生成包含所有工具的 `all_mirror.json`：

```bash
cd configs
./merge_mirrors.sh
```

### 配置加载方式

1. **通过配置管理窗口**：
   - 打开应用菜单中的「⚙️ 配置...」
   - 添加本地配置源，指向本目录或单个配置文件
   - 启用配置源

2. **通过环境变量**：
   ```bash
   export MIRROR_SWITCH_CONFIG_URL="https://raw.githubusercontent.com/user/repo/main/configs/all_mirror.json"
   ```

3. **通过本地文件**：
   ```bash
   # 复制到用户配置目录
   cp configs/all_mirror.json ~/.mirror-switch/tools_config.json
   ```

## 📋 添加新工具配置

要添加新的工具镜像配置：

1. 创建 `工具名_mirror.json` 文件（或添加到 `all_mirror.json`）
2. 按照 `mirror_config.schema.json` 定义配置结构
3. 在 `merge_mirrors.sh` 中添加新文件路径
4. 运行合并脚本更新 `all_mirror.json`

### 配置文件模板

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
          "url": "镜像URL",
          "description": "源描述",
          "region": "CN"
        }
      ],
      "strategy": {
        "type": "command|xml|jsonpath|regex|keyvalue",
        "set": {...},
        "get": {...}
      },
      "backup": {...},
      "metadata": {...}
    }
  ]
}
```

## 🔄 镜像源来源

所有镜像源均来自 [chsrc](https://github.com/RubyMetric/chsrc) 项目维护的权威镜像站列表：

### 教育网镜像站（重点关注）
- 清华大学 TUNA
- 上海交通大学 SJTUG
- 中科大 USTC
- 浙江大学 ZJU
- 北京外国语大学 BFSU

### 商业公司镜像站
- 阿里云
- 腾讯云
- 华为云
- 网易 163

## 📚 相关文档

- [mirror_config.schema.json](./mirror_config.schema.json) - 配置文件 Schema
- [chsrc Wiki](https://github.com/RubyMetric/chsrc/wiki) - 镜像站详细信息
