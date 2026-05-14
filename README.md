# webhook-site-helm

[webhook.site](https://github.com/webhooksite/webhook.site) を OpenShift 上にデプロイするための Helm チャートです。
Ingress の代わりに OpenShift Route を使用します。

## 構成図

```mermaid
graph TD
    Client(["`**クライアント**
    ブラウザ / Webhook送信者`"])

    subgraph OpenShift
        Route["**Route**
        webhook.apps.*
        (HTTP/HTTPS)"]

        subgraph Namespace: webhook-site
            subgraph webhook-site Pod
                WebhookApp["webhooksite/webhook.site
                port: 80"]
            end

            subgraph laravel-echo-server Pod
                EchoApp["webhooksite/laravel-echo-server
                port: 6001"]
            end

            subgraph redis Pod
                RedisApp["redis:alpine
                port: 6379"]
            end

            WebhookSvc["Service: webhook
            port: 8084"]
            EchoSvc["Service: laravel-echo-server
            port: 6001"]
            RedisSvc["Service: redis
            port: 6379"]
        end
    end

    Client -->|"HTTP / HTTPS"| Route
    Route --> WebhookSvc
    WebhookSvc --> WebhookApp

    WebhookApp -->|"cache / queue / broadcast"| RedisSvc
    RedisSvc --> RedisApp

    EchoSvc --> EchoApp
    EchoApp -->|"pub/sub"| RedisSvc
    EchoApp -->|"認証"| WebhookSvc
```

## 構成コンポーネント

| コンポーネント | イメージ | 用途 |
|---|---|---|
| webhook-site | `webhooksite/webhook.site` | Laravel アプリ本体 |
| laravel-echo-server | `webhooksite/laravel-echo-server` | WebSocket サーバ |
| redis | `redis:alpine` | キャッシュ / キュー / ブロードキャスト |

## 前提条件

- OpenShift 4.x クラスタへのアクセス
- Helm 3.x がインストール済み
- デプロイ先 Namespace が作成済み（デフォルト: `webhook-site`）

## インストール

### 1. Namespace の作成

```bash
oc new-project webhook-site
```

### 2. APP_KEY の生成（任意）

`APP_KEY` は省略可能です。省略した場合、チャートが初回インストール時に `base64:` 形式の 32 バイトランダムキーを自動生成して Secret に保存します。`helm upgrade` 以降は既存 Secret の値を使い回すため、キーがローテーションされることはありません。

明示的に指定したい場合は以下で生成できます。

```bash
# PHP が使える場合
php artisan key:generate --show

# openssl で代替
echo "base64:$(openssl rand -base64 32)"
```

### 3. Helm インストール

`APP_KEY` は Kubernetes Secret として管理されます。`APP_URL` はどちらも以下の優先順位で自動生成されるため、最小構成では `APP_KEY` の指定すら不要です。

| 優先度 | 条件 | APP_URL の値 |
|---|---|---|
| 1 | `webhook.appUrl` を指定 | その値をそのまま使用 |
| 2 | `route.host` を指定 | `http(s)://route.host` |
| 3 | 両方とも空 | OpenShift IngressController を参照して自動構築 |

**自動構築される URL の形式（優先度 3 の場合）:**

```
http(s)://webhook-<namespace>.<IngressController の apps ドメイン>
# 例: http://webhook-webhook-site.apps.mycluster.example.com
```

`route.host` は省略可能です。省略した場合は OpenShift がホスト名を自動割り当てし、チャートも IngressController から同じホスト名を導出して `APP_URL` に設定します。

```bash
# route.host を指定する場合（TLS あり）
helm install webhook-site ./chart \
  --set webhook.env.APP_KEY=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx= \
  --set route.host=webhook.apps.mycluster.example.com \
  --set route.tls.enabled=true

# route.host を省略する場合（IngressController から APP_URL を自動取得）
helm install webhook-site ./chart \
  --set webhook.env.APP_KEY=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
```

> **注意:** `helm template`（オフラインレンダリング）では `lookup` が無効なため、APP_URL は空になります。その場合は `webhook.appUrl` で明示指定してください。

#### 既存の Secret を使う場合

Vault や External Secrets Operator などで Secret を別途管理している場合は、`webhook.existingSecret` に Secret 名を指定します。この場合、チャートは Secret を作成しません。

```bash
# Secret を事前に作成
oc create secret generic my-webhook-secret --from-literal=APP_KEY=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=

# existingSecret を指定してインストール
helm install webhook-site ./chart \
  --set webhook.existingSecret=my-webhook-secret \
  --set route.host=webhook.apps.mycluster.example.com \
  --set route.tls.enabled=true
```

## 主な values 一覧

| キー | デフォルト | 説明 |
|---|---|---|
| `namespace` | `webhook-site` | デプロイ先 Namespace |
| `webhook.env.APP_KEY` | `""` | Laravel アプリキー。空の場合は初回インストール時に自動生成 |
| `webhook.existingSecret` | `""` | 既存 Secret 名。指定するとチャートは Secret を作成しない |
| `webhook.appUrl` | `""` | APP_URL を明示指定。省略時は `route.host` → IngressController の順で自動生成 |
| `webhook.env.APP_ENV` | `production` | Laravel 環境 |
| `webhook.env.APP_DEBUG` | `"false"` | デバッグモード |
| `webhook.replicas` | `1` | webhook-site Pod 数 |
| `echoServer.replicas` | `1` | laravel-echo-server Pod 数 |
| `route.host` | `""` | Route のホスト名（空で自動割当） |
| `route.tls.enabled` | `false` | TLS を有効化するか |
| `route.tls.termination` | `edge` | TLS 終端方式（edge / reencrypt / passthrough） |
| `route.tls.insecureEdgeTerminationPolicy` | `Redirect` | HTTP アクセス時の挙動 |

すべての設定は [chart/values.yaml](chart/values.yaml) を参照してください。

## デプロイ後のアクセス方法

割り当てられたホスト名は以下で確認できます。

```bash
oc get route webhook -n webhook-site -o jsonpath='{.spec.host}'
```

そのホスト名をベースに以下の URL を使用します。

### ブラウザでアクセス

```
https://webhook.apps.mycluster.example.com
```

ブラウザで開くとアプリが自動的にユニークな UUID を生成し、そのページに遷移します。

### Webhook の送信先 URL

ブラウザに表示された UUID 付きの URL がそのまま受信エンドポイントです。

```
https://webhook.apps.mycluster.example.com/{uuid}
```

curl での送信例:

```bash
curl -X POST https://webhook.apps.mycluster.example.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -H "Content-Type: application/json" \
  -d '{"hello": "world"}'
```

送信すると、ブラウザ画面にリクエストの内容（メソッド・ヘッダー・ボディなど）がリアルタイムで表示されます。
UUID はブラウザセッションごとに異なるため、複数人が同時に別々の受信エンドポイントを持つことができます。

## アップグレード

```bash
helm upgrade webhook-site ./chart -f my-values.yaml
```

## アンインストール

```bash
helm uninstall webhook-site
```
