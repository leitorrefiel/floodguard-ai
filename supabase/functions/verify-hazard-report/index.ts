import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const floodTypes = new Set(["floodedRoad", "overflowingCanal"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Supabase service configuration is missing." }, 500);
    }

    const { report_id } = await req.json();
    if (!report_id) return json({ error: "report_id is required." }, 400);

    console.log(`[Verification] Starting report verification: ${report_id}`);
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data: report, error: reportError } = await supabase
      .from("hazard_reports")
      .select("*")
      .eq("id", report_id)
      .single();

    if (reportError || !report) {
      console.error("[Verification] report read failed:", reportError);
      return json({ error: "Report could not be read." }, 404);
    }

    const result = await evaluateReport(report, supabase);
    const { error: updateError } = await supabase
      .from("hazard_reports")
      .update({
        status: result.status,
        confidence_score: result.confidence_score,
        verification_state: "completed",
        verification_reason: result.verification_reason,
        verification_evidence: result.verification_evidence,
        ai_image_score: result.verification_evidence.image?.confidence ?? null,
        weather_support:
          result.verification_evidence.weather?.support === "moderate" ||
          result.verification_evidence.weather?.support === "heavy",
        hazard_context_support: false,
        nearby_report_count:
          result.verification_evidence.nearby_reports?.count ?? 0,
        last_verified_at: result.last_verified_at,
        verification_updated_at: result.last_verified_at,
      })
      .eq("id", report_id);

    if (updateError) {
      console.error("[Verification] Supabase update failed:", updateError);
      return json({ error: "Verification update failed." }, 500);
    }

    console.log(
      `[Verification] Supabase update success: ${report_id} ${result.status} ${result.confidence_score}/100`,
    );
    return json(result);
  } catch (error) {
    console.error("[Verification] unexpected failure:", error);
    return json({ error: "Verification failed unexpectedly." }, 500);
  }
});

async function evaluateReport(
  report: Record<string, unknown>,
  supabase: ReturnType<typeof createClient>,
) {
  let score = 0;
  const signals: string[] = [];
  const evidence: Record<string, unknown> = {};
  const latitude = Number(report.latitude);
  const longitude = Number(report.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return {
      status: "rejected",
      confidence_score: 0,
      verification_reason: "Rejected because the report has invalid map coordinates.",
      verification_evidence: {
        location: { valid: false, reason: "Invalid latitude/longitude." },
      },
      last_verified_at: new Date().toISOString(),
    };
  }

  score += 10;
  console.log("[Verification] location score: +10");
  signals.push("Valid GPS/map location");
  evidence.location = { valid: true, latitude, longitude };

  const photoPath = String(report.photo_path ?? "");
  const photoUrl = photoPath
    ? await createSignedPhotoUrl(supabase, photoPath)
    : String(report.photo_url ?? "");
  if (photoUrl.trim()) {
    score += 15;
    console.log("[Verification] photo score: +15");
    signals.push("Photo evidence provided");
  } else {
    console.log("[Verification] photo score: +0");
  }

  const image = await verifyPhoto(photoUrl, reportTypeToVerificationValue(String(report.type ?? "other")));
  evidence.image = image;
  if (image.unavailable) {
    console.log("[Verification] AI score: +0 unavailable");
    signals.push("Image verification temporarily unavailable");
  } else if (image.matches_reported_hazard && image.confidence >= 0.75) {
    score += 25;
    console.log("[Verification] AI score: +25");
    signals.push("Photo appears strongly consistent with the reported hazard");
  } else if (image.matches_reported_hazard && image.confidence >= 0.45) {
    score += 15;
    console.log("[Verification] AI score: +15");
    signals.push("Photo appears moderately consistent with the reported hazard");
  } else if (image.detected_category === "no_visible_hazard") {
    score -= 10;
    console.log("[Verification] AI score: -10");
    signals.push("Image check did not find a visible matching hazard");
  } else {
    console.log("[Verification] AI score: +0 uncertain");
    signals.push("Image verification was uncertain");
  }

  const weather = await getWeather(latitude, longitude, String(report.type ?? ""));
  evidence.weather = weather.evidence;
  score += weather.score;
  console.log(`[Verification] weather score: +${weather.score}`);
  signals.push(...weather.signals);

  const nearby = await getNearbyReports(report, supabase);
  evidence.nearby_reports = {
    count: nearby,
    radius_meters: 250,
    window_hours: 3,
  };
  const nearbyScore = nearby * 20;
  score += nearbyScore;
  console.log(`[Verification] nearby report score: +${nearbyScore}`);
  if (nearby > 0) {
    signals.push(
      `${nearby} independent nearby matching report${nearby === 1 ? "" : "s"}`,
    );
  }

  evidence.official_hazard_context = {
    available: false,
    reason:
      "PAGASA/MGB/GeoRisk machine-readable hazard context is not configured.",
  };
  console.log("[Verification] official hazard context score: +0 unavailable");

  score = Math.max(0, Math.min(100, score));
  const status = score >= 70 ? "high_confidence" : "pending";
  console.log(`[Verification] final confidence: ${score}`);
  console.log(`[Verification] status: ${status}`);

  return {
    status,
    confidence_score: score,
    verification_state: "completed",
    verification_reason:
      `${labelStatus(status)}. Supporting evidence: ${signals.join(", ")}.`,
    verification_evidence: evidence,
    last_verified_at: new Date().toISOString(),
  };
}

