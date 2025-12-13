import { ConnectButton, SuiClientProvider, WalletProvider, useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';


import { SuiClient } from '@mysten/sui/client';


import { Transaction } from '@mysten/sui/transactions';


import { QueryClient, QueryClientProvider, useQuery, useQueryClient } from '@tanstack/react-query';


import { useEffect, useState } from 'react';


import './App.css';


import { NetworkBlocker } from './components/NetworkBlocker';


import { TestnetBanner } from './components/TestnetBanner';


import { ids, tokens } from './ids';


import { DEFAULT_NETWORK, networkConfig } from './sui';


import { priceNoBps, priceYesBps, toFixed } from './utils/pricing';


import {


  buildAddLiquidity,


  buildBuyNo,


  buildBuyYes,


  buildCancelOrder,


  buildChallenge,


  buildCreateOrder,


  buildFinalize,


  buildPropose,


  buildRedeem,


  buildRemoveLiquidity,


  buildSellNo,


  buildSellYes,


} from './utils/txBuilders';





type MarketInfo = {


  id: string;


  question: string;


  endTimeMs: number;


  feeBps: number;


  resolved: boolean;


  outcomeYes: boolean;


  yesVault: bigint;


  noVault: bigint;


  totalYesShares: bigint;


  totalNoShares: bigint;


  totalLpShares: bigint;


  hasPending: boolean;


  coinType: string;


};





type Position = {


  id: string;


  marketId: string;


  shares: number;


  sideYes: boolean;


  coinType: string;


};





type LPPosition = {


  id: string;


  marketId: string;


  shares: number;


  coinType: string;


};





type LimitOrder = {


  id: string;


  marketId: string;


  sideYes: boolean;


  priceBps: number;


  maxShares: number;


  remainingShares: number;


  expiryMs: number;


  coinType: string;


};





type Portfolio = {


  positions: Position[];


  lps: LPPosition[];


  orders: LimitOrder[];


};





const expectedChain = 'sui:testnet';


const queryClient = new QueryClient();





const parseBig = (v: unknown): bigint => {


  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'bigint') return BigInt(v);


  return 0n;


};





const parseBalance = (b: any): bigint => {


  if (!b) return 0n;


  return parseBig(b.fields?.value ?? b.value);


};





const coinSymbol = (coinType: string) => tokens.find((t) => t.type === coinType)?.symbol ?? 'SUI';


const coinDecimals = (coinType: string) => tokens.find((t) => t.type === coinType)?.decimals ?? 9;





const formatDate = (ms: number) => new Date(ms).toLocaleString();





const useMarkets = () => {


  const client = useSuiClient();


  return useQuery<MarketInfo[]>({


    queryKey: ['markets', ids.registryId],


    queryFn: async () => {


      const reg = await client.getObject({


        id: ids.registryId,


        options: { showContent: true },


      });


      const markets: string[] = (reg.data?.content as any)?.fields?.markets ?? [];


      if (!markets.length) return [];


      const objs = await client.multiGetObjects({


        ids: markets,


        options: { showContent: true, showType: true },


      });


      return objs


        .map((obj) => {


          const content = obj.data?.content as any;


          if (!content || content.dataType !== 'moveObject') return null;


          const fields = content.fields;


          const type = (content as any)?.type as string;


          const coinType = type?.match(/<(.+)>/)?.[1] ?? '0x2::sui::SUI';


          return {


            id: obj.data?.objectId ?? '',


            question: fields.question as string,


            endTimeMs: Number(fields.end_time_ms ?? 0),


            feeBps: Number(fields.fee_bps ?? 0),


            resolved: Boolean(fields.resolved),


            outcomeYes: Boolean(fields.outcome_yes),


            yesVault: parseBalance(fields.yes_vault),


            noVault: parseBalance(fields.no_vault),


            totalYesShares: parseBig(fields.total_yes_shares),


            totalNoShares: parseBig(fields.total_no_shares),


            totalLpShares: parseBig(fields.total_lp_shares),


            hasPending: Boolean(fields.has_pending),


            coinType,


          } as MarketInfo;


        })


        .filter(Boolean) as MarketInfo[];


    },


    staleTime: 10_000,


  });


};





const fetchOwnedOfType = async (client: SuiClient, owner: string, type: string) => {


  const res = await client.getOwnedObjects({


    owner,


    filter: { StructType: type },


    options: { showContent: true, showType: true },


  });


  return res.data;


};





