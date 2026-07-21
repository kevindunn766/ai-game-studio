const http = require('http');
const fs = require('fs');
const path = require('path');

const APK = path.join(__dirname, 'chimeradrift.apk');
const port = process.env.PORT || 3000;

http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  if (url === '/' || url === '') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Chimera Drift — playtest</title></head>
<body style="font-family:system-ui,sans-serif;background:#0b0e16;color:#e6ecff;text-align:center;padding:12vh 6vw">
<h1 style="letter-spacing:2px">CHIMERA DRIFT</h1>
<p style="opacity:.7">Android playtest build</p>
<p style="margin-top:2em"><a href="/chimeradrift.apk" style="display:inline-block;padding:16px 28px;background:#3a5bd9;color:#fff;border-radius:10px;text-decoration:none;font-size:1.2em">Download APK</a></p>
<p style="opacity:.5;font-size:.85em;margin-top:2em">You may need to allow "install from unknown sources".</p>
</body></html>`);
    return;
  }
  if (url === '/chimeradrift.apk') {
    let stat;
    try { stat = fs.statSync(APK); } catch (e) { res.writeHead(404); res.end('apk missing'); return; }
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': stat.size,
      'Content-Disposition': 'attachment; filename="chimeradrift.apk"',
    });
    fs.createReadStream(APK).pipe(res);
    return;
  }
  res.writeHead(404); res.end('not found');
}).listen(port, () => console.log('APK host listening on ' + port));