async function verifyPhoto(photoUrl: string, type: string) {
  if (!photoUrl.startsWith("http")) {
    return {
      matches_reported_hazard: false,
      detected_category: "uncertain",
      confidence: 0,
      reason: "Image verification unavailable because no public uploaded photo URL is available.",
      unavailable: true,
    };
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiKey) {
    return {
      matches_reported_hazard: false,
      detected_category: "uncertain",
      confidence: 0,
      reason: "Image verification is not configured.",
      unavailable: true,
    };
  }

  try {
    const response = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/verify-hazard-photo`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_ANON_KEY") ?? ""}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          photo_url: photoUrl,
          reported_category: type,
        }),
      },
    );
    if (!response.ok) throw new Error(`status ${response.status}`);
    return { ...(await response.json()), unavailable: false };
  } catch (error) {
    console.error("[Verification] AI image verification failed:", error);
    return {
      matches_reported_hazard: false,
      detected_category: "uncertain",
      confidence: 0,
      reason: "Image verification service is temporarily unavailable.",
      unavailable: true,
    };
  }
}

async function createSignedPhotoUrl(
  supabase: ReturnType<typeof createClient>,
  path: string,
) {
  try {
    const { data, error } = await supabase.storage
      .from("hazard-report-photos")
      .createSignedUrl(path, 600);
    if (error) throw error;
    return data.signedUrl;
  } catch (error) {
    console.error("[Verification] signed photo URL failed:", error);
    return "";
  }
}

function reportTypeToVerificationValue(type: string) {
  switch (type) {
    case "floodedRoad":
      return "flooded_road";
    case "cloggedDrainage":
      return "clogged_drainage";
    case "blockedWaterway":
      return "blocked_waterway";
    case "overflowingCanal":
      return "overflowing_canal";
    case "roadObstruction":
      return "road_obstruction";
    case "damagedDrainage":
      return "damaged_drainage";
    default:
      return "other";
  }
}

async function getWeather(latitude: number, longitude: number, type: string) {
  try {
    const url = new URL("https://api.open-meteo.com/v1/forecast");
    url.searchParams.set("latitude", String(latitude));
    url.searchParams.set("longitude", String(longitude));
    url.searchParams.set("current", "temperature_2m,precipitation,rain");
    url.searchParams.set("daily", "precipitation_sum");
    url.searchParams.set("timezone", "auto");
    url.searchParams.set("forecast_days", "1");
    const response = await fetch(url);
    if (!response.ok) throw new Error(`status ${response.status}`);
    const data = await response.json();
    const currentRain =
      Number(data.current?.rain ?? 0) + Number(data.current?.precipitation ?? 0);
    const forecastRain = Number(data.daily?.precipitation_sum?.[0] ?? 0);
    const rainRelevant = floodTypes.has(type);
    const signals: string[] = [];
    let score = 0;
    let support = "none";
    if (rainRelevant && currentRain >= 7) {
      score += 15;
      support = "heavy";
      signals.push("Heavy rainfall detected near report location");
    } else if (rainRelevant && currentRain >= 2) {
      score += 8;
      support = "moderate";
      signals.push("Moderate rainfall detected near report location");
    }
    if (rainRelevant && forecastRain >= 10) {
      score += 8;
      signals.push("Forecast rainfall may support flood conditions");
    }
    return {
      score,
      signals,
      evidence: {
        available: true,
        rain_relevant: rainRelevant,
        current_rain_mm: currentRain,
        forecast_rain_mm: forecastRain,
        support,
      },
    };
  } catch (error) {
    console.error("[Verification] weather check failed:", error);
    return {
      score: 0,
      signals: ["Some verification checks are temporarily unavailable"],
      evidence: {
        available: false,
        reason: "Weather check temporarily unavailable.",
      },
    };
  }
}

async function getNearbyReports(
  report: Record<string, unknown>,
  supabase: ReturnType<typeof createClient>,
) {
  const createdAt = new Date(String(report.created_at ?? new Date().toISOString()));
  const since = new Date(createdAt.getTime() - 3 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("hazard_reports")
    .select("id,user_id,type,latitude,longitude,created_at,status")
    .eq("type", report.type)
    .gte("created_at", since);
  if (error || !data) {
    console.error("[Verification] nearby report read failed:", error);
    return 0;
  }

  return data.filter((other) => {
    if (String(other.id) === String(report.id)) return false;
    if (String(other.user_id ?? "") === String(report.user_id ?? "")) return false;
    const distance = distanceMeters(
      Number(report.latitude),
      Number(report.longitude),
      Number(other.latitude),
      Number(other.longitude),
    );
    return distance <= 250;
  }).length;
}

function distanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
) {
  const earth = 6371000;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) *
      Math.sin(dLon / 2) ** 2;
  return earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function radians(value: number) {
  return value * Math.PI / 180;
}

function labelStatus(status: string) {
  return status === "high_confidence" ? "High Confidence" : "Pending";
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
