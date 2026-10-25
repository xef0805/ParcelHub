# 涂涂取件：手动编译与更新

不需要 Mac，也不需要在 GitHub 输入 Apple 账号或密码。GitHub 负责编译，iLoader 负责在电脑上签名安装。

## 每次编译

1. 登录 GitHub，打开 https://github.com/xef0805/ParcelHub/actions/workflows/ios-unsigned.yml 。
2. 点击右侧 Run workflow，分支选 main，再点绿色 Run workflow。
3. 刷新页面，点击刚出现的新运行记录。不要在旧记录上点 Re-run all jobs 来获取新代码：重新运行旧记录仍会使用旧提交。
4. 等待测试与 build 全部结束。绿色 Success 表示编译及安装包打包成功；红色 Failure 表示失败，打开 build 查看红色步骤，复制运行记录链接供排查。
5. 成功后在 Summary 页面向下滚到 Artifacts，点击 ParcelHub-unsigned-iphone 下载 ZIP。也可以点击顶部 Artifacts 下的数量跳转。
6. 解压 ZIP 得到 ParcelHub-unsigned.ipa；IPA 本身不需要继续解压。安装包目前保留 3 天。

本轮版本为 0.4.0。工程、编译方案和安装包文件名继续使用 ParcelHub，以保持覆盖更新兼容；安装后的应用显示名为“涂涂取件”。

## 安装到自己的 iPhone

1. 数据线连接并解锁 iPhone，运行 iLoader。
2. 使用此前安装时相同的 Apple 账号和 Bundle ID 设置，选择 Import IPA，导入新 IPA。
3. 按提示签名并覆盖安装。不要先卸载旧 App，否则可能丢失本地记录。
4. 安装后检查 我的 → 设置 中的版本、短信识别、地点绑定、排序和自动刷新。

免费个人签名需定期续签。若只是签名到期、代码没有更新，可用已有安装包续签，不必每次重新云端编译。

## 需要区分

- 上传源码不等于已编译；云端绿色不等于已安装到手机。
- 预览、真实 iOS 页面和不同平台登录分别验证。自动刷新实际延迟需在手机测试。
- 本流程只手动触发，上传代码不会自动开始编译。私有仓库编译及产物会使用 GitHub Actions 额度。

官方操作说明：https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
