# Windows 编译与安装

项目已上传私有仓库 xef0805/ParcelHub。0.2.0 云端编译和 iLoader 安装已完成，用户确认 iPhone 官方网页登录、身份码展示与清单读取可用。

.github/workflows/ios-unsigned.yml 使用 GitHub macOS runner，手动触发。先执行数据检查，再编译 iPhone 目标，产出未签名 IPA；不需要 Apple 账号密码、Cookie 或签名证书。私有仓库运行和产物保存会使用 GitHub Actions 账户额度，超额收费以账户设置为准。

在 Actions 手动运行 main，完成后下载 ParcelHub-unsigned-iphone；ZIP 内是未签名 IPA，产物保留 3 天。

用户已用 iLoader 2.4.0 成功安装。Sideloadly 0.71.1 在本机两种 Anisette 方式均报登录错误 -80046，不再推荐在此环境重复尝试。Windows 上保留 iTunes 和 Apple Mobile Device Support 供 iLoader 连接设备。

更新沿用原 Apple 账号和 Bundle ID 配置，覆盖安装以保留本地数据。免费账号签名需定期续签。不要先删旧 App，也不要将密码、验证码或签名材料上传到源码库。
