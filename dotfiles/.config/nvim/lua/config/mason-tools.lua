-- Mason 工具版本清单（唯一来源）
-- * lua/plugins/mason.lua 读取这里的名字，告诉 Mason 需要哪些工具
-- * scripts/bootstrap.sh 读取这里的版本，在镜像构建时按固定版本安装
-- 升级某个工具：修改版本号 → 重建镜像。可用 :Mason 查看最新版本。
return {
  -- TypeScript / JavaScript（node、bun、react 都走 vtsls）
  ["vtsls"] = "0.3.0",
  -- Vue 单文件组件
  ["vue-language-server"] = "3.3.11",
  -- ESLint 检查（提供 eslint LSP）与 JSON（jsonls）同属 vscode-langservers-extracted
  ["eslint-lsp"] = "4.10.0",
  ["json-lsp"] = "4.10.0",
  -- 格式化
  ["prettier"] = "3.9.8",
  -- YAML / TOML
  ["yaml-language-server"] = "1.24.0",
  ["taplo"] = "0.10.0",
  -- Dockerfile / docker-compose
  ["dockerfile-language-server"] = "0.15.0",
  ["docker-compose-language-service"] = "1.0.0",
  ["hadolint"] = "v2.15.1",
  -- 编辑本 nvim 配置（Lua）与 shell 脚本时使用
  ["lua-language-server"] = "3.19.1",
  ["shfmt"] = "v3.14.1",
}
