(function process(request, response) {
  try {
    var body = request.body.data;
    var gcpIncident = body.incident;

    // ペイロード検証
    if (!gcpIncident) {
      response.setStatus(400);
      response.setBody({
        error: {
          message: "Invalid payload: missing incident object",
          status: "failure"
        }
      });
      return;
    }

    // state=closed → 既存インシデントを解決して返す
    if (gcpIncident.state === "closed") {
      var existing = new GlideRecord("incident");
      existing.addQuery("correlation_id", gcpIncident.incident_id);
      existing.query();
      if (existing.next()) {
        existing.setValue("state", 6); // Resolved
        existing.setValue("close_code", "Solved (Permanently)");
        existing.setValue("close_notes",
          "Auto-resolved by Cloud Monitoring at " + new GlideDateTime());
        existing.update();
        response.setBody({
          result: {
            status: "resolved",
            incident_number: existing.getValue("number"),
            sys_id: existing.getUniqueValue()
          }
        });
      } else {
        response.setStatus(404);
        response.setBody({
          error: {
            message: "No matching incident found for correlation_id: " + gcpIncident.incident_id,
            status: "failure"
          }
        });
      }
      return;
    }

    // 重複チェック — 同じ correlation_id のオープンインシデントがあればスキップ
    var dup = new GlideRecord("incident");
    dup.addQuery("correlation_id", gcpIncident.incident_id);
    dup.addActiveQuery();
    dup.query();
    if (dup.next()) {
      response.setBody({
        result: {
          status: "duplicate",
          incident_number: dup.getValue("number"),
          sys_id: dup.getUniqueValue()
        }
      });
      return;
    }

    // 新規インシデント作成
    var gr = new GlideRecord("incident");
    gr.initialize();
    gr.setValue("short_description", "[GCP Alert] " + gcpIncident.policy_name);
    gr.setValue("description",
      "Summary: "    + gcpIncident.summary              + "\n" +
      "Condition: "  + gcpIncident.condition_name        + "\n" +
      "Resource: "   + gcpIncident.resource_display_name + "\n" +
      "Project: "    + gcpIncident.scoping_project_id    + "\n" +
      "Console URL: " + gcpIncident.url
    );
    gr.setValue("urgency", 1);
    gr.setValue("impact", 1);
    gr.setValue("category", "Software");
    gr.setValue("subcategory", "Operating System");
    gr.setValue("correlation_id", gcpIncident.incident_id);
    gr.setValue("assignment_group", "Cloud SRE");
    var sys_id = gr.insert();

    response.setBody({
      result: {
        status: "success",
        incident_number: gr.getValue("number"),
        sys_id: sys_id
      }
    });

  } catch (e) {
    response.setStatus(500);
    response.setBody({
      error: { message: e.message, status: "failure" }
    });
  }
})(request, response);
