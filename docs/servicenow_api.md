# ServiceNow Scripted REST API — Cloud Monitoring Webhook 受信仕様

## 概要

Google Cloud Monitoring のアラート通知を ServiceNow で受信し、インシデントを自動起票するための Scripted REST API 仕様。

## エンドポイント

| 項目 | 値 |
|---|---|
| Method | `POST` |
| Path | `/api/<scope>/cloud_monitoring_webhook` |
| Content-Type | `application/json` |
| 認証 | Basic Auth（インテグレーション用ユーザー） |

## リクエスト（Cloud Monitoring Webhook ペイロード）

Cloud Monitoring の Notification Channel (Webhook) から送信される JSON:

```json
{
  "incident": {
    "incident_id": "0.abcdef1234567890",
    "scoping_project_id": "my-gcp-project",
    "scoping_project_number": 123456789,
    "url": "https://console.cloud.google.com/monitoring/alerting/incidents/...?project=my-gcp-project",
    "started_at": 1704067200,
    "ended_at": null,
    "state": "open",
    "resource_id": "",
    "resource_name": "servicenow-sre-poc",
    "resource_display_name": "servicenow-sre-poc",
    "resource_type_display_name": "Cloud Run Revision",
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
    "policy_user_labels": {},
    "condition_name": "5xx error ratio > 1%",
    "condition": {
      "name": "projects/my-gcp-project/alertPolicies/12345/conditions/67890",
      "displayName": "5xx error ratio > 1%"
    },
    "summary": "5xx error ratio for servicenow-sre-poc is above the threshold of 1%."
  },
  "version": "1.2"
}
```

### 主要フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `incident.incident_id` | string | Cloud Monitoring 側のインシデント ID |
| `incident.state` | string | `open` または `closed` |
| `incident.started_at` | number | 発生時刻（Unix epoch 秒） |
| `incident.ended_at` | number / null | 復旧時刻（未復旧は `null`） |
| `incident.summary` | string | アラートの要約文 |
| `incident.policy_name` | string | アラートポリシー名 |
| `incident.condition_name` | string | 条件名 |
| `incident.resource.labels` | object | 対象リソースのラベル |
| `incident.url` | string | Cloud Console のインシデント URL |

## レスポンス

### 成功時（200）

```json
{
  "result": {
    "status": "success",
    "incident_number": "INC0012345",
    "sys_id": "a1b2c3d4e5f6..."
  }
}
```

### エラー時（400 / 500）

```json
{
  "error": {
    "message": "Invalid payload: missing incident object",
    "status": "failure"
  }
}
```

## ServiceNow 側実装ガイド

### 1. Scripted REST API の作成

- **Name**: Cloud Monitoring Webhook
- **API ID**: `cloud_monitoring_webhook`
- **Resource Path**: `/cloud_monitoring_webhook`（POST）

### 2. スクリプト例

```javascript
(function process(request, response) {
  try {
    var body = request.body.data;
    var incident = body.incident;

    if (!incident) {
      response.setStatus(400);
      response.setBody({
        error: { message: "Invalid payload: missing incident object", status: "failure" }
      });
      return;
    }

    // state=closed の場合は既存インシデントを解決
    if (incident.state === "closed") {
      var existing = new GlideRecord("incident");
      existing.addQuery("correlation_id", incident.incident_id);
      existing.query();
      if (existing.next()) {
        existing.setValue("state", 6); // Resolved
        existing.setValue("close_code", "Solved (Permanently)");
        existing.setValue("close_notes", "Auto-resolved by Cloud Monitoring at " + new GlideDateTime());
        existing.update();
        response.setBody({
          result: { status: "success", incident_number: existing.getValue("number"), sys_id: existing.getUniqueValue() }
        });
      }
      return;
    }

    // 新規インシデント作成
    var gr = new GlideRecord("incident");
    gr.initialize();
    gr.setValue("short_description", "[GCP] " + incident.summary);
    gr.setValue("description",
      "Policy: " + incident.policy_name + "\n" +
      "Condition: " + incident.condition_name + "\n" +
      "Resource: " + incident.resource_display_name + "\n" +
      "Console: " + incident.url
    );
    gr.setValue("urgency", 1);
    gr.setValue("impact", 1);
    gr.setValue("category", "Software");
    gr.setValue("subcategory", "Operating System");
    gr.setValue("correlation_id", incident.incident_id);
    gr.setValue("assignment_group", "Cloud SRE");
    var sys_id = gr.insert();

    response.setBody({
      result: { status: "success", incident_number: gr.getValue("number"), sys_id: sys_id }
    });

  } catch (e) {
    response.setStatus(500);
    response.setBody({
      error: { message: e.message, status: "failure" }
    });
  }
})(request, response);
```

### 3. Cloud Monitoring 通知チャンネル設定

```
Type:       Webhook
URL:        https://<instance>.service-now.com/api/<scope>/cloud_monitoring_webhook
Auth:       Basic Auth（ServiceNow インテグレーション用ユーザー）
```
