#!/usr/bin/env bash
# 在 macOS 上发布未签名的 Medis.app（依赖 .nvmrc / .node-version 中的 Node 10）。
# 若 npm 安装阶段出现 invalid mode: 'rU'：本机 Python 过新，请 brew install python@3.10，
#   或 export PYTHON=/opt/homebrew/opt/python@3.10/bin/python3.10 后再运行。
# 若出现 env: python: No such file or directory：Makefile 会调用名为 python 的可执行文件，
#   本脚本在 $TMPDIR 下创建临时 shim 暴露为 python（不会写入仓库，避免 asar 打包失败）。
# 用法：
#   ./scripts/publish-darwin.sh           # npm ci + 生产构建 + electron-packager
#   ./scripts/publish-darwin.sh --install-only
#   ./scripts/publish-darwin.sh --pack-only   # 已有 node_modules 且已构建过时使用
#   ./scripts/publish-darwin.sh --mas       # Mac App Store 打包（需证书与本机签名环境，见 bin/pack.js）
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 旧版脚本曾在仓库内创建 .npm-build-shim，asar 不允许指向包外的 symlink，需清理
if [ -d "$ROOT/.npm-build-shim" ] || [ -L "$ROOT/.npm-build-shim" ]; then
  rm -rf "$ROOT/.npm-build-shim"
  echo "已删除仓库内旧的 .npm-build-shim（避免 electron-packager 报错）。" >&2
fi

INSTALL_ONLY=false
PACK_ONLY=false
MAS=false
for arg in "$@"; do
  case "$arg" in
    --install-only) INSTALL_ONLY=true ;;
    --pack-only)    PACK_ONLY=true ;;
    --mas)          MAS=true ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
  esac
done

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env)"
  fnm install
  fnm use
elif [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install
  nvm use
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install
  nvm use
elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  mkdir -p "$NVM_DIR"
  # shellcheck source=/dev/null
  . "/opt/homebrew/opt/nvm/nvm.sh"
  nvm install
  nvm use
else
  echo "未找到 nvm 或 fnm。请先安装其一，或将 NVM_DIR 指向 nvm.sh 所在目录。" >&2
  exit 1
fi

# Node 10 自带的 node-gyp 使用旧版 gyp，在 Python 3.11+ 上会报：
#   ValueError: invalid mode: 'rU' while trying to load binding.gyp
# 因此优先使用 Python 3.10 或 3.9（brew install python@3.10）。
pick_python_for_node_gyp() {
  if [ -n "${PYTHON:-}" ] && [ -x "$PYTHON" ]; then
    printf '%s' "$PYTHON"
    return
  fi
  local c
  for c in \
    "$(command -v python3.10 2>/dev/null)" \
    "$(command -v python3.9 2>/dev/null)" \
    "/opt/homebrew/opt/python@3.10/bin/python3.10" \
    "/opt/homebrew/opt/python@3.9/bin/python3.9" \
    "/usr/local/opt/python@3.10/bin/python3.10" \
    "/usr/local/opt/python@3.9/bin/python3.9"
  do
    if [ -n "$c" ] && [ -x "$c" ]; then
      printf '%s' "$c"
      return
    fi
  done
  command -v python3 2>/dev/null || true
}

PY="$(pick_python_for_node_gyp)"
if [ -n "$PY" ]; then
  export PYTHON="$PY"
  export npm_config_python="$PY"
  echo "PYTHON（供 node-gyp）: $PY" >&2
else
  echo "警告: 未找到 python3，node-gyp 可能失败。" >&2
fi

# cpu-features / 部分 Makefile 会执行 `env python`，macOS 往往只有 python3。
ensure_python_on_path() {
  local py="$1"
  if [ -z "$py" ] || [ ! -x "$py" ]; then
    return 0
  fi
  local rootdir
  rootdir="$(cd "$(dirname "$py")/.." && pwd)"
  if [ -x "$rootdir/libexec/bin/python" ]; then
    export PATH="$rootdir/libexec/bin:$PATH"
    echo "PATH 前置（Homebrew python 的 python 别名）: $rootdir/libexec/bin" >&2
    return 0
  fi
  # 不可放在仓库目录内：asar 打包时禁止「指向包外」的 symlink
  local shim
  shim="$(mktemp -d "${TMPDIR:-/tmp}/medis-npm-shim.XXXXXX")"
  ln -sf "$py" "$shim/python"
  export PATH="$shim:$PATH"
  trap "rm -rf '$shim'" EXIT
  echo "PATH 前置 python -> $py（临时目录 $shim）" >&2
}
ensure_python_on_path "$PY"

echo "Node: $(node -v)  npm: $(npm -v)  cwd: $ROOT"

if [ "$PACK_ONLY" != true ]; then
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi
fi

if [ "$INSTALL_ONLY" = true ]; then
  echo "已按 --install-only 结束。"
  exit 0
fi

if [ "$MAS" = true ]; then
  echo "执行 MAS 打包（npm run pack）…"
  NODE_ENV=production npm run pack
  echo "完成。输出通常在 dist/out/ 下（见 bin/pack.js）。"
  exit 0
fi

if [ "$PACK_ONLY" = true ]; then
  echo "执行 pack:darwin:only …"
  npm run pack:darwin:only
else
  echo "执行 pack:darwin（生产 webpack + 未签名 .app）…"
  npm run pack:darwin
fi

echo "完成。应用目录: $ROOT/dist/out/Medis-darwin-x64/Medis.app"
