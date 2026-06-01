const sessions = new Map();
const lastNotify = new Map();
const pendingPermissions = new Map(); // sid → count

function env() {
  return {
    TOKEN: process.env.TELEGRAM_BOT_TOKEN,
    CHAT_ID: process.env.TELEGRAM_CHAT_ID,
  };
}

function throttle(sid, type) {
  const key = `${sid}:${type}`;
  const now = Date.now();
  const last = lastNotify.get(key) || 0;
  if (now - last < 3000) return false;
  lastNotify.set(key, now);
  return true;
}

function esc(text) {
  return text.replace(/[_*[\]()`~]/g, "\\$&");
}

function label(info) {
  const t = info?.title || info?.id?.slice(0, 8) || "agent";
  return esc(t);
}

export const OpengramNotify = async () => {
  const notify = async (text) => {
    const { TOKEN, CHAT_ID } = env();
    if (!TOKEN || !CHAT_ID) return;
    try {
      const res = await fetch(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: Number(CHAT_ID),
          text,
          parse_mode: "Markdown",
          disable_web_page_preview: true,
        }),
      });
      if (!res.ok) {
        console.error("opengram-notify: Telegram API error", await res.json().catch(() => ({})));
      }
    } catch (err) {
      console.error("opengram-notify: send error", err);
    }
  };

  return {
    "session.created": async (input) => {
      const info = input?.info;
      if (info?.id) sessions.set(info.id, info);
    },
    "session.updated": async (input) => {
      const info = input?.info;
      if (info?.id) sessions.set(info.id, info);
    },
    "session.status": async (input) => {
      const { TOKEN, CHAT_ID } = env();
      if (!TOKEN || !CHAT_ID) return;
      const sid = input?.sessionID || input?.info?.id;
      const status = input?.status;
      if (!sid || !status) return;
      if (status.type === "busy") {
        if (throttle(sid, "busy")) {
          const info = sessions.get(sid);
          await notify(`🤔 *${label(info)}* — working...`);
        }
      } else if (status.type === "retry") {
        if (throttle(sid, "retry")) {
          const info = sessions.get(sid);
          await notify(`🔄 *${label(info)}* — retry #${status.attempt}${status.message ? ` (${status.message})` : ""}`);
        }
      }
    },
    "session.idle": async (input) => {
      const { TOKEN, CHAT_ID } = env();
      if (!TOKEN || !CHAT_ID) return;
      const sid = input?.sessionID || input?.info?.id;
      if (!sid) return;
      if (pendingPermissions.has(sid)) return;
      if (throttle(sid, "idle")) {
        const info = sessions.get(sid);
        await notify(`✅ *${label(info)}* — completed`);
      }
    },
    "session.error": async (input) => {
      const { TOKEN, CHAT_ID } = env();
      if (!TOKEN || !CHAT_ID) return;
      const sid = input?.sessionID || input?.info?.id;
      if (!sid || !throttle(sid, "error")) return;
      const err = input?.error || {};
      const msg = err.data?.message || err.name || "error";
      const info = sessions.get(sid);
      await notify(`❌ *${label(info)}* — ${esc(msg)}`);
    },
    "permission.asked": async (input) => {
      const { TOKEN, CHAT_ID } = env();
      if (!TOKEN || !CHAT_ID) return;
      const permSid = input?.sessionID;
      if (permSid) {
        pendingPermissions.set(permSid, (pendingPermissions.get(permSid) || 0) + 1);
        if (throttle(permSid, "permission")) {
          const info = sessions.get(permSid);
          await notify(`⏳ *${label(info)}* — needs approval: ${esc(input?.title || "permission")}`);
        }
      }
    },
    "permission.replied": async (input) => {
      const { TOKEN, CHAT_ID } = env();
      if (!TOKEN || !CHAT_ID) return;
      const permSid = input?.sessionID;
      if (permSid) {
        const count = pendingPermissions.get(permSid);
        if (count != null) {
          if (count <= 1) pendingPermissions.delete(permSid);
          else pendingPermissions.set(permSid, count - 1);
        }
      }
    },
  };
};