const usePortfolio = (owner?: string | null) => {


  const client = useSuiClient();


  return useQuery<Portfolio>({


    queryKey: ['portfolio', owner],


    enabled: Boolean(owner),


    queryFn: async () => {


      if (!owner) return { positions: [], lps: [], orders: [] };


      const pos: Position[] = [];


      const lps: LPPosition[] = [];


      const orders: LimitOrder[] = [];





      for (const token of tokens) {


        const positionType = `${ids.packageId}::market::Position<${token.type}>`;


        const lpType = `${ids.packageId}::market::LPPosition<${token.type}>`;


        const orderType = `${ids.packageId}::orders::LimitOrder<${token.type}>`;


        const [posObjs, lpObjs, orderObjs] = await Promise.all([


          fetchOwnedOfType(client, owner, positionType),


          fetchOwnedOfType(client, owner, lpType),


          fetchOwnedOfType(client, owner, orderType),


        ]);





        pos.push(


          ...posObjs.map((o) => {


            const f = (o.data?.content as any)?.fields;


            return {


              id: o.data?.objectId ?? '',


              marketId: f?.market_id ?? '',


              shares: Number(f?.shares ?? 0),


              sideYes: Boolean(f?.side_yes),


              coinType: token.type,


            } as Position;


          }),


        );





        lps.push(


          ...lpObjs.map((o) => {


            const f = (o.data?.content as any)?.fields;


            return {


              id: o.data?.objectId ?? '',


              marketId: f?.market_id ?? '',


              shares: Number(f?.shares ?? 0),


              coinType: token.type,


            } as LPPosition;


          }),


        );





        orders.push(


          ...orderObjs.map((o) => {


            const f = (o.data?.content as any)?.fields;


            return {


              id: o.data?.objectId ?? '',


              marketId: f?.market_id ?? '',


              sideYes: Boolean(f?.side_yes),


              priceBps: Number(f?.price_bps ?? 0),


              maxShares: Number(f?.max_shares ?? 0),


              remainingShares: Number(f?.remaining_shares ?? 0),


              expiryMs: Number(f?.expiry_ms ?? 0),


              coinType: token.type,


            } as LimitOrder;


          }),


        );


      }





      return { positions: pos, lps, orders };


    },


  });


};





const msFromHours = (h: number) => Math.round(h * 60 * 60 * 1000);


const toMist = (amount: number, decimals: number) => Math.floor(amount * 10 ** decimals);





type ChartPoint = { time: number; close: number };





const timeframeConfig: Record<string, { interval: string; limit: number }> = {


  '1d': { interval: '15m', limit: 96 },


  '7d': { interval: '1h', limit: 168 },


  '30d': { interval: '4h', limit: 200 },


  '90d': { interval: '12h', limit: 200 },


};





const pairFor = (asset: string) => ({


  BTC: 'BTCUSDT',


  ETH: 'ETHUSDT',


  SOL: 'SOLUSDT',


}[asset] ?? 'BTCUSDT');





const fetchKlines = async (asset: string, timeframe: string): Promise<ChartPoint[]> => {


  const { interval, limit } = timeframeConfig[timeframe] ?? timeframeConfig['7d'];


  const pair = pairFor(asset);


  const urls = [


    `https://api.binance.com/api/v3/klines?symbol=${pair}&interval=${interval}&limit=${limit}`,


    `https://data-api.binance.vision/api/v3/klines?symbol=${pair}&interval=${interval}&limit=${limit}`,


  ];


  for (const url of urls) {


    try {


      const res = await fetch(url);


      if (!res.ok) continue;


      const data = await res.json();


      return (data as any[]).map((row) => ({ time: Number(row[0]), close: Number(row[4]) }));


    } catch {


      // ignore and try fallback


    }


  }


  const now = Date.now();


  return Array.from({ length: 60 }).map((_, i) => ({


    time: now - (60 - i) * 60 * 60 * 1000,


    close: 100 + Math.sin(i / 5) * 8 + Math.random() * 2,


  }));


};





const useCryptoSeries = (asset: string, timeframe: string) =>


  useQuery<ChartPoint[]>({


    queryKey: ['crypto', asset, timeframe],


    queryFn: () => fetchKlines(asset, timeframe),


    staleTime: 60_000,


  });





