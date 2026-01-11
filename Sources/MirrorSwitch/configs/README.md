# MirrorSwitch 配置文件说明

本目录包含 MirrorSwitch 应用的所有配置文件。

## ⚠️ 重要提示

本项目中有两个 `configs/` 目录：

1. **根目录的 `configs/`** ← **请在此处编辑配置文件**
   - 这是"源"配置目录
   - 方便查看和编辑
   - 版本控制的主要目录

2. **`Sources/MirrorSwitch/configs/`** ← **自动同步，请勿手动编辑**
   - Swift Package Manager 需要资源在目标目录下
   - 由同步脚本自动从根目录复制

**编辑配置后，请运行同步脚本**：
```bash
./sync-configs.sh
```

## 📁 文件结构

```
configs/
├── app_config.json           # 应用配置（UI、行为、网络等）
├── app_config.schema.json    # 应用配置的 JSON Schema
├── tools_config.json         # 工具配置（定义支持的镜像源）
├── tools_config.schema.json  # 工具配置的 JSON Schema
├── ui_strings.json           # UI 字符串（国际化）
└── README.md                 # 本文件
```

## 📋 配置文件说明

### 1. app_config.json

**作用**：定义应用的基本信息和行为配置

**主要配置项**：
- `app`: 应用基本信息（名称、版本等）
- `ui`: UI 相关配置（菜单栏图标、测速设置等）
- `behavior`: 应用行为配置（自动检测、自动备份等）
- `network`: 网络相关配置（超时、重试等）
- `paths`: 路径配置（配置目录、备份目录等）
- `remoteConfig`: 远程配置设置
- `features`: 功能开关

**示例**：
```json
{
  "ui": {
    "speedTest": {
      "enabled": true,
      "autoRunOnLaunch": true,
      "timeout": 5
    }
  }
}
```

### 2. tools_config.json

**作用**：定义支持的镜像源工具和切换策略

**主要配置项**：
- `tools`: 工具列表，每个工具包含：
  - `id`: 工具唯一标识
  - `name`: 工具显示名称
  - `detection`: 工具检测配置
  - `sources`: 镜像源列表
  - `strategy`: 切换策略（command/xml/jsonpath/regex/keyvalue）
  - `backup`: 备份配置

**支持的策略类型**：
1. **command**: 通过命令行工具切换
2. **xml**: 通过修改 XML 文件切换
3. **jsonpath**: 通过修改 JSON 文件切换
4. **regex**: 通过正则表达式替换切换
5. **keyvalue**: 通过修改键值对文件切换

### 3. ui_strings.json

**作用**：UI 字符串配置，支持国际化

**主要配置项**：
- 应用名称和菜单文本
- 错误消息
- 通知文本
- 设置界面文本

## 🔄 远程配置支持

### 配置方式

应用支持从远程 URL 加载配置，支持以下方式：

#### 方式 1: 环境变量
```bash
export MIRROR_SWITCH_CONFIG_URL="https://raw.githubusercontent.com/user/repo/main/configs/app_config.json"
export MIRROR_SWITCH_TOOLS_URL="https://raw.githubusercontent.com/user/repo/main/configs/tools_config.json"
```

#### 方式 2: 配置文件
在 `~/.mirror-switch/config.json` 中配置：
```json
{
  "remoteConfig": {
    "enabled": true,
    "url": "https://raw.githubusercontent.com/user/repo/main/configs",
    "updateInterval": 86400
  }
}
```

### 配置优先级

1. **远程配置**（最高优先级）
2. **用户本地配置** (`~/.mirror-switch/`)
3. **内置默认配置**（最低优先级）

### 安全措施

- ✅ JSON Schema 验证
- ✅ ETag 缓存机制
- ✅ HTTPS 支持
- ✅ 错误回退到本地配置

## 🛠️ 添加新工具

### 步骤 1: 编辑 tools_config.json

```json
{
  "id": "cargo",
  "name": "Cargo",
  "description": "Rust Package Manager",
  "detection": {
    "command": "cargo",
    "arguments": ["--version"]
  },
  "sources": [
    {
      "id": "cargo-official",
      "name": "官方源",
      "url": "https://crates.io/",
      "description": "Crates.io 官方"
    },
    {
      "id": "cargo-tsinghua",
      "name": "清华源",
      "url": "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index/",
      "description": "清华大学镜像",
      "region": "CN"
    }
  ],
  "strategy": {
    "type": "command",
    "set": {
      "command": "cargo",
      "arguments": ["config", "set", "registry.index", "{{url}}"]
    },
    "get": {
      "command": "cargo",
      "arguments": ["config", "get", "registry.index"],
      "outputParser": "trim"
    }
  },
  "backup": {
    "filePath": "~/.cargo/config",
    "backupFileName": "config.backup",
    "backupOriginal": true
  }
}
```

### 步骤 2: 重启应用

应用会自动加载新工具配置，无需修改任何 Swift 代码！

## 📝 配置验证

### 使用 JSON Schema 验证

```bash
# 验证应用配置
cat configs/app_config.json | jq '.'
cat configs/app_config.json | ajv validate -s configs/app_config.schema.json

# 验证工具配置
cat configs/tools_config.json | jq '.'
cat configs/tools_config.json | ajv validate -s configs/tools_config.schema.json
```

## 🔧 常见配置场景

### 禁用自动测速

```json
{
  "ui": {
    "speedTest": {
      "enabled": false
    }
  }
}
```

### 启用远程配置自动更新

```json
{
  "remoteConfig": {
    "enabled": true,
    "url": "https://raw.githubusercontent.com/user/repo/main/configs",
    "updateInterval": 86400
  }
}
```

### 自定义备份路径

```json
{
  "paths": {
    "backupDirectory": "~/Documents/mirror-switch-backups"
  }
}
```

## 📚 相关文档

- [项目主页](https://github.com/your-repo)
- [配置驱动架构设计](./ARCHITECTURE.md)
- [工具配置指南](./TOOLS_GUIDE.md)

## 🤝 贡献指南

欢迎提交 PR 添加新的镜像源配置！

1. Fork 本项目
2. 创建配置分支：`git checkout -b feature/add-new-tool`
3. 修改 `tools_config.json` 添加新工具
4. 提交更改：`git commit -m "Add: 新增 XXX 工具支持"`
5. 推送分支：`git push origin feature/add-new-tool`
6. 创建 Pull Request

## ⚠️ 注意事项

1. **备份重要配置**：修改配置前请备份原文件
2. **验证 JSON 格式**：确保 JSON 格式正确，可以使用 `jq` 或在线工具验证
3. **测试配置**：修改配置后请测试所有功能是否正常
4. **版本兼容**：注意配置文件版本号，确保与应用版本兼容

## 📞 联系方式

- Issue: [GitHub Issues](https://github.com/your-repo/issues)
- Email: your-email@example.com
