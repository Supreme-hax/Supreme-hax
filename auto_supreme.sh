#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ========== Helpers ==========
log()  { echo -e "[$(date '+%F %T')] $*"; }
ok()   { log "✅ $*"; }
warn() { log "⚠️ $*"; }

# ========== Config ==========
REPO_DIR="$HOME/Supreme-hax"
BACKUP_DIR="$HOME/.supreme_backups"
PORT="${PORT:-8787}"
SYMBOL_SPOT="${SYMBOL_SPOT:-BTCUSDT}"
SYMBOL_FUTURES="${SYMBOL_FUTURES:-BTCUSDT}"
INTERVAL="${INTERVAL:-15m}"   # for main charts
SCALP_INTERVAL="${SCALP_INTERVAL:-1m}"  # for scalping
DASH_DIR="$REPO_DIR/.dashboard"

# ========== Binance env (optional) ==========
[ -f "${BINANCE_ENV:-}" ] && source "$BINANCE_ENV" || true

# ========== SSH key ==========
if [ -f "$HOME/.ssh/id_ed25519" ]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$HOME/.ssh/id_ed25519" >/dev/null
  ok "SSH key loaded"
else
  warn "SSH key not found — GitHub push/pull via SSH may fail"
fi

# ========== Git sync ==========
if [ -d "$REPO_DIR/.git" ]; then
  cd "$REPO_DIR"
  git reset --hard
  git pull --rebase
  ok "GitHub repo synced"
else
  warn "Repo not found at $REPO_DIR — cloning..."
  git clone git@github.com:Supreme-hax/Supreme-hax.git "$REPO_DIR"
  ok "Repo cloned"
fi

# ========== Binance ping (public, no signature) ==========
if curl -s -H "X-MBX-APIKEY: ${BINANCE_API_KEY:-}" "https://api.binance.com/api/v3/ping" | grep -q "{}"; then
  ok "Binance API connectivity OK"
else
  warn "Binance API ping failed"
fi

# ========== Backup & heal ==========
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/backup_$(date +%F_%H-%M-%S).tar.gz" -C "$REPO_DIR" . || warn "Backup step had a warning"
ok "Backup created"

if [ ! -f "$REPO_DIR/config/main.conf" ] && ls -1 "$BACKUP_DIR"/backup_*.tar.gz >/dev/null 2>&1; then
  warn "Main config missing — restoring from latest backup"
  LATEST="$(ls -t "$BACKUP_DIR"/backup_*.tar.gz | head -n 1)"
  tar -xzf "$LATEST" -C "$REPO_DIR"
  ok "Restore complete"
fi

# ========== Ensure Python for local server ==========
if ! command -v python3 >/dev/null 2>&1; then
  pkg update -y
  pkg install -y python
fi

