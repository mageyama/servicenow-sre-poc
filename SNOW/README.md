# SNOW - ServiceNow Scripted REST API

Google Cloud Monitoring のアラートを受信し、ServiceNow にインシデントを自動起票する Scripted REST API。

## PDI 設定手順

### 1. Scripted REST API の作成

`System Web Services > Scripted REST APIs > New` から作成する。

| 項目 | 値 |
|---|---|
| Name | Cloud Monitoring Webhook |
| API ID | `cloud_monitoring_webhook` |

### 2. Resource の追加

| 項目 | 値 |
|---|---|
| HTTP Method | `POST` |
| Relative path | `/cloud_monitoring_webhook` |
| Script | `cloud_monitoring_webhook.js` の内容を貼り付け |

### 3. 認証

インテグレーション用ユーザーに以下のロールを付与する。

- `rest_api_explorer`
- `itil`

## 呼び出し例

### インシデント起票（state: open）

```bash
curl -X POST \
  "https://<instance>.service-now.com/api/<scope>/cloud_monitoring_webhook" \
  -u "integration_user:password" \
  -H "Content-Type: application/json" \
  -d '{
    "incident": {
      "incident_id": "0.abc123",
      "scoping_project_id": "my-gcp-project",
      "scoping_project_number": 123456789,
      "url": "https://console.cloud.google.com/monitoring/alerting/incidents/...?project=my-gcp-project",
      "started_at": 1704067200,
      "ended_at": null,
      "state": "open",
      "resource_display_name": "servicenow-sre-poc",
      "resource": {
        "type": "cloud_run_revision",
        "labels": {
          "project_id": "my-gcp-project",
          "service_name": "servicenow-sre-poc",
          "revision_name": "servicenow-sre-poc-00001-abc",
          "location": "asia-northeast1"
        }
      },
      "metric": {
        "type": "run.googleapis.com/request_count",
        "displayName": "Request count"
      },
      "policy_name": "Cloud Run 5xx Error Rate",
      "condition_name": "5xx error ratio > 1%",
      "condition": {
        "name": "projects/my-gcp-project/alertPolicies/12345/conditions/67890",
        "displayName": "5xx error ratio > 1%"
      },
      "summary": "5xx error ratio for servicenow-sre-poc is above the threshold of 1%."
    },
    "version": "1.2"
  }'
```

レスポンス（成功）:

```json
{
  "result": {
    "status": "success",
    "incident_number": "INC0012345",
    "sys_id": "a1b2c3d4e5f6..."
  }
}
```

### インシデント自動解決（state: closed）

```bash
curl -X POST \
  "https://<instance>.service-now.com/api/<scope>/cloud_monitoring_webhook" \
  -u "integration_user:password" \
  -H "Content-Type: application/json" \
  -d '{
    "incident": {
      "incident_id": "0.abc123",
      "state": "closed",
      "ended_at": 1704070800,
      "summary": "5xx error ratio for servicenow-sre-poc has returned to normal."
    },
    "version": "1.2"
  }'
```

レスポンス（解決済み）:

```json
{
  "result": {
    "status": "resolved",
    "incident_number": "INC0012345",
    "sys_id": "a1b2c3d4e5f6..."
  }
}
```

### エラーレスポンス

ペイロード不正（400）:

```json
{
  "error": {
    "message": "Invalid payload: missing incident object",
    "status": "failure"
  }
}
```

サーバーエラー（500）:

```json
{
  "error": {
    "message": "エラー詳細",
    "status": "failure"
  }
}
```

## スクリプトの動作

| 受信した state | 動作 |
|---|---|
| `open` | 新規インシデントを起票（重複時は既存番号を返却） |
| `closed` | `correlation_id` で既存インシデントを検索し Resolved に更新 |

### フィールドマッピング

| ServiceNow フィールド | 値 |
|---|---|
| `short_description` | `[GCP Alert] ` + アラートポリシー名 |
| `description` | Summary / Condition / Resource / Project / Console URL |
| `correlation_id` | Cloud Monitoring の `incident_id` |
| `urgency` | 1 (High) |
| `impact` | 1 (High) |
| `category` | Software |
| `assignment_group` | Cloud SRE |
