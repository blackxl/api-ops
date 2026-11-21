# 宝塔面板部署 api-ops（ops.58api.net）

面向宝塔面板的点击步骤。本文件是部署说明，**不会**在服务器上执行，也**不**改 DNS。

镜像目标：

- `ghcr.io/blackxl/api-ops:latest`（只在 **main 分支的 push** 上移动）
- `ghcr.io/blackxl/api-ops:sha-<完整 40 位 commit>`（不可变，先于 `latest` 推送）
- 架构：`linux/amd64`

**现在还不能把镜像当成已经发布。** `.github/workflows/ci.yml` 的 `Publish GHCR (main only)` 只有在合并进 `main` 并且该 job 成功之后才会推送。Pull request 只构建和测试，**不会**推 `latest`。在那次 Actions 成功之前，服务器上 `docker pull ghcr.io/blackxl/api-ops:latest` 会失败，这是预期结果，不要改去拉别的仓库的镜像。

对应文件：

- 编排：`docker-compose.prod.yml`
- 环境变量模板：`.env.production.example`（复制成服务器上的 `.env`，不要提交）

## 机器预算

按约 **1.9 GiB 可用内存**、4 核来限制，三个容器的上限合计 **1120 MiB**，把余量留给宝塔和系统。

| 服务 | 内存上限 | 预留 | CPU 上限 |
|---|---|---|---|
| postgres | 320 MiB | 96 MiB | 0.50 |
| redis | 80 MiB | 24 MiB | 0.25 |
| api | 720 MiB | 128 MiB | 1.50 |

Postgres 和 Redis **不映射到宿主机端口**。api 只映射 `127.0.0.1:8088`。

## 1. 等 GitHub 构建完成

1. 打开仓库 `https://github.com/blackxl/api-ops` → Actions。
2. 合并进 `main` 之后，等名为 **Publish GHCR (main only)** 的 job 变绿。
3. 日志里会有 `ghcr.io/blackxl/api-ops:sha-<commit>` 和 `latest`。把那条 sha 标签记下来，回滚时用它，不要只依赖 `latest`。

这次打包**没有**改账号级权限。第一次推送后，包默认可能是私有的，Actions 里的 `GITHUB_TOKEN` 不会替你改成公开。需要你在网页上做一次：

1. 打开 `https://github.com/blackxl/api-ops/pkgs/container/api-ops`（第一次成功推送之后才会出现）。
2. Package settings → Change visibility。
3. 若服务器要匿名 `docker pull`，改成 Public。
4. 若保持 Private：在 GitHub → Settings → Developer settings 建一个**只含** `read:packages` 的 token，只放在服务器的 `docker login ghcr.io`，不要写进仓库。用户名用 `blackxl`。

## 2. 在面板里准备目录和 `.env`

1. 软件商店 → 已安装：确认 **Docker 管理器** 已安装。不要在这台机器上再加别的大容器。
2. 文件 → 新建目录，例如 `/www/dk_project/api-ops`。
3. 把仓库里的 `docker-compose.prod.yml` 上传到这个目录（或在面板编辑器里粘贴该文件全文）。
4. 在同一目录新建 `.env`。内容从 `.env.production.example` 复制，把每一个 `PLEASE_FILL_*` 换成真实值。
5. 在面板终端里生成随机串，再贴回 `.env`，不要把终端输出提交到 git：

```bash
openssl rand -hex 32
```

至少填这些项：

| 变量 | 作用 |
|---|---|
| `OPS_PG_PASSWORD` | 本机 Postgres 密码。只用字母和数字，不要空格 |
| `OPS_API_TOKEN` | 至少 32 字符，进程没有它会拒绝启动 |
| `JWT_SECRET` | 登录令牌签名 |
| `ADMIN_PASSWORD` | 第一次启动、用户表为空时创建的 admin 密码 |
| `API_OPS_RO_DSN` | New API 数据库只读连接，见下一节 |
| `upstream_ADMIN_BASE_URL` / `API_OPS_ADMIN_TOKEN` | New API 管理 API |
| `CORS_ALLOWED_ORIGINS` | `https://ops.58api.net` |