# ========== Build local dashboard (HTML + JS) ==========
mkdir -p "$DASH_DIR"
cat > "$DASH_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Supreme Dashboard — Spot & Futures with Signals</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <script src="https://cdn.plot.ly/plotly-2.32.0.min.js"></script>
  <style>
    body{font-family:Inter,system-ui,Segoe UI,Roboto,Arial,sans-serif;background:#0b0f14;color:#e6edf3;margin:0;padding:0}
    header{padding:14px 18px;background:#111826;border-bottom:1px solid #1f2733}
    .wrap{padding:18px;display:grid;grid-template-columns:1fr 1fr;gap:18px}
    .panel{background:#0f141b;border:1px solid #1f2733;border-radius:10px;padding:12px}
    h1{font-size:18px;margin:0}
    .signals{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}
    .signal{background:#0f141b;border:1px solid #1f2733;border-radius:10px;padding:12px}
    .tag{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px}
    .buy{background:#0f2a18;color:#36d399;border:1px solid #1a4d34}
    .sell{background:#2a0f0f;color:#f87272;border:1px solid #4d1a1a}
    .neutral{background:#1a1f2e;color:#93c5fd;border:1px solid #27374f}
    .meta{font-size:12px;color:#9aa6b2;margin-top:6px}
    .footer{padding:10px 18px;color:#708090;font-size:12px;border-top:1px solid #1f2733}
  </style>
</head>
<body>
<header>
  <h1>Supreme Dashboard — Spot & Futures with EMA50/200, RSI14, MACD (auto-refresh)</h1>
</header>

<div class="wrap">
  <div class="panel">
    <div id="spot_chart" style="height:420px;"></div>
  </div>
  <div class="panel">
    <div id="futures_chart" style="height:420px;"></div>
  </div>
</div>

<div class="wrap">
  <div class="signals">
    <div class="signal">
      <div>Spot signal</div>
      <div id="sig_spot" class="tag neutral">Loading...</div>
      <div class="meta" id="sig_spot_meta"></div>
    </div>
    <div class="signal">
      <div>Futures signal</div>
      <div id="sig_fut" class="tag neutral">Loading...</div>
      <div class="meta" id="sig_fut_meta"></div>
    </div>
    <div class="signal">
      <div>Scalping signal</div>
      <div id="sig_scalp" class="tag neutral">Loading...</div>
      <div class="meta" id="sig_scalp_meta"></div>
    </div>
  </div>
</div>

<div class="footer">
  Non-custodial, client-side view. Signals are informational only — not financial advice.
</div>

<script>
  // Config injected by script at runtime (from URL params)
  const urlParams = new URLSearchParams(window.location.search);
  const SYMBOL_SPOT    = urlParams.get('spot')    || 'BTCUSDT';
  const SYMBOL_FUTURES = urlParams.get('fut')     || 'BTCUSDT';
  const INTERVAL       = urlParams.get('tf')      || '15m';
  const SCALP_INTERVAL = urlParams.get('scalp')   || '1m';
  const LIMIT          = parseInt(urlParams.get('limit') || '500', 10);

  const endpoints = {
    spotKlines: (sym, tf, limit) => `https://api.binance.com/api/v3/klines?symbol=${sym}&interval=${tf}&limit=${limit}`,
    futKlines:  (sym, tf, limit) => `https://fapi.binance.com/fapi/v1/klines?symbol=${sym}&interval=${tf}&limit=${limit}`
  };

  const toOHLC = rows => rows.map(r => ({ t: r[0], o:+r[1], h:+r[2], l:+r[3], c:+r[4], v:+r[5] }));

  function ema(src, period){
    const k = 2/(period+1);
    let ema = [], prev = src[0];
    for (let i=0;i<src.length;i++){
      const val = i===0 ? src[i] : (src[i]*k + prev*(1-k));
      ema.push(val); prev = val;
    }
    return ema;
  }
  function rsi(closes, period=14){
    let gains=0, losses=0;
    for(let i=1;i<=period;i++){
      const ch = closes[i]-closes[i-1];
      if (ch>=0) gains+=ch; else losses+=-ch;
    }
    let avgGain=gains/period, avgLoss=losses/period;
    const rsis = new Array(period).fill(null);
    for(let i=period+1;i<closes.length;i++){
      const ch = closes[i]-closes[i-1];
      const g = ch>0? ch:0, l = ch<0? -ch:0;
      avgGain = (avgGain*(period-1)+g)/period;
      avgLoss = (avgLoss*(period-1)+l)/period;
      const rs = avgLoss===0? 100 : 100 - (100/(1+(avgGain/avgLoss)));
      rsis.push(rs);
    }
    return rsis;
  }
  function macd(closes, fast=12, slow=26, sig=9){
    const emaFast = ema(closes, fast);
    const emaSlow = ema(closes, slow);
    const macdLine = emaFast.map((v,i)=> v - emaSlow[i]);
    const signal = ema(macdLine.slice(slow-1), sig);
    // align signal length
    const pad = new Array(slow-1).fill(null);
    const fullSignal = pad.concat(signal);
    const hist = macdLine.map((v,i)=> (fullSignal[i]==null? null : v - fullSignal[i]));
    return { macdLine, signal: fullSignal, hist };
  }
  const crossedUp   = (a,b)=> a[a.length-2]!==null && b[b.length-2]!==null && a[a.length-2] <= b[b.length-2] && a[a.length-1] > b[b.length-1];
  const crossedDown = (a,b)=> a[a.length-2]!==null && b[b.length-2]!==null && a[a.length-2] >= b[b.length-2] && a[a.length-1] < b[b.length-1];

  async function fetchKlines(url){
    const res = await fetch(url);
    if(!res.ok) throw new Error('fetch failed');
    const rows = await res.json();
    return toOHLC(rows);
  }

  function drawChart(divId, ohlc, title){
    const t = ohlc.map(x=> new Date(x.t));
    const o = ohlc.map(x=> x.o), h = ohlc.map(x=> x.h), l = ohlc.map(x=> x.l), c = ohlc.map(x=> x.c);

    const ema50  = ema(c, 50);
    const ema200 = ema(c, 200);
    const rsi14  = rsi(c, 14);
    const { macdLine, signal, hist } = macd(c, 12, 26, 9);

    const candle = {
      x:t, open:o, high:h, low:l, close:c, type:'candlestick', name:'Price',
      increasing:{line:{color:'#22c55e'}}, decreasing:{line:{color:'#ef4444'}}
    };
    const lEma50 = { x:t, y:ema50,  type:'scatter', mode:'lines', name:'EMA50',  line:{color:'#60a5fa', width:1.5} };
    const lEma200= { x:t, y:ema200, type:'scatter', mode:'lines', name:'EMA200', line:{color:'#a78bfa', width:1.5} };
    const rsiPlot= { x:t, y:rsi14,  type:'scatter', mode:'lines', name:'RSI14',  line:{color:'#f59e0b', width:1.3}, yaxis:'y2' };
    const macdHist={ x:t, y:hist,   type:'bar',     name:'MACD hist', marker:{color:'#94a3b8'}, yaxis:'y3' };

    const layout = {
      title:{text:title, font:{color:'#e6edf3', size:14}},
      plot_bgcolor:'#0f141b', paper_bgcolor:'#0f141b',
      font:{color:'#cbd5e1'},
      grid:{rows:3, columns:1, subplots:[['xy'],['xy2'],['xy3']], roworder:'top to bottom'},
      xaxis:{rangeslider:{visible:false}},
      yaxis:{domain:[0.40,1.0]}, yaxis2:{domain:[0.20,0.36]}, yaxis3:{domain:[0.0,0.16]},
      margin:{l:40,r:10,t:36,b:24}
    };
    Plotly.newPlot(divId, [candle, lEma50, lEma200, rsiPlot, macdHist], layout, {displayModeBar:false});
    return { ema50, ema200, rsi14, macdLine, signal, hist };
  }

  function setSignal(elId, metaId, status, details){
    const el = document.getElementById(elId);
    el.className = 'tag ' + (status==='BUY' ? 'buy' : status==='SELL' ? 'sell' : 'neutral');
    el.textContent = status;
    document.getElementById(metaId).textContent = details;
  }

  async function updateAll(){
    try{
      // Spot
      const spot = await fetchKlines(endpoints.spotKlines(SYMBOL_SPOT, INTERVAL, LIMIT));
      const spotInd = drawChart('spot_chart', spot, `Spot ${SYMBOL_SPOT} — TF ${INTERVAL}`);
      const sBuy  = crossedUp(spotInd.ema50, spotInd.ema200) && (spotInd.rsi14.at(-1) > 50);
      const sSell = crossedDown(spotInd.ema50, spotInd.ema200) && (spotInd.rsi14.at(-1) < 50);
      setSignal('sig_spot','sig_spot_meta',
        sBuy ? 'BUY' : sSell ? 'SELL' : 'HOLD',
        `EMA50/200 cross + RSI14=${(spotInd.rsi14.at(-1)||0).toFixed(1)}  •  ${new Date().toLocaleString()}`);

      // Futures
      const fut = await fetchKlines(endpoints.futKlines(SYMBOL_FUTURES, INTERVAL, LIMIT));
      const futInd = drawChart('futures_chart', fut, `Futures ${SYMBOL_FUTURES} — TF ${INTERVAL}`);
      const rsiNow = futInd.rsi14.at(-1)||0, macdNow = futInd.macdLine.at(-1)||0, sigNow = futInd.signal.at(-1)||0;
      const fBuy  = (rsiNow < 30 && macdNow > sigNow) || crossedUp(futInd.macdLine, futInd.signal);
      const fSell = (rsiNow > 70 && macdNow < sigNow) || crossedDown(futInd.macdLine, futInd.signal);
      setSignal('sig_fut','sig_fut_meta',
        fBuy ? 'BUY' : fSell ? 'SELL' : 'HOLD',
        `RSI14=${rsiNow.toFixed(1)} • MACD ${macdNow.toFixed(3)} vs Sig ${sigNow.toFixed(3)} • ${new Date().toLocaleString()}`);

      // Scalping (1m spot)
      const scalp = await fetchKlines(endpoints.spotKlines(SYMBOL_SPOT, SCALP_INTERVAL, 300));
      const closes = scalp.map(x=>x.c);
      const ema9 = ema(closes, 9), ema21 = ema(closes, 21);
      const macdSc = macd(closes, 12, 26, 9);
      const scBuy  = crossedUp(ema9, ema21) && (macdSc.hist.at(-1) > 0);
      const scSell = crossedDown(ema9, ema21) && (macdSc.hist.at(-1) < 0);
      setSignal('sig_scalp','sig_scalp_meta',
        scBuy ? 'BUY' : scSell ? 'SELL' : 'HOLD',
        `EMA9/21 + MACD hist ${(macdSc.hist.at(-1)||0).toFixed(4)} • ${new Date().toLocaleString()}`);

    }catch(e){
      setSignal('sig_spot','sig_spot_meta','HOLD', 'Fetch/Calc error — retrying...');
      setSignal('sig_fut','sig_fut_meta','HOLD', 'Fetch/Calc error — retrying...');
      setSignal('sig_scalp','sig_scalp_meta','HOLD', 'Fetch/Calc error — retrying...');
      console.error(e);
    }
  }

  updateAll();
  setInterval(updateAll, 60*1000); // refresh every 60s
</script>
</body>
</html>
HTML

# ========== Launch local server ==========
# Kill any prior server on PORT
if lsof -i :"$PORT" >/dev/null 2>&1; then
  kill -9 "$(lsof -ti :"$PORT" | head -n1)" || true
fi
cd "$DASH_DIR"
nohup python3 -m http.server "$PORT" >/dev/null 2>&1 &

ok "Dashboard live — open this on your device browser:"
log "http://127.0.0.1:${PORT}/?spot=${SYMBOL_SPOT}&fut=${SYMBOL_FUTURES}&tf=${INTERVAL}&scalp=${SCALP_INTERVAL}&limit=500"
ok "ALL DONE — GitHub + Binance OK, backups done, dashboard running."
