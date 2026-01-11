#!/usr/bin/env python3
"""
镜像配置文件 Schema 验证脚本
验证 configs 目录下的镜像 JSON 文件是否符合 ToolsConfiguration.schema.json
"""

import json
import sys
from pathlib import Path
from jsonschema import validate, ValidationError

# 配置文件路径
CONFIG_DIR = Path(__file__).parent
SCHEMA_FILE = CONFIG_DIR / "ToolsConfiguration.schema.json"

# 需要验证的镜像配置文件
MIRROR_FILES = [
    "brew_mirror.json",
    "maven_mirror.json",
    "npm_mirror.json",
    "orbstack_mirror.json",
    "python_pip.json",
]

def load_schema():
    """加载 schema 文件"""
    with open(SCHEMA_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)

def validate_file(schema, file_path):
    """验证单个 JSON 文件"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        validate(instance=data, schema=schema)
        return True, "✅ 通过"
    except ValidationError as e:
        return False, f"❌ 验证失败: {e.message}"
    except json.JSONDecodeError as e:
        return False, f"❌ JSON 解析错误: {e}"
    except Exception as e:
        return False, f"❌ 错误: {e}"

def main():
    """主函数"""
    print("=" * 60)
    print("镜像配置文件 Schema 验证")
    print("=" * 60)

    # 加载 schema
    try:
        schema = load_schema()
        print(f"✓ 已加载 schema: {SCHEMA_FILE.name}\n")
    except Exception as e:
        print(f"❌ 无法加载 schema 文件: {e}")
        sys.exit(1)

    # 验证各个文件
    results = []
    for filename in MIRROR_FILES:
        file_path = CONFIG_DIR / filename
        if not file_path.exists():
            results.append((filename, False, "⚠️ 文件不存在"))
            continue

        success, message = validate_file(schema, file_path)
        results.append((filename, success, message))

    # 输出结果
    print("\n验证结果:")
    print("-" * 60)

    all_passed = True
    for filename, success, message in results:
        status_symbol = "✓" if success else "✗"
        print(f"{status_symbol} {filename:30s} {message}")
        if not success:
            all_passed = False

    print("-" * 60)

    if all_passed:
        print("\n✅ 所有文件验证通过！")
        return 0
    else:
        print("\n❌ 部分文件验证失败，请检查上述错误！")
        return 1

if __name__ == "__main__":
    sys.exit(main())
