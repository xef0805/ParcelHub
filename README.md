# 拾件 ParcelHub · 官方网页读取验证版

目标：个人自用，不读取到站短信；读取本人登录后的官方待取件页面，直接显示官方身份码。

## 本轮实际验证（2026-10-25）

- 用户自行登录后，淘宝官方身份码页真实显示已认证的取件条形码。
- 官方待取件页首次提示接口超时，重新加载后显示 2 件真实包裹。
- 项目同一份 shared/cainiao-reader.js 在该实际页面运行，返回 ready，读取数量与页面数量均为 2。
- 读取取件码、快递公司、运单号与站点，不保存收件人姓名、手机号、身份码或登录凭证。
- 尚未在驿站扫码出库，也未验证全部购买平台、家庭号码与末端系统覆盖。

## Windows 现在可体验

双击「打开预览.cmd」，或访问正在运行的 http://127.0.0.1:8765/preview/ 。

首页可直接打开官方身份码和待取件网页。不同浏览器需要在对应官方页面分别登录。

预览显示本次验证读取的真实快照，并标注来源、读取时间；它不是持续后台同步。旧演示记录已隐藏但未删除，手动记录保留。

快照仅放在本机 .private/official-snapshot.json，已加入 .gitignore，不属于源码或测试样例。浏览器副本保存在本机 localStorage，不上传服务器。关闭预览窗口可停止本机服务。

## 原生 iOS 使用流程

在 Mac 上用 Xcode 打开 ios/ParcelHub.xcodeproj，运行 ParcelHub scheme：

1. 打开「菜鸟官方身份码 / 待取件」。
2. 在 App 内官方网页完成登录。WebKit 会话与 Windows 浏览器独立，需分别登录。
3. 身份码页直接显示官方网页，不复制、缓存或重画条形码。
4. 切换到待取件，加载完成后尝试读取；也可点击「读取当前待取件到拾件」。
5. 完整读取后返回清单，按快递公司和运单号合并，保留取件码前导零。

页面超时、登录失效、结构变化或数量不符时保留原记录，不显示成零件。本次官方清单不再出现的记录只移出当前快照，不伪造已取状态。

**iOS 工程未在 Mac 编译、未在 iPhone 实测、未生成 IPA。浏览器通过不等于真机通过。** 真机运行前需要选择自己的开发团队，修改默认 Bundle Identifier com.example.ParcelHub。

## 尚未完成

- 驿收发、丰巢等其他平台的登录、包裹读取和凭证。
- Windows 预览持续自动刷新官方页面的运行机制。
- iPhone 登录、读取、身份码刷新与驿站扫码的完整测试。
- 页面分页、多个号码及跨来源重复场景的扩展验证。

## 检查

运行 node --test tests/model.test.mjs tests/official-reader.test.mjs ，当前 13 项通过。测试均为虚构数据，无实际取件码或运单号。

Mac 编译：xcodebuild -project ios/ParcelHub.xcodeproj -scheme ParcelHub -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build

## 文件与复用边界

ios/ 为 SwiftUI / WebKit 工程；shared/catalog.json 为平台目录；shared/cainiao-reader.js 为可见页面读取组件；preview/ 为 Windows 预览；.private/ 为仅本机快照。

原先参考的 PickTool、BiuLand、fluwx 与 ExpressAssistant 只提供架构思路，未复制其源码或品牌素材。当前使用官方网页正常登录与可见页面读取，不调用逆向接口，也不绕过验证码、权限或访问控制。
