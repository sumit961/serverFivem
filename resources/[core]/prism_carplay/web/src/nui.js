/** Small, testable bridge around FiveM's NUI fetch contract. */
export function resourceName() {
  return typeof window.GetParentResourceName === "function"
    ? window.GetParentResourceName()
    : "nui-frame-app";
}

export async function nui(action, data = {}) {
  try {
    const response = await fetch(`https://${resourceName()}/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });

    const text = await response.text();
    if (!text) return null;

    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  } catch (error) {
    // The local browser preview has no FiveM endpoint. Keeping this quiet
    // makes the same UI usable outside the game for visual development.
    console.debug(`[CarPlay] NUI call failed: ${action}`, error);
    return null;
  }
}

export function listen(callback) {
  const handler = (event) => {
    const message = event?.data;
    if (!message || typeof message !== "object") return;
    callback(message);
  };

  window.addEventListener("message", handler);
  return () => window.removeEventListener("message", handler);
}
