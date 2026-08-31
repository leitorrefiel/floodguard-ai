const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const categories = [
  "flooded_road",
  "clogged_drainage",
  "blocked_waterway",
  "overflowing_canal",
  "road_obstruction",
  "damaged_drainage",
  "other",
  "no_visible_hazard",
  "uncertain",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) {
      return json({
        matches_reported_hazard: false,
        detected_category: "uncertain",
        confidence: 0,
        reason: "Image verification is not configured.",
      });
    }

    const body = await req.json();
    const photoUrl = String(body.photo_url ?? "");
    const reportedCategory = String(body.reported_category ?? "other");
    if (!photoUrl.startsWith("http")) {
      return json({
        matches_reported_hazard: false,
        detected_category: "uncertain",
        confidence: 0,
        reason: "A public image URL is required for verification.",
      }, 400);
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-5-mini",
        input: [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text:
                  "Classify whether this image supports a community hazard report. " +
                  `Reported category: ${reportedCategory}. ` +
                  `Allowed categories: ${categories.join(", ")}. ` +
                  "Return only JSON with matches_reported_hazard boolean, detected_category string, confidence number 0-1, and reason string. " +
                  "This is supporting evidence only, not official verification.",
              },
              { type: "input_image", image_url: photoUrl },
            ],
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "hazard_image_verification",
            schema: {
              type: "object",
              additionalProperties: false,
              required: [
                "matches_reported_hazard",
                "detected_category",
                "confidence",
                "reason",
              ],
              properties: {
                matches_reported_hazard: { type: "boolean" },
                detected_category: { type: "string", enum: categories },
                confidence: { type: "number", minimum: 0, maximum: 1 },
                reason: { type: "string" },
              },
            },
          },
        },
      }),
    });

    if (!response.ok) {
      return json({
        matches_reported_hazard: false,
        detected_category: "uncertain",
        confidence: 0,
        reason: "Image verification service failed temporarily.",
      }, 200);
    }

    const result = await response.json();
    const text = result.output_text ??
      result.output?.[0]?.content?.find((item: { text?: string }) => item.text)
        ?.text;
    const parsed = JSON.parse(text);
    return json({
      matches_reported_hazard: Boolean(parsed.matches_reported_hazard),
      detected_category: categories.includes(parsed.detected_category)
        ? parsed.detected_category
        : "uncertain",
      confidence: Number(parsed.confidence ?? 0),
      reason: String(parsed.reason ?? "Image verification completed."),
    });
  } catch (_error) {
    return json({
      matches_reported_hazard: false,
      detected_category: "uncertain",
      confidence: 0,
      reason: "Image verification service is temporarily unavailable.",
    });
  }
});

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