const CryptoChart = ({


  asset,


  series,


  timeframe,


  onTimeframeChange,


}: {


  asset: string;


  series: ChartPoint[];


  timeframe: string;


  onTimeframeChange: (tf: string) => void;


}) => {


  const [hover, setHover] = useState<number | null>(null);


  const width = 860;


  const height = 280;


  const pad = 46;


  const points = series.length ? series : [{ time: Date.now(), close: 0 }];


  const min = Math.min(...points.map((p) => p.close));


  const max = Math.max(...points.map((p) => p.close));


  const range = Math.max(1e-6, max - min);





  const scaled = points.map((p, i) => {


    const x = pad + (i / Math.max(1, points.length - 1)) * (width - pad * 2);


    const y = height - pad - ((p.close - min) / range) * (height - pad * 2);


    return { ...p, x, y };


  });





  const path = scaled


    .map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(2)} ${p.y.toFixed(2)}`)


    .join(' ');





  const hoverIdx = hover ?? scaled.length - 1;


  const hoverPoint = scaled[hoverIdx];





  const axisTicks = 4;


  const yTicks = Array.from({ length: axisTicks }).map((_, i) => {


    const v = min + (range / (axisTicks - 1)) * i;


    const y = height - pad - ((v - min) / range) * (height - pad * 2);


    return { v, y };


  });





  const timeFmt = (t: number) => new Date(t).toLocaleString();





  return (


    <div className="chart-card fade-slide">


      <div className="chart-head">


        <div>


          <div style={{ fontWeight: 700 }}>{asset} / USD</div>


          <div className="muted">Live (Binance)</div>


        </div>


        <div style={{ display: 'flex', gap: 8 }}>


          {['1d', '7d', '30d', '90d'].map((tf) => (


            <button


              key={tf}


              className="tab"


              style={{


                padding: '6px 10px',


                borderRadius: 10,


                border: '1px solid rgba(255,255,255,0.08)',


                background: timeframe === tf ? 'linear-gradient(90deg,#22d3ee,#22c55e)' : 'rgba(255,255,255,0.04)',


                color: timeframe === tf ? '#0b1021' : '#e5e7eb',


                cursor: 'pointer',


              }}


              onClick={() => onTimeframeChange(tf)}


            >


              {tf}


            </button>


          ))}


        </div>


      </div>


      <div style={{ position: 'relative' }}>


        <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', borderRadius: 12, background: 'rgba(255,255,255,0.02)' }}>


          <defs>


            <linearGradient id="gradArea" x1="0" x2="0" y1="0" y2="1">


              <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.32" />


              <stop offset="100%" stopColor="#0b1021" stopOpacity="0" />


            </linearGradient>


          </defs>


          {yTicks.map((t, i) => (


            <g key={i}>


              <line x1={pad} x2={width - pad} y1={t.y} y2={t.y} stroke="rgba(255,255,255,0.06)" strokeDasharray="4 4" />


              <text x={8} y={t.y + 4} fill="#94a3b8" fontSize={10}>


                {toFixed(t.v, 2)}


              </text>


            </g>


          ))}


          <path d={`${path} L ${width - pad} ${height - pad} L ${pad} ${height - pad} Z`} fill="url(#gradArea)" opacity={0.6} />


          <path d={path} fill="none" stroke="#22d3ee" strokeWidth={3} strokeLinejoin="round" strokeLinecap="round" />


          {scaled.map((p, i) => (


            <circle


              key={i}


              cx={p.x}


              cy={p.y}


              r={i === hoverIdx ? 4.2 : 2.5}


              fill={i === hoverIdx ? '#22c55e' : '#22d3ee'}


              opacity={i % 4 === 0 || i === hoverIdx ? 0.9 : 0.4}


            />


          ))}


          <rect
            x={pad}
            y={pad}
            width={width - pad * 2}
            height={height - pad * 2}
            fill="transparent"
            onMouseLeave={() => setHover(null)}
            onMouseMove={(e) => {
              const bounds = (e.target as SVGRectElement).getBoundingClientRect();
              const x = e.clientX - bounds.left; // local to the hit-rect
              const rectWidth = Math.max(1, bounds.width);
              const percent = Math.min(1, Math.max(0, x / rectWidth));
              const idx = Math.min(points.length - 1, Math.max(0, Math.round(percent * (points.length - 1))));
              setHover(idx);
            }}
          />


        </svg>


        {hoverPoint && (


          <div


            style={{


              position: 'absolute',


              left: `${((hoverPoint.x - pad) / (width - pad * 2)) * 100}%`,


              top: `${Math.max(4, hoverPoint.y - 90)}px`,


              transform: 'translateX(-50%)',


              background: '#0f172a',


              border: '1px solid rgba(255,255,255,0.08)',


              borderRadius: 10,


              padding: '8px 10px',


              color: '#e5e7eb',


              boxShadow: '0 10px 30px rgba(0,0,0,0.35)',


              pointerEvents: 'none',


            }}


          >


            <div style={{ fontWeight: 700 }}>${toFixed(hoverPoint.close, 2)}</div>


            <div className="muted" style={{ fontSize: 11 }}>


              {timeFmt(hoverPoint.time)}


            </div>


          </div>


        )}


      </div>


    </div>


  );


};





const CryptoPanel = ({


  asset,


  setAsset,


}: {


  asset: 'BTC' | 'ETH' | 'SOL';


  setAsset: (a: 'BTC' | 'ETH' | 'SOL') => void;


}) => {


  const [timeframe, setTimeframe] = useState<'1d' | '7d' | '30d' | '90d'>('7d');


  const { data = [], isFetching } = useCryptoSeries(asset, timeframe);


  const latest = data.at(-1)?.close;





  return (


    <div className="crypto-panel fade-slide">


      <div className="crypto-tabs">


        {(['BTC', 'ETH', 'SOL'] as const).map((sym) => (


          <button key={sym} className={`tab ${asset === sym ? 'active' : ''}`} onClick={() => setAsset(sym)}>


            {sym}


          </button>


        ))}


      </div>


      <div className="chart-card">


        <div className="chart-head">


          <div>


            <div style={{ fontWeight: 700 }}>Live (Binance)</div>


            <div className="muted">{asset} / USD</div>


          </div>


          <div style={{ color: '#22c55e', fontWeight: 700 }}>{latest ? `$${toFixed(latest, 2)}` : 'Loading...'}</div>


        </div>


        <CryptoChart asset={asset} series={data} timeframe={timeframe} onTimeframeChange={(tf) => setTimeframe(tf as any)} />


        {isFetching && <div className="muted">Updating price...</div>}


        <div className="muted">Demo view only - connect real markets to place on-chain bets.</div>


      </div>


    </div>


  );


};





const MarketList = ({


  onSelect,


  selectedId,


  mode,


  setMode,


  cryptoAsset,


  setCryptoAsset,


}: {


  onSelect: (id: string | null) => void;


  selectedId: string | null;


  mode: 'normal' | 'crypto';


  setMode: (m: 'normal' | 'crypto') => void;


  cryptoAsset: 'BTC' | 'ETH' | 'SOL';


  setCryptoAsset: (a: 'BTC' | 'ETH' | 'SOL') => void;


}) => {


  const { data, isLoading, error } = useMarkets();


  const [coinFilter, setCoinFilter] = useState<string>('all');


  const isCrypto = mode === 'crypto';


  const filtered = (data ?? []).filter((m) => coinFilter === 'all' || m.coinType === coinFilter);





  return (


    <div className={`panel ${isCrypto ? '' : 'fade-slide'}`}>


      <div className="panel-head">


        <h2>Markets</h2>


        <div className="mode-toggle">


          <span className="mode-active">{isCrypto ? 'Crypto' : 'Normal'}</span>


          <div className={`toggle-pill ${isCrypto ? 'on' : ''}`} onClick={() => setMode(isCrypto ? 'normal' : 'crypto')}>


            <div className="thumb" style={isCrypto ? { transform: 'translateX(26px)' } : undefined} />


          </div>


          <span style={{ color: isCrypto ? '#e5e7eb' : '#94a3b8' }}>Crypto</span>


        </div>


      </div>


      {isCrypto ? (


        <CryptoPanel asset={cryptoAsset} setAsset={setCryptoAsset} />


      ) : (


        <>


          {isLoading && <div className="muted">Loading markets...</div>}


          {error && <div className="muted">Failed to load markets. Check network or refresh.</div>}


          <div className="market-list">


            {filtered.map((m) => {


              const yesBps = priceYesBps(m.yesVault, m.noVault);


              const noBps = priceNoBps(m.yesVault, m.noVault);


              const yesPct = yesBps / 100;


              const noPct = noBps / 100;


              const multYes = yesPct > 0 ? toFixed(100 / yesPct, 2) : 0;


              const multNo = noPct > 0 ? toFixed(100 / noPct, 2) : 0;


              return (


                <div key={m.id} className="market-card">


                  <div className="market-card-info">


                    <div className="market-title">{m.question}</div>


                    <div className="muted">Coin: {coinSymbol(m.coinType)}</div>


                    <div className="stats">


                      <div className="stat">


                        <span>YES</span>


                        <strong>{yesPct.toFixed(2)}%</strong>


                        <div className="muted">{multYes}</div>


                      </div>


                      <div className="stat">


                        <span>NO</span>


                        <strong>{noPct.toFixed(2)}%</strong>


                        <div className="muted">{multNo}</div>


                      </div>


                      <div className="stat">


                        <span>Status</span>


                        <strong>{m.resolved ? 'Resolved' : 'Open'}</strong>


                      </div>


                    </div>


                  </div>


                  <div className="market-card-actions">


                    <button onClick={() => onSelect(m.id)}>{selectedId === m.id ? 'Viewing' : 'View'}</button>


                  </div>


                </div>


              );


            })}


            {!isLoading && filtered.length === 0 && <div className="card-empty">No markets found. Create one on-chain.</div>}


          </div>


        </>


      )}


    </div>


  );


};





const PositionList = ({


  portfolio,


  selectedMarket,


  onSell,


  onRedeem,


}: {


  portfolio: Portfolio | undefined;


  selectedMarket: MarketInfo | null;


  onSell: (pos: Position, minOut: number) => void;


  onRedeem: (pos: Position) => void;


}) => {


  if (!selectedMarket) return null;


  const positions = portfolio?.positions.filter((p) => p.marketId === selectedMarket.id) ?? [];


  if (!positions.length) return <div className="card-empty">No positions for this market yet.</div>;


  return (


    <div className="portfolio-list">


      {positions.map((p) => (


        <div key={p.id} className="mini-card">


          <div className="mini-title">


            {p.sideYes ? 'YES' : 'NO'}  {p.shares} shares


          </div>


          <div className="muted">{p.id}</div>


          <div className="form-row">


            <input type="number" min={0} placeholder="Min out (optional)" onChange={(e) => onSell(p, Number(e.target.value) || 0)} />


            <button className="secondary" onClick={() => onRedeem(p)}>


              Redeem / Sell


            </button>


          </div>


        </div>


      ))}


    </div>


  );


};





const MarketDetails = ({


  market,


  mode,


  cryptoAsset,


  setCryptoAsset,


}: {


  market: MarketInfo | null;


  mode: 'normal' | 'crypto';


  cryptoAsset: 'BTC' | 'ETH' | 'SOL';


  setCryptoAsset: (a: 'BTC' | 'ETH' | 'SOL') => void;


}) => {


  const account = useCurrentAccount();


  const onTestnet = account?.chains?.includes(expectedChain) ?? true;


  const client = useSuiClient();


  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction({


    execute: async ({ bytes, signature }) =>


      client.executeTransactionBlock({


        transactionBlock: bytes,


        signature,


        options: { showEffects: true, showObjectChanges: true },


        requestType: 'WaitForEffectsCert',


      }),


  });


  const { data: portfolio } = usePortfolio(account?.address);


  const queryClient = useQueryClient();





  const [buyYesAmount, setBuyYesAmount] = useState(0);


  const [buyNoAmount, setBuyNoAmount] = useState(0);


  const [liqAmount, setLiqAmount] = useState(0);


  const [orderPrice, setOrderPrice] = useState(5000);


  const [orderShares, setOrderShares] = useState(10);


  const [orderExpiryHours, setOrderExpiryHours] = useState(24);


  const [orderAmount, setOrderAmount] = useState(1);
  const [resolutionOutcome, setResolutionOutcome] = useState(true);
  const [bondAmount, setBondAmount] = useState(1);
  const [pythUpdate, setPythUpdate] = useState('');
  const [minSlippageYes, setMinSlippageYes] = useState(0);
  const [minSlippageNo, setMinSlippageNo] = useState(0);
  const [betAsset, setBetAsset] = useState<'BTC' | 'ETH' | 'SOL'>(cryptoAsset);
  const [betPrice, setBetPrice] = useState(70000);
  const [betDate, setBetDate] = useState(() => {
    const dt = new Date();
    dt.setDate(dt.getDate() + 7);


    return dt.toISOString().slice(0, 16);


  });


  const [betStake, setBetStake] = useState(0.1);


  const [betDirection, setBetDirection] = useState<'above' | 'below'>('above');





  useEffect(() => {


    setBuyYesAmount(0);


    setBuyNoAmount(0);


    setLiqAmount(0);


    setOrderAmount(1);


    setOrderPrice(5000);


    setOrderShares(10);


  }, [market?.id]);





  useEffect(() => {


    setBetAsset(cryptoAsset);


  }, [cryptoAsset]);





  const tradeDisabled = !account || !onTestnet || !market;
  const coinDec = market ? coinDecimals(market.coinType) : 9;
  const [toasts, setToasts] = useState<{ id: number; type: 'success' | 'error'; text: string }[]>([]);

  const showToast = (type: 'success' | 'error', text: string) => {
    const id = Date.now();
    setToasts((prev) => [...prev, { id, type, text }]);
    setTimeout(() => setToasts((prev) => prev.filter((t) => t.id !== id)), 4000);
  };

  const runTx = async (tx: Transaction) => {
    try {
      await signAndExecute({
        transaction: tx,
        chain: expectedChain,
        options: { showEffects: true, showEvents: true },
      });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['markets'] }),
        queryClient.invalidateQueries({ queryKey: ['portfolio', account?.address] }),
      ]);
      showToast('success', 'Transaction submitted');
    } catch (e: any) {
      const raw = typeof e?.message === 'string' ? e.message : `${e}`;
      const msg = raw.includes('Could not parse effects') ? 'Wallet could not parse the response. Please retry; check network/wallet.' : raw;
      showToast('error', msg);
      throw e;
    }
  };



  if (!market) {


    return (


      <div className="panel fade-slide">


        <h2>Market Detail</h2>


        <div className="card-empty">Select a market to trade.</div>


      </div>


    );


  }





  if (mode === 'crypto') {


    const potential = betStake > 0 ? `${(betStake * 1.9).toFixed(2)} SUI` : '';


    return (


      <div className="panel crypto-detail fade-slide">


        <div className="panel-head">


          <h2>Crypto Bet</h2>


          <div className="tag pending">Demo</div>


        </div>


        <div className="crypto-grid">


          <div className="action-card">


            <h3>Setup bet</h3>


            <div className="form-row">


              <select


                value={betAsset}


                onChange={(e) => {


                  const next = e.target.value as 'BTC' | 'ETH' | 'SOL';


                  setBetAsset(next);


                  setCryptoAsset(next);


                }}


              >


                <option value="BTC">BTC</option>


                <option value="ETH">ETH</option>


                <option value="SOL">SOL</option>


              </select>


              <select value={betDirection} onChange={(e) => setBetDirection(e.target.value as 'above' | 'below')}>


                <option value="above">Above target</option>


                <option value="below">Below target</option>


              </select>


            </div>


            <div className="form-row">


              <input


                type="number"


                min={0}


                step="10"


                value={betPrice}


                onChange={(e) => setBetPrice(Math.max(0, Number(e.target.value)))}


                placeholder="Target price (USD)"


              />


              <input


                type="datetime-local"


                value={betDate}


                onChange={(e) => setBetDate(e.target.value)}


              />


            </div>


          </div>





          <div className="action-card">


            <h3>Stake (SUI)</h3>


            <input


              type="number"


              min={0}


              step="0.01"


              value={betStake}


              onChange={(e) => setBetStake(Math.max(0, Number(e.target.value)))}


              placeholder="Amount in SUI"


            />


            <button className="primary" disabled>Place demo bet</button>


            <div className="helper">Demo-only UI. Connect a real on-chain market to submit.</div>


          </div>





          <div className="action-card">


            <h3>Summary</h3>


            <div className="summary-line"><span>Asset</span><strong>{betAsset} / USD</strong></div>


            <div className="summary-line"><span>Thesis</span><strong>{betDirection === 'above' ? 'Will be above' : 'Will be below'}</strong></div>


            <div className="summary-line"><span>Target</span><strong>${betPrice.toLocaleString()}</strong></div>


            <div className="summary-line">


              <span>Expires</span>


              <strong>{betDate ? new Date(betDate).toLocaleString() : ''}</strong>


            </div>


            <div className="summary-line"><span>Stake</span><strong>{betStake || 0} SUI</strong></div>


            <div className="summary-line"><span>Est. payout (demo)</span><strong>{potential}</strong></div>


          </div>


        </div>


      </div>


    );


  }





  const yesBps = priceYesBps(market.yesVault, market.noVault);


  const noBps = priceNoBps(market.yesVault, market.noVault);


  const yesPct = yesBps / 100;


  const noPct = noBps / 100;





  const lpForMarket = portfolio?.lps.filter((l) => l.marketId === market.id) ?? [];


  const ordersForMarket = portfolio?.orders.filter((o) => o.marketId === market.id) ?? [];





  const submitBuy = async (sideYes: boolean) => {


    const amt = sideYes ? buyYesAmount : buyNoAmount;


    if (!amt || amt <= 0) return;


    const mist = toMist(amt, coinDec);


    const tx = sideYes


      ? buildBuyYes(market.id, market.coinType, mist, minSlippageYes)


      : buildBuyNo(market.id, market.coinType, mist, minSlippageNo);


    await runTx(tx);


  };





  const submitLiquidity = async () => {


    if (!liqAmount || liqAmount <= 0) return;


    const mist = toMist(liqAmount, coinDec);


    const tx = buildAddLiquidity(market.id, market.coinType, mist, 0);


    await runTx(tx);


  };





  const submitLimitOrder = async (sideYes: boolean) => {


    const mist = toMist(orderAmount, coinDec);


    const expiry = Date.now() + msFromHours(orderExpiryHours);


    const tx = buildCreateOrder(market.id, market.coinType, sideYes, orderPrice, orderShares, expiry, mist);


    await runTx(tx);


  };





  const propose = async (outcome: boolean) => {


    const tx = buildPropose(market.id, market.coinType, outcome, toMist(bondAmount, coinDec));


    await runTx(tx);


  };





  const challenge = async (outcome: boolean) => {


    const tx = buildChallenge(market.id, market.coinType, outcome, toMist(bondAmount, coinDec));


    await runTx(tx);


  };





  const finalize = async (outcome: boolean) => {


    if (!ids.adminCapId) return;


    const tx = buildFinalize(market.id, market.coinType, outcome, ids.adminCapId, pythUpdate);


    await runTx(tx);


  };





  const cancelOrder = async (orderId: string) => {


    const tx = buildCancelOrder(market.id, orderId, market.coinType);


    await runTx(tx);


  };





  const sellPosition = async (pos: Position, minOut: number) => {


    if (market.resolved) {


      const tx = buildRedeem(market.id, pos.id, market.coinType);


      await runTx(tx);


      return;


    }


    const tx = pos.sideYes


      ? buildSellYes(market.id, market.coinType, pos.id, minOut)


      : buildSellNo(market.id, market.coinType, pos.id, minOut);


    await runTx(tx);


  };





  const redeemPosition = async (pos: Position) => {


    const tx = buildRedeem(market.id, pos.id, market.coinType);


    await runTx(tx);


  };





  const removeLp = async (lpId: string) => {


    const tx = buildRemoveLiquidity(market.id, lpId, market.coinType);


    await runTx(tx);


  };





  return (


    <div className="panel fade-slide">


      <div className="panel-head">


        <h2>Market Detail</h2>


        <div className={`tag ${market.resolved ? 'resolved' : 'pending'}`}>{market.resolved ? 'Resolved' : 'Open'}</div>


      </div>


      <div className="dual">


        <div className="mini-card">


          <div className="mini-title">{market.question}</div>


          <div className="muted">Ends: {formatDate(market.endTimeMs)}</div>


          <div className="helper">Coin: {coinSymbol(market.coinType)}</div>


        </div>


        <div className="mini-card">


          <div className="mini-title">Prices</div>


          <div className="stats">


            <div className="stat">


              <span>YES</span>


              <strong>{yesPct.toFixed(2)}%</strong>


            </div>


            <div className="stat">


              <span>NO</span>


              <strong>{noPct.toFixed(2)}%</strong>


            </div>


            <div className="stat">


              <span>Fee</span>


              <strong>{market.feeBps / 100}%</strong>


            </div>


          </div>


        </div>


      </div>





      <div className="actions">


        <div className="dual">


          <div className="action-card">


            <h3>Buy YES</h3>


            <input


              type="number"


              min={0}


              step="0.0001"


              value={buyYesAmount}


              onChange={(e) => setBuyYesAmount(Math.max(0, Number(e.target.value)))}


              placeholder={`Amount in ${coinSymbol(market.coinType)}`}


            />


            <button className="primary" disabled={tradeDisabled} onClick={() => submitBuy(true)}>


              Buy YES


            </button>


          </div>


          <div className="action-card">


            <h3>Buy NO</h3>


            <input


              type="number"


              min={0}


              step="0.0001"


              value={buyNoAmount}


              onChange={(e) => setBuyNoAmount(Math.max(0, Number(e.target.value)))}


              placeholder={`Amount in ${coinSymbol(market.coinType)}`}


            />


            <button className="primary" disabled={tradeDisabled} onClick={() => submitBuy(false)}>


              Buy NO


            </button>


          </div>


        </div>





        <div className="dual">


          <div className="action-card">


            <h3>Add balanced liquidity</h3>


            <input


              type="number"


              min={0}


              step="0.0001"


              value={liqAmount}


              onChange={(e) => setLiqAmount(Math.max(0, Number(e.target.value)))}


              placeholder={`Amount in ${coinSymbol(market.coinType)}`}


            />


            <button className="primary" disabled={tradeDisabled} onClick={submitLiquidity}>


              Add liquidity


            </button>


          </div>


          <div className="action-card">


            <h3>Limit order</h3>


            <div className="form-row">


              <select value={resolutionOutcome ? 'yes' : 'no'} onChange={(e) => setResolutionOutcome(e.target.value === 'yes')}>


                <option value="yes">Buy YES</option>


                <option value="no">Buy NO</option>


              </select>


              <input


                type="number"


                min={1}


                max={10_000}


                step="1"


                value={orderPrice}


                onChange={(e) => setOrderPrice(Math.max(1, Number(e.target.value)))}


                placeholder="Price (bps)"


              />


              <input


                type="number"


                min={1}


                step="1"


                value={orderShares}


                onChange={(e) => setOrderShares(Math.max(1, Number(e.target.value)))}


                placeholder="Max shares"


              />


              <input


                type="number"


                min={1}


                step="1"


                value={orderExpiryHours}


                onChange={(e) => setOrderExpiryHours(Math.max(1, Number(e.target.value)))}


                placeholder="Expiry (h)"


              />


              <input


                type="number"


                min={0}


                step="0.0001"


                value={orderAmount}


                onChange={(e) => setOrderAmount(Math.max(0, Number(e.target.value)))}


                placeholder={`Escrow ${coinSymbol(market.coinType)}`}


              />


            </div>


            <button className="primary" disabled={tradeDisabled} onClick={() => submitLimitOrder(resolutionOutcome)}>


              Create order


            </button>


          </div>


        </div>





        <div className="portfolio-stack">


          <div className="action-card">


            <h3>Your LP</h3>


            {lpForMarket.length === 0 && <div className="card-empty">No LP positions yet.</div>}


            {lpForMarket.map((lp) => (


              <div key={lp.id} className="form-row">


                <div className="muted">LP {lp.id.slice(0, 8)} - {lp.shares} shares</div>


                <button className="secondary" disabled={tradeDisabled} onClick={() => removeLp(lp.id)}>


                  Remove LP


                </button>


              </div>


            ))}


          </div>





          <div className="action-card">


            <h3>Your positions</h3>


            <PositionList


              portfolio={portfolio}


              selectedMarket={market}


              onSell={(pos, minOut) => sellPosition(pos, minOut)}


              onRedeem={(pos) => redeemPosition(pos)}


            />


          </div>





          <div className="action-card">


            <h3>Your orders</h3>


            {ordersForMarket.length === 0 && <div className="card-empty">No open orders.</div>}


            {ordersForMarket.map((o) => (


              <div key={o.id} className="mini-card">


                <div className="mini-title">


                  {o.sideYes ? 'YES' : 'NO'} @ {o.priceBps} bps - {o.remainingShares}/{o.maxShares} shares


                </div>


                <div className="muted">Expires: {formatDate(o.expiryMs)}</div>


                <button className="secondary" disabled={tradeDisabled} onClick={() => cancelOrder(o.id)}>


                  Cancel


                </button>


              </div>


            ))}


          </div>


        </div>





        <div className="dual res-grid">


          <div className="action-card">


            <h3>Resolution (propose/challenge)</h3>


            <div className="form-row">


              <select value={resolutionOutcome ? 'yes' : 'no'} onChange={(e) => setResolutionOutcome(e.target.value === 'yes')}>


                <option value="yes">Outcome YES</option>


                <option value="no">Outcome NO</option>


              </select>


              <input


                type="number"


                min={0}


                step="0.0001"


                value={bondAmount}


                onChange={(e) => setBondAmount(Math.max(0, Number(e.target.value)))}


                placeholder="Bond amount (SUI)"


              />


            </div>


            <div className="form-row">


              <button className="secondary" disabled={tradeDisabled || !ids.adminCapId} onClick={() => propose(resolutionOutcome)}>


                Propose


              </button>


              <button className="secondary" disabled={tradeDisabled || !ids.adminCapId} onClick={() => challenge(!resolutionOutcome)}>


                Challenge opposite


              </button>


            </div>


            <div className="helper">Requires AdminCap + resolution bond set in protocol config.</div>


          </div>





          <div className="action-card">


            <h3>Finalize (admin)</h3>


            <textarea


              value={pythUpdate}


              onChange={(e) => setPythUpdate(e.target.value)}


              placeholder="Pyth update bytes (hex). Leave empty to skip."


              style={{


                minHeight: 80,


                borderRadius: 10,


                padding: 10,


                border: '1px solid rgba(255,255,255,0.1)',


                background: 'rgba(12,16,32,0.8)',


                color: '#e5e7eb',


              }}


            />


            <div className="form-row">


              <button className="secondary" disabled={tradeDisabled || !ids.adminCapId} onClick={() => finalize(true)}>


                Finalize YES


              </button>


              <button className="secondary" disabled={tradeDisabled || !ids.adminCapId} onClick={() => finalize(false)}>


                Finalize NO


              </button>


            </div>


            <div className="helper subtle">AdminCap required. Pyth update optional in demo.</div>
          </div>
        </div>

        <div className="toast-stack">
          {toasts.map((t) => (
            <div key={t.id} className={`toast ${t.type}`}>
              {t.text}
            </div>
          ))}
        </div>

      </div>
    </div>
  );
};



const ProfileCard = ({ portfolio }: { portfolio?: Portfolio }) => {


  const account = useCurrentAccount();


  const addressShort = account?.address ? `${account.address.slice(0, 6)}...${account.address.slice(-4)}` : '';


  const positions = portfolio?.positions.length ?? 0;


  const lps = portfolio?.lps.length ?? 0;


  const orders = portfolio?.orders.length ?? 0;





  const copyAddr = () => {


    if (account?.address && navigator?.clipboard) {


      navigator.clipboard.writeText(account.address).catch(() => {});


    }


  };





  return (


    <div className="panel profile-panel fade-slide">


      <div className="profile-head">


        <div className="avatar">{account?.address ? account.address.slice(2, 4).toUpperCase() : '?'}</div>


        <div className="profile-meta">


          <div className="muted">Connected wallet</div>


          {account ? (


            <div className="address-row">


              <code className="mono">{addressShort}</code>


              <button className="ghost-btn" onClick={copyAddr}>


                Copy


              </button>


            </div>


          ) : (


            <div className="muted">Connect to see balances</div>


          )}


        </div>


        <div className="chip">{account?.chains?.[0] ?? 'Unknown'}</div>


      </div>





      {!account && <div className="card-empty">Connect wallet to view profile.</div>}





      {account && (


        <>


          <div className="profile-grid">


            <div className="stat-card">


              <span className="muted">Positions</span>


              <strong>{positions}</strong>


              <div className="muted tiny">Across current markets</div>


            </div>


            <div className="stat-card">


              <span className="muted">LP tokens</span>


              <strong>{lps}</strong>


              <div className="muted tiny">Active liquidity seats</div>


            </div>


            <div className="stat-card">


              <span className="muted">Orders</span>


              <strong>{orders}</strong>


              <div className="muted tiny">Open limit orders</div>


            </div>


          </div>


          <div className="helper subtle">


            Tip: stay on Testnet. Switch to Normal/Crypto modes to explore markets and price feeds.


          </div>


        </>


      )}


    </div>


  );


};





const AppShell = () => {


  const account = useCurrentAccount();


  const { data: portfolio } = usePortfolio(account?.address);


  const [selected, setSelected] = useState<string | null>(null);


  const [mode, setMode] = useState<'normal' | 'crypto'>('normal');


  const { data: markets } = useMarkets();


  const [cryptoAsset, setCryptoAsset] = useState<'BTC' | 'ETH' | 'SOL'>('BTC');


  const selectedMarket = markets?.find((m) => m.id === selected) ?? null;





  useEffect(() => {


    if (markets && markets.length && !selected) {


      setSelected(markets[0].id);


    }


  }, [markets, selected]);





  return (


    <div className="shell">


      <div className="header">


        <div className="title">


          <h1>On-chain Prediction Market (Sui Testnet)</h1>


          <span>DeFi-style AMM, limit orders, optimistic resolution. No backend.</span>


        </div>


        <ConnectButton connectText="Connect Wallet" />


      </div>


      <div className="grid">


        <MarketList onSelect={setSelected} selectedId={selected} mode={mode} setMode={setMode} cryptoAsset={cryptoAsset} setCryptoAsset={setCryptoAsset} />


        <MarketDetails market={selectedMarket} mode={mode} cryptoAsset={cryptoAsset} setCryptoAsset={setCryptoAsset} />


      </div>


      <div style={{ marginTop: 12 }}>


        <ProfileCard portfolio={portfolio} />


      </div>


    </div>


  );


};





const Providers = ({ children }: { children: React.ReactNode }) => {


  return (


    <QueryClientProvider client={queryClient}>


      <SuiClientProvider networks={networkConfig} defaultNetwork={DEFAULT_NETWORK}>


        <WalletProvider autoConnect theme={null}>{children}</WalletProvider>


      </SuiClientProvider>


    </QueryClientProvider>


  );


};





const App = () => {


  return (


    <Providers>


      <div className="app">


        <TestnetBanner />


        <NetworkBlocker expectedChain={expectedChain} />


        <AppShell />


      </div>


    </Providers>


  );


};





export default App;
