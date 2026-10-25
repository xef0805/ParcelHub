# 没有 Mac 时的编译与安装路线

当前只是本地准备，尚未上传到 GitHub，也未运行云端编译。

## 已准备的配置

`.github/workflows/ios-unsigned.yml` 使用 GitHub macOS runner 编译 iPhone 目标，仅手动触发，不随提交自动运行。

编译不需要 Apple 密码、登录 Cookie 或签名证书；产出未签名 IPA，不能直接点击安装。该流程尚未实际运行，可能仍需修复编译错误。

## 下一步需要用户授权

1. 仅将源码上传到用户的 GitHub 私有仓库。禁止上传 `.private/`、实际包裹快照或浏览器登录资料。
2. 核对 GitHub Actions 剩余额度与预算后，再运行云端编译。私有仓库使用账户额度，超出额度可能产生费用；本项目尚未核对用户账单状态。
3. 得到 IPA 后再选择 Windows 安装方式，例如 AltStore Classic 或 Sideloadly。不要从非官方来源下载。
4. 安装软件、设备信任、开发者模式及 Apple 账号认证，由用户另行确认并在设备或官方界面自行完成；本步骤尚未执行。

免费 Apple 账号的此类个人签名通常需要每 7 天续签。没有 Mac 不代表不能尝试，但仍需云端编译和实际签名安装测试，不能把本地浏览器当作原生 App 的验收结果。

官方依据（查询于 2026-10-25）：

- [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [AltStore Windows 安装指南](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [Sideloadly 官方 FAQ](https://sideloadly.io/faq)
