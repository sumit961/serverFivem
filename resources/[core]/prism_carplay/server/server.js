const fs = require("fs");
const FormData = require("form-data");
const https = require("https");

// Read the upload key from a server-only convar.
// Never read secrets from config.lua: it is loaded by the client as a shared
// script and would expose the key to every player.
function getApiKey() {
  return GetConvar(
    "prism_carplay_fivemanage_api_key",
    GetConvar("fivemanage_api_key", ""),
  );
}

// Upload video to Fivemanage - exported for Lua to call
function uploadFivemanage(filePath, filename, callback) {
  const apiKey = getApiKey();
  if (!apiKey) {
    console.error("[prism-carplay] Fivemanage API key not configured");
    callback(null);
    return;
  }

  // Check if file exists
  if (!fs.existsSync(filePath)) {
    console.error("[prism-carplay] File not found:", filePath);
    callback(null);
    return;
  }

  const formData = new FormData();

  // Read file as stream (blob equivalent in Node.js)
  const fileStream = fs.createReadStream(filePath);
  formData.append("file", fileStream, {
    filename: filename,
    contentType: "video/webm",
  });

  // Add metadata
  formData.append(
    "metadata",
    JSON.stringify({
      name: filename,
      description: "Dashcam recording from CarPlay",
    }),
  );

  // Make request to Fivemanage
  const options = {
    hostname: "api.fivemanage.com",
    port: 443,
    path: "/api/v3/file",
    method: "POST",
    headers: {
      ...formData.getHeaders(),
      Authorization: apiKey,
    },
  };

  const req = https.request(options, (res) => {
    let data = "";
    res.on("data", (chunk) => (data += chunk));
    res.on("end", () => {
      console.log("[prism-carplay] Fivemanage response:", data);
      if (res.statusCode === 200 || res.statusCode === 201) {
        try {
          const json = JSON.parse(data);
          // Handle different response formats
          const url = json.url || (json.data && json.data.url);
          const id = json.id || (json.data && json.data.id);
          console.log("[prism-carplay] Uploaded to Fivemanage:", url);
          callback({ url: url, id: id });
        } catch (e) {
          console.error("[prism-carplay] Failed to parse response:", data);
          callback(null);
        }
      } else {
        console.error(
          "[prism-carplay] Fivemanage upload failed:",
          res.statusCode,
          data,
        );
        callback(null);
      }
    });
  });

  req.on("error", (err) => {
    console.error("[prism-carplay] Fivemanage upload error:", err.message);
    callback(null);
  });

  formData.pipe(req);
}

// Delete file from Fivemanage - exported for Lua to call
function deleteFivemanage(fileId, callback) {
  const apiKey = getApiKey();
  if (!apiKey) {
    console.error("[prism-carplay] Fivemanage API key not configured");
    if (callback) callback(false);
    return;
  }

  if (!fileId) {
    console.error("[prism-carplay] No file ID provided for deletion");
    if (callback) callback(false);
    return;
  }

  const options = {
    hostname: "api.fivemanage.com",
    port: 443,
    path: "/api/v3/file/" + fileId,
    method: "DELETE",
    headers: {
      Authorization: apiKey,
    },
  };

  const req = https.request(options, (res) => {
    let data = "";
    res.on("data", (chunk) => (data += chunk));
    res.on("end", () => {
      if (res.statusCode === 200 || res.statusCode === 204) {
        console.log("[prism-carplay] Deleted from Fivemanage:", fileId);
        if (callback) callback(true);
      } else {
        console.error(
          "[prism-carplay] Fivemanage delete failed:",
          res.statusCode,
          data,
        );
        if (callback) callback(false);
      }
    });
  });

  req.on("error", (err) => {
    console.error("[prism-carplay] Fivemanage delete error:", err.message);
    if (callback) callback(false);
  });

  req.end();
}

// Export functions for Lua to call
exports("uploadFivemanage", uploadFivemanage);
exports("deleteFivemanage", deleteFivemanage);
