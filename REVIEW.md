# Hi Hysteria 项目 Review

## 1. 结论概览

项目已完成较好的模块化拆分：`server/src/` 是源码、`server/hy2.sh` 是可复现生成物；安装恢复、自动配置、客户端配置和 i18n 均已有回归测试。本次执行全部 5 个 `server/test_*.sh`，均通过；`bash -n`、`test_build.sh` 和 `i18n-validate.sh` 也通过。

当前最值得优先处理的是安全边界和失败恢复。脚本以 root 运行并修改服务、防火墙和 `/etc`，但远端可执行文件缺少完整性验证，敏感配置权限也未显式收紧。建议先完成 P0/P1 项，再扩充功能。

## 2. 主要问题（按优先级）

### P0：远端代码和二进制缺少可信校验

- `server/install.sh:66-84`、`server/src/20-net-yaml.sh:5-27` 从 `main` 分支下载脚本后直接安装，仅检查 `hihyV=` 标记；该标记不能证明来源或内容完整性。
- `server/src/50-core.sh:36-75` 只验证 ELF 魔数；`server/src/25-system.sh:234-242` 下载 `yq` 后直接执行。
- `server/src/45-wizard.sh:158`、`server/src/85-actions.sh:228` 下载第三方 WARP 脚本后直接以 root 执行。
- 多处 `wget --no-check-certificate`（如 `server/install.sh:67`、`server/src/50-core.sh:43`）主动关闭 TLS 证书验证，进一步扩大中间人攻击风险。

**建议：** 删除所有 `--no-check-certificate`；发布版本使用固定 tag/commit URL；为 `hy2.sh`、Hysteria、`yq` 和第三方脚本维护 SHA-256（或验证上游签名），校验成功后再原子替换。第三方安装器应固定提交并在执行前展示来源与摘要。

### P0：认证信息可能对本机普通用户可读

`server/src/55-service.sh:70` 和 `server/src/45-wizard.sh:1011-1015` 创建目录和配置前没有设置 `umask` 或显式权限。`config.yaml`、`backup.yaml`、客户端配置包含认证密码、DNS API token、Realm token 和 SOCKS5 密码；在常见 `umask 022` 下，新文件通常为 `0644`。

**建议：** 主入口尽早执行 `umask 077`；配置、证书和结果目录使用 `0700`，敏感文件写完后强制 `chmod 600`。交互读取 token/密码使用 `read -rs`，摘要默认只显示掩码。新增测试断言最终权限。

### P1：YAML/JSON 写入对特殊字符不安全

`server/src/20-net-yaml.sh:163-190` 通过拼接字符串构造 yq 表达式；双引号、反斜杠、换行等输入可能导致解析失败。`server/src/85-actions.sh:239,266-268` 直接把地址、用户名和密码嵌入 yq 程序，既容易破坏配置，也允许输入改变表达式语义。自动安装密码 `HIHY_AUTO_PASSWORD` 没有限制字符集，因此该问题可稳定触发。

**建议：** 使用 yq 的环境变量接口，例如 `VALUE="$value" yq -i '.path = strenv(VALUE)' file`；动态路径也应通过受控映射或 yq 参数传递。为引号、反斜杠、空格、Unicode 和换行增加表驱动测试。

### P1：重配置不是事务操作，失败可能导致服务中断

`server/src/85-actions.sh:86-106` 先停止服务并删除防火墙规则，再调用配置流程；而 `server/src/45-wizard.sh:1005` 会直接删除旧配置。中途下载、证书、yq 或输入处理失败时，没有恢复旧配置和规则的统一机制，后续仍可能执行 `start` 并显示成功。

**建议：** 在临时目录生成并校验完整配置，执行 `hysteria server --test`（若上游支持）或最小启动探测；成功后原子替换。保存旧配置、服务状态和防火墙状态，失败时自动回滚，并让所有关键函数严格传播非零退出码。

### P1：缺少持续集成和强制静态检查

仓库没有 `.github/workflows/`，本次环境也未安装 ShellCheck，因此测试与 `shellcheck -S warning` 依赖贡献者手动执行。生成文件忘记更新、翻译占位符错误或未引用变量可能直到发布后才暴露。

**建议：** 添加 CI，至少运行：

```bash
bash -n server/src/*.sh server/install.sh scripts/*.sh server/test_*.sh
bash scripts/i18n-validate.sh
for t in server/test_*.sh; do bash "$t"; done
shellcheck -S warning server/src/*.sh server/install.sh scripts/*.sh
```

同时把 `server/test_build.sh` 设为合并门禁。

### P2：核心向导模块仍然过大

`server/src/45-wizard.sh` 约 1,359 行，混合输入交互、自动模式、证书供应商、配置生成和安装验证。大量全局变量让函数调用顺序成为隐式依赖，增加测试和重用难度。

**建议：** 拆为 `wizard-input`、`wizard-auto`、`certificate`、`config-render`、`install-validate` 等模块；函数参数显式传递状态，或将状态统一保存到关联数组。优先抽取无副作用的校验和渲染函数。

### P2：并发与临时文件处理不完全一致

- `server/src/10-i18n.sh:29-39` 后台刷新翻译时直接覆盖目标文件，下载中断可能留下空文件，并可能与并发进程互相覆盖。
- `server/src/30-version.sh:67-85` 的锁是“先检查、再创建”普通文件，两个进程可能同时获得锁。
- `server/src/50-core.sh:40` 使用 PID 拼接临时文件，而非 `mktemp`；服务安装还在当前目录使用 `./crontab.tmp`（`server/src/55-service.sh:273-279`）。

**建议：** 所有下载采用“同目录 `mktemp` → 内容校验 → `mv`”；锁使用 `flock` 或原子 `mkdir`；临时文件统一注册 `trap` 清理。

### P2：防火墙代码重复且直接覆盖系统持久化配置

`server/src/60-firewall.sh` 为不同发行版重复拼装命令，并把完整 ruleset 写入 `/etc/nftables.conf`，或通过过滤 `iptables-save` 后整体 restore。该做法与其他防火墙管理工具并存时风险较高，错误也多被忽略。

**建议：** 建立统一后端接口（detect/add/delete/persist），仅管理带唯一 comment/chain 的项目规则；变更前备份，失败时恢复。为 ufw、firewalld、iptables、nft 分别使用命令 mock 做单元测试。

## 3. 测试与质量改进

现有测试的优点是无需 root、使用临时 fixture，执行速度快。后续建议补充：

1. 敏感文件权限与日志脱敏测试。
2. 下载摘要不匹配、TLS 失败和原子更新回滚测试。
3. 特殊字符密码/token 的 YAML、JSON 往返测试。
4. 重配置各阶段故障注入，验证旧服务可恢复。
5. 防火墙命令 mock、重复执行幂等性和卸载不影响无关规则。
6. 各语言完整 JSON 解析及格式占位符“类型、顺序、宽度”一致性；当前校验只统计 `%s/%d` 数量。

## 4. 推荐整改顺序

1. **安全基线：** TLS、固定版本、哈希/签名、`umask 077`、密钥脱敏。
2. **配置可靠性：** yq 安全传参、临时生成、校验、原子替换和回滚。
3. **自动化门禁：** CI、ShellCheck、现有测试和生成物同步检查。
4. **结构治理：** 拆分向导与防火墙模块，减少全局状态和重复实现。

完成前两项后，项目在 root 场景下的供应链风险、凭据泄露风险和安装中断概率都会显著下降。
