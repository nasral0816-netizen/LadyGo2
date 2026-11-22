import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const sendExpoPush = async (messages: Record<string, unknown>[]) => {
  const response = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Accept-encoding": "gzip, deflate",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(messages),
  });
  const result = await response.json();
  const tickets = Array.isArray(result?.data) ? result.data : [];
  const errors = tickets.filter((ticket: any) => ticket.status === "error");
  return { ok: response.ok && errors.length === 0, result, errors };
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookSecret = req.headers.get("x-ladygo-webhook-secret") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
    return json({ error: "Webhook configuration is incomplete" }, 503);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let claimed: { table: string; id: string } | null = null;
  try {
    const { data: authorized, error: authError } = await supabase.rpc(
      "ladygo_verify_push_webhook_secret",
      { p_candidate: webhookSecret },
    );
    if (authError || authorized !== true) return json({ error: "Unauthorized" }, 401);

    const payload = await req.json();

    // Passenger/driver status and service notifications.
    const notification = payload?.notification;
    if (notification) {
      if (!notification.id || !notification.user_id || !notification.title || !notification.body) {
        return json({ skipped: true, reason: "Invalid notification event" });
      }

      const [{ data: currentNotification, error: notificationError }, { data: profile, error: profileError }] =
        await Promise.all([
          supabase.from("notifications")
            .select("id, user_id, order_id, title, body, push_sent_at")
            .eq("id", notification.id)
            .eq("user_id", notification.user_id)
            .maybeSingle(),
          supabase.from("profiles")
            .select("role")
            .eq("id", notification.user_id)
            .maybeSingle(),
        ]);
      if (notificationError) throw notificationError;
      if (profileError) throw profileError;
      if (!currentNotification) return json({ skipped: true, reason: "Notification not found" });

      const { data: tokens, error: tokenError } = await supabase
        .from("user_push_tokens")
        .select("expo_push_token")
        .eq("user_id", notification.user_id);
      if (tokenError) throw tokenError;
      if (!tokens?.length) return json({ sent: 0, reason: "No registered devices" });

      const { data: claim, error: claimError } = await supabase
        .from("notifications")
        .update({ push_sent_at: new Date().toISOString() })
        .eq("id", notification.id)
        .is("push_sent_at", null)
        .select("id")
        .maybeSingle();
      if (claimError) throw claimError;
      if (!claim) return json({ sent: 0, duplicate: true });
      claimed = { table: "notifications", id: notification.id };

      const channelId = profile?.role === "driver" ? "driver-orders" : "trip-updates";
      const messages = tokens.map((token: { expo_push_token: string }) => ({
        to: token.expo_push_token,
        title: currentNotification.title,
        body: currentNotification.body,
        sound: "default",
        priority: "high",
        channelId,
        data: { notificationId: notification.id, orderId: currentNotification.order_id ?? null },
      }));
      const delivery = await sendExpoPush(messages);
      if (!delivery.ok) {
        await supabase.from("notifications").update({ push_sent_at: null }).eq("id", notification.id);
        claimed = null;
        const tickets = Array.isArray(delivery.result?.data) ? delivery.result.data : [];
        for (let index = 0; index < tickets.length; index++) {
          if (tickets[index]?.details?.error === "DeviceNotRegistered" && tokens[index]?.expo_push_token) {
            await supabase.from("user_push_tokens").delete()
              .eq("user_id", notification.user_id)
              .eq("expo_push_token", tokens[index].expo_push_token);
          }
        }
        return json({ error: "Expo Push rejected one or more messages", details: delivery.result }, 502);
      }
      return json({ sent: messages.length, tickets: delivery.result?.data ?? delivery.result });
    }

    // New order offer for a driver.
    const offer = payload?.record ?? payload;
    if (!offer?.id || !offer?.order_id || !offer?.driver_id || offer?.status !== "pending") {
      return json({ skipped: true, reason: "Invalid offer event" });
    }

    const [{ data: currentOffer, error: offerError }, { data: order, error: orderError }] =
      await Promise.all([
        supabase.from("order_offers")
          .select("id, order_id, driver_id, status, push_sent_at")
          .eq("id", offer.id)
          .eq("order_id", offer.order_id)
          .eq("driver_id", offer.driver_id)
          .eq("status", "pending")
          .maybeSingle(),
        supabase.from("orders")
          .select("id, pickup_address, destination_address, status, driver_id")
          .eq("id", offer.order_id)
          .eq("status", "new")
          .is("driver_id", null)
          .maybeSingle(),
      ]);
    if (offerError) throw offerError;
    if (orderError) throw orderError;
    if (!currentOffer || !order) return json({ skipped: true, reason: "Offer is no longer active" });

    const { data: tokens, error: tokenError } = await supabase
      .from("driver_push_tokens")
      .select("expo_push_token")
      .eq("driver_id", offer.driver_id);
    if (tokenError) throw tokenError;
    if (!tokens?.length) return json({ sent: 0, reason: "No registered devices" });

    const { data: claim, error: claimError } = await supabase
      .from("order_offers")
      .update({ push_sent_at: new Date().toISOString() })
      .eq("id", offer.id)
      .eq("status", "pending")
      .is("push_sent_at", null)
      .select("id")
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claim) return json({ sent: 0, duplicate: true });
    claimed = { table: "order_offers", id: offer.id };

    const messages = tokens.map((token: { expo_push_token: string }) => ({
      to: token.expo_push_token,
      title: "Новый заказ LadyGo",
      body: `Подача: ${order.pickup_address || "Адрес не указан"}`,
      sound: "default",
      priority: "high",
      channelId: "driver-orders",
      ttl: 25,
      data: { orderId: offer.order_id, offerId: offer.id },
    }));
    const delivery = await sendExpoPush(messages);
    if (!delivery.ok) {
      await supabase.from("order_offers").update({ push_sent_at: null }).eq("id", offer.id);
      claimed = null;
      const tickets = Array.isArray(delivery.result?.data) ? delivery.result.data : [];
      for (let index = 0; index < tickets.length; index++) {
        if (tickets[index]?.details?.error === "DeviceNotRegistered" && tokens[index]?.expo_push_token) {
          await supabase.from("driver_push_tokens").delete()
            .eq("driver_id", offer.driver_id)
            .eq("expo_push_token", tokens[index].expo_push_token);
        }
      }
      return json({ error: "Expo Push rejected one or more messages", details: delivery.result }, 502);
    }
    return json({ sent: messages.length, tickets: delivery.result?.data ?? delivery.result });
  } catch (error) {
    if (claimed) {
      await supabase.from(claimed.table).update({ push_sent_at: null }).eq("id", claimed.id);
    }
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
