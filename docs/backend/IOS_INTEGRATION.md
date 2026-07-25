# iOS 后端接入约定

## 环境

- Debug 默认连接 `http://127.0.0.1:8080`，仅允许本机网络明文传输；
- Release 默认连接 `https://api.lingotrip.app`；
- 自动化测试和开发联调可用 `LINGOTRIP_BACKEND_URL` 覆盖地址；
- 生产构建不得通过环境变量或设置页接受用户自定义后端地址。

## 会话

- 客户端只把轮换用 refresh token、会话 ID 和用户 ID 存入 Keychain；
- access token 只保存在进程内存，并在过期前 30 秒刷新；
- 同一时刻的多个请求共用一次 refresh token 轮换，避免旧令牌重放误报；
- API 返回 401 时只自动刷新并重放一次原请求；
- refresh token 被拒绝后清除本机会话，要求用户重新登录；
- 无网络启动且 Keychain 中仍有未过期会话时，可进入只读缓存界面；首次需要服务端操作时仍会刷新并校验会话。

## 身份

- 邮箱注册必须完成服务端发送的验证邮件后才能登录；
- Apple 登录先从服务端获取一次性 nonce，再把 identity token、authorization code 和 challenge ID 一并交给服务端核验；
- Apple authorization code 和 identity token 不写磁盘、不写日志；
- 设备 ID 是 Keychain 中随机生成的安装标识，只用于会话管理，不作为用户身份或广告追踪标识；
- 退出登录以本地凭据清除为最终动作，即使服务器暂时不可达也不会保留可用凭据。

## 后续模块

所有跨平台业务状态通过 `BackendClient` 接入同一套 `/v1` API。SwiftData 只作为按用户隔离的离线缓存；机票、城市解锁、订阅权益和 AI 配额以服务器结果为准。
