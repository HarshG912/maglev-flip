const https = require('https');

const url = "https://hteolkfbjmouicmyuxqv.supabase.co/storage/v1/object/public/train_skins/Cyber%20Streak%20(The%20Neon%20Classic).png";

https.get(url, (res) => {
  console.log("Status Code:", res.statusCode);
  console.log("Headers:", res.headers);
}).on('error', (e) => {
  console.error("Error:", e);
});