`OPS_DB_DSN` 不用自己写。编排会用 `OPS_PG_PASSWORD` 注入 `host=postgres`。

## 3. New API 数据库地址

`API_OPS_RO_DSN` 的 `host=` 填**你配置的私有 DNS 名或容器名**，例如 New API 那套 Compose 里 Postgres 的服务名。用户名用只读账号，密码只放在服务器 `.env`。

不要在仓库或编排文件里写死某一段桥接 IP。仓库里没有、也不要加入固定地址。

如果 New API 的数据库在另一套 Docker 网络里：宝塔 → Docker → 网络，看它的网络名称。在编排里给 `api` 服务再加一个 `external: true` 的网络，`name` 用你刚看到的那个名字，然后把 `host=` 写成那个容器名。默认的 `docker-compose.prod.yml` 不引用任何外部网络，避免在名字未知时启动失败。

## 4. 用面板启动容器

1. Docker → 编排 / Compose → 添加项目，目录选 `/www/dk_project/api-ops`，编排文件选 `docker-compose.prod.yml`。
2. 确认端口是 `127.0.0.1:8088:8088`，不是 `8088:8088`（后者等于 `0.0.0.0`）。
3. 先不要点启动，直到第 1 节的 Publish job 已经成功。然后在镜像管理里拉取 `ghcr.io/blackxl/api-ops:latest`，平台选 `linux/amd64`。
4. 启动项目。三个容器应在跑：`api-ops-postgres`、`api-ops-redis`、`api-ops-api`。
5. 在容器终端或面板终端执行：

```bash
docker exec api-ops-api wget -q -O - -T 3 http://127.0.0.1:8088/healthz
```

看到 `{"ok":true}` 再做网站反代。健康检查用的是 Alpine 自带的 BusyBox `wget`（`/usr/bin/wget` → `/bin/busybox`），镜像里没有单独再装 wget。

账单 ZIP 卷是命名卷 `api-ops-billing-exports`，挂在容器内 `/data/billing-exports`。镜像里该目录属主是 `app`（uid 100，gid 101）。**新建的**命名卷会继承这个属主，应用用户可以直接写。如果复用以前 root 拥有的旧目录，需要在面板里改一次属主为 `100:101`，本说明不替你在服务器上执行。

## 5. 网站 ops.58api.net

本仓库变更不修改 DNS。你自己把 `ops.58api.net` 指到这台机器之后，再在面板里加站点。

1. 网站 → 添加站点 → 域名 `ops.58api.net`。不要让这个站点再占 8088。
2. 站点设置 → SSL → 申请证书并开启强制 HTTPS。
3. 反向代理 → 目标 URL 填 `http://127.0.0.1:8088`。发送域名用 `$host`。
4. 打开该站点的配置文件，在 `server` 里、反代 `location /` **之前**加上：

```nginx
location ^~ /api/ws/ {
    default_type text/plain;
    return 403;
}
```

保存并重载 Nginx。

这一步是必须的。当前进程把 `/api/ws/` 挂在鉴权中间件之外（`MountWebSocket` 传入的 auth 是空的），WebSocket **没有登录校验**。这次镜像打包没有改这段行为，也不能代替这层拦截。反代如果开了“WebSocket 支持”，也仍然要让上面的 `location` 先生效，不要把 `/api/ws/` 代理进容器。

用浏览器打开 `https://ops.58api.net/` 应出现登录页。用面板终端确认拦截：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://ops.58api.net/api/ws/global
```

期望 `403`。`/healthz` 仍可由本机 `127.0.0.1:8088` 访问，不必对公网开放。

## 6. 这次没有解决的事

- 没有登录的 WebSocket 仍然在容器里面。公网靠第 5 节的 Nginx 规则挡住。
- GHCR 包是否公开，要你在包设置里点一次。
- `.env` 里的 token、数据库密码、New API 地址只存在于服务器。
- 回滚：把编排里的镜像改成某次 `sha-<commit>` 再启动，不要假定 `latest` 永远可追溯。
