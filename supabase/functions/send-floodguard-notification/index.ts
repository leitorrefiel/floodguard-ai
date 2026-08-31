import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type NotificationPayload = {
  type?: string;
  severity?: string;
  title?: string;
  message?: string;
  area?: string;
  latitude?: number;
  longitude?: number;
  source?: string;
  report_id?: string;
  data?: Record<string, unknown>;
  target?: {
    mode?: "current_user" | "baliwag_development_area" | "all";
    user_id?: string;
  };
};

type PushDevice = {
  id: string;
  user_id: string | null;
  fcm_token: string;
};

type NotificationPreference = {
  user_id: string;
  flood_warnings: boolean;
  nearby_hazards: boolean;
  severe_rainfall: boolean;
  evacuation_advisories: boolean;
  community_updates: boolean;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await request.json() as NotificationPayload;
    const title = payload.title?.trim();
    const message = payload.message?.trim();
    if (!title || !message) {
      return json({ error: "title and message are required" }, 400);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const firebaseProjectId = requiredEnv("FIREBASE_PROJECT_ID");
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const authUserId = await userIdFromRequest(supabase, request);
    const targetMode = payload.target?.mode ?? "baliwag_development_area";
    const targetUserId = payload.target?.user_id ??
      (targetMode === "current_user" ? authUserId : undefined);

    const alertInsert = {
      user_id: targetUserId ?? null,
      type: payload.type ?? "flood_warning",
      severity: payload.severity ?? "info",
      title,
      message,
      area: payload.area ?? "Baliwag development area",
      latitude: payload.latitude ?? null,
      longitude: payload.longitude ?? null,
      source: payload.source ?? "FloodGuard",
      report_id: payload.report_id ?? null,
      data: payload.data ?? {},
      is_active: true,
      expires_at: null,
    };
    const { data: alert, error: alertError } = await supabase
      .from("alerts")
      .insert(alertInsert)
      .select()
      .single();
    if (alertError) throw alertError;

    let deviceQuery = supabase
      .from("push_devices")
      .select("id,user_id,fcm_token")
      .eq("is_active", true);
    if (targetUserId) {
      deviceQuery = deviceQuery.eq("user_id", targetUserId);
    }

    const { data: devices, error: deviceError } = await deviceQuery;
    if (deviceError) throw deviceError;

    const activeDevices = (devices ?? []) as PushDevice[];
    const userIds = [...new Set(activeDevices.map((item) => item.user_id).filter(
      (value): value is string => Boolean(value),
    ))];
    const preferences = await loadPreferences(supabase, userIds);
    const allowedDevices = activeDevices.filter((device) =>
      allowsNotification(
        preferences.get(device.user_id ?? ""),
        payload.type ?? "flood_warning",
      )
    );

    const accessToken = await firebaseAccessToken();
    let sent = 0;
    let failed = 0;
    const invalidTokens: string[] = [];

    for (const device of allowedDevices) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              notification: { title, body: message },
              data: stringifyData({
                alert_id: alert.id,
                type: payload.type ?? "flood_warning",
                severity: payload.severity ?? "info",
                report_id: payload.report_id ?? "",
                screen: payload.data?.screen ?? "alerts",
              }),
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "flood_alerts",
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
              },
            },
          }),
        },
      );

      if (response.ok) {
        sent++;
      } else {
        failed++;
        const body = await response.text();
        if (response.status === 404 || body.includes("UNREGISTERED")) {
          invalidTokens.push(device.fcm_token);
        }
      }
    }

    if (invalidTokens.length > 0) {
      await supabase
        .from("push_devices")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .in("fcm_token", invalidTokens);
    }

    return json({
      alert_id: alert.id,
      target_mode: targetMode,
      devices_considered: activeDevices.length,
      devices_allowed: allowedDevices.length,
      sent,
      failed,
      invalid_tokens: invalidTokens.length,
    });
  } catch (error) {
    return json({ error: String(error?.message ?? error) }, 500);
  }
});

async function userIdFromRequest(
  supabase: ReturnType<typeof createClient>,
  request: Request,
) {
  const authHeader = request.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "").trim();
  if (!token) return null;
  const { data } = await supabase.auth.getUser(token);
  return data.user?.id ?? null;
}

async function loadPreferences(
  supabase: ReturnType<typeof createClient>,
  userIds: string[],
) {
  const map = new Map<string, NotificationPreference>();
  if (userIds.length === 0) return map;
  const { data, error } = await supabase
    .from("notification_preferences")
    .select()
    .in("user_id", userIds);
  if (error) throw error;
  for (const row of (data ?? []) as NotificationPreference[]) {
    map.set(row.user_id, row);
  }
  return map;
}

function allowsNotification(
  preference: NotificationPreference | undefined,
  type: string,
) {
  if (!preference) return true;
  switch (type) {
    case "flood_warning":
      return preference.flood_warnings;
    case "nearby_hazard":
      return preference.nearby_hazards;
    case "severe_rainfall":
      return preference.severe_rainfall;
    case "evacuation_advisory":
      return preference.evacuation_advisories;
    case "community_update":
      return preference.community_updates;
    default:
      return true;
  }
}

async function firebaseAccessToken() {
  const clientEmail = requiredEnv("FIREBASE_CLIENT_EMAIL");
  const privateKey = requiredEnv("FIREBASE_PRIVATE_KEY").replaceAll("\\n", "\n");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    {
      alg: "RS256",
      typ: "JWT",
    },
    {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    privateKey,
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(await response.text());
  const json = await response.json();
  return json.access_token as string;
}

async function signJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  pem: string,
) {
  const encodedHeader = base64Url(JSON.stringify(header));
  const encodedClaims = base64Url(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function stringifyData(data: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, String(value ?? "")]),
  );
}

function base64Url(value: string) {
  return base64UrlBytes(new TextEncoder().encode(value));
}

function base64UrlBytes(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
