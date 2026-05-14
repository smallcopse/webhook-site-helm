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

### 2. APP_KEY の生成

Laravel アプリに必要な 32 文字のアプリキーを生成します。

```bash
php artisan key:generate --show
# 例: base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
```

PHP が手元にない場合は以下のワンライナーで代替できます。

```bash
echo "base64:$(openssl rand -base64 32)"
```

### 3. Helm インストール

```bash
helm install webhook-site ./chart \
  --set webhook.env.APP_KEY=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx= \
  --set webhook.env.APP_URL=https://webhook.apps.mycluster.example.com \
  --set route.host=webhook.apps.mycluster.example.com \
  --set route.tls.enabled=true
```

TLS なしで試す場合（開発用）:

```bash
helm install webhook-site ./chart \
  --set webhook.env.APP_KEY=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx= \
  --set webhook.env.APP_URL=http://webhook.apps.mycluster.example.com \
  --set route.host=webhook.apps.mycluster.example.com
```

Route ホスト名を OpenShift に自動割り当てさせる場合は `route.host` を省略できます。

## 主な values 一覧

| キー | デフォルト | 説明 |
|---|---|---|
| `namespace` | `webhook-site` | デプロイ先 Namespace |
| `webhook.env.APP_KEY` | `""` | Laravel アプリキー（必須） |
| `webhook.env.APP_URL` | `""` | アプリの公開 URL（必須） |
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

`route.host` に設定したホスト名をベースに以下の URL を使用します。

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
