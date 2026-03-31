# xYield Protocol — Technical Specification

> Premier protocole d'autocall permissionless sur tokenized equities.
> Pricing par Chainlink CRE Oracle + On-Chain Verification.
> Hedge delta-neutre on-chain. Multi-source carry engine. Coupon streaming temps reel.
> Deploye sur Ink (Kraken L2) — xStocks natifs, Nado perps, Tydro lending.

---

## 1. Produit

```
Phoenix Autocall — worst-of 3 xStocks, European KI, memory coupon

Basket :            3 xStocks au choix (NVDAx, TSLAx, METAx, AAPLx, MSFTx, AMZNx, GOOGLx)
Maturite :          6 mois
Observations :      Mensuelles (6 observations)
Coupon barrier :    70% (worst-of >= 70% -> coupon paye)
Autocall trigger :  100%, step-down 2% par observation
KI barrier :        50% (European — maturite seulement)
Memory coupon :     Oui (base coupon uniquement)
Settlement :        USDC (autocall/maturite) ou choix holder au KI (xStocks ou USDC)
Coupon :            ~12% ann = base (option premium) + carry enhancement (funding + lending)
Deposit :           USDC
```

---

## 2. Architecture

```
contracts/
├── core/
│   ├── AutocallEngine.sol          <- State machine 12 etats, observe, settle
│   ├── NoteToken.sol               <- ERC-1155 note positions
│   └── XYieldVault.sol             <- ERC-7540 async vault (requestDeposit/claim)
│
├── pricing/
│   ├── OptionPricer.sol            <- Approx analytique on-chain (verification)
│   ├── CREConsumer.sol             <- Chainlink CRE consumer (recoit pricing du DON)
│   ├── VolOracle.sol               <- Stocke vols implicites + correlations (alimente par CRE)
│   ├── CouponCalculator.sol        <- base = premium - margin, enhance = carry share
│   └── IssuanceGate.sol            <- 4 pre-checks avant emission
│
├── hedge/
│   ├── HedgeManager.sol            <- Orchestre spot + perps + collateral
│   └── CarryEngine.sol             <- Multi-source carry (funding + lending)
│
├── integrations/
│   ├── NadoAdapter.sol             <- Nado stock perps (Ink)
│   ├── ChainlinkPriceFeed.sol      <- Data Streams v10 verify on-chain
│   ├── ChainlinkCRE.sol            <- CRE workflows: pricing, vol oracle, epochs
│   ├── TydroAdapter.sol            <- Tydro (Aave v3) collateral + borrow
│   ├── OneInchSwapper.sol          <- Swap with retry + slippage control
│   └── SablierStream.sol           <- Coupon streaming temps reel
│
├── periphery/
│   ├── ReserveFund.sol             <- Buffer coupon smoothing (Ethena model)
│   ├── EpochManager.sol            <- 48h cycles: NAV, waterfall, rebalance
│   └── FeeCollector.sol            <- Fee collection + distribution
│
└── scripts/
    └── mc-pricer/                  <- Off-chain Monte Carlo pricer (Rust or TS)
        └── src/main.rs             <- GBM correle, Cholesky, worst-of pricing
```

---

## 3. Stack & Adresses

```
CHAIN : Ink (Kraken L2, OP Stack)
        xStocks NATIFS sur Ink — pas de bridge necessaire

xStocks tokens (natifs sur Ink, aussi sur Ethereum) :
  NVDAx   0xc845b2894dbddd03858fd2d643b4ef725fe0849d
  TSLAx   0x8ad3c73f833d3f9a523ab01476625f269aeb7cf0
  METAx   0x96702be57cd9777f835117a809c7124fe4ec989a
  AAPLx   0x9d275685dc284c8eb1c79f6aba7a63dc75ec890a
  MSFTx   0x5621737f42dae558b81269fcb9e9e70c19aa6b35
  AMZNx   0x3557ba345b01efa20a1bddc61f573bfd87195081
  (adresses Ink a confirmer — deploiement natif via Backed Finance)

Nado (Ink) :
  Perp DEX avec unified margin, stock perps disponibles
  Adresses et pair indexes a confirmer via Nado CLI/MCP

Tydro (Ink) :
  Lending protocol (Aave v3 fork), incube par Kraken
  xStocks collateral : coming soon
  Adresses a confirmer

Chainlink (Ink) :
  Data Streams           Deploye sur Ink (fev 2025)
  Data Feeds             Deploye sur Ink (fev 2025)
  CCIP                   Deploye sur Ink (fev 2025)
  CRE                    A confirmer (Early Access, supporte OP Stack)
  Supported : NVDA, AAPL, TSLA, MSFT, META, GOOGL, MSTR + ETFs

1inch :
  Swap aggregator sur Ink

Tradier (off-chain, via CRE) :
  API REST : api.tradier.com/v1/markets/options/chains
  Vol implicite reelle (source ORATS, MAJ toutes les heures)
  Stocks supportes : NVDA, TSLA, META, AAPL, MSFT, AMZN, GOOGL
  Cout : $10/mois (plan Pro)
  Rate limit : 120 req/min (on utilise ~3/heure)
  Fournit : mid_iv, bid_iv, ask_iv, smv_vol + Greeks (delta, gamma, theta, vega)
```

---

## 4. Pricing Engine — Chainlink CRE + On-Chain Verification

Le pricing repose sur 3 couches de securite : Monte Carlo off-chain, consensus DON Chainlink (CRE), et verification on-chain.

### 4.1 Monte Carlo off-chain (Rust or TypeScript)

```rust
// mc-pricer/src/main.rs — runs off-chain, called by CRE workflow via HTTP

struct MCInputs {
    spot_prices: [u64; 3],       // Chainlink prices (1e8)
    impl_vols: [u64; 3],         // implied vols (bps)
    correlations: [u64; 3],      // pairwise rho (bps) [rho12, rho13, rho23]
    ki_barrier_bps: u64,         // 5000 = 50%
    coupon_barrier_bps: u64,     // 7000 = 70%
    autocall_trigger_bps: u64,   // 10000 = 100%
    step_down_bps: u64,          // 200 = 2%
    maturity_days: u64,          // 180
    num_observations: u64,       // 6
    num_paths: u64,              // 10000
    rng_seed: [u8; 32],          // keccak256(blockHash, noteId)
}

struct MCOutput {
    put_premium_bps: u64,        // fair value annualisee
    ki_probability_bps: u64,     // probabilite de KI
    expected_ki_loss_bps: u64,   // perte moyenne si KI
    avg_autocall_month: u64,     // mois moyen avant autocall
    vega_bps: u64,               // sensibilite a la vol
}

// Algorithme :
// 1. Decomposition de Cholesky sur la matrice de correlation
// 2. Pour chaque path (10,000) :
//    a. Generer 3 GBM correles : dS/S = (r - sigma^2/2)dt + sigma*dW
//    b. A chaque observation (6) : calculer worst = min(perf_i)
//    c. Check autocall : worst >= trigger (avec step-down)
//    d. Check coupon : worst >= coupon barrier
//    e. A maturite : check KI (worst < 50%)
// 3. Agreger : premium = E[protocol_payoff] / notional (annualise)
//
// RNG deterministe : ChaCha20 avec seed = keccak256(blockHash, noteId)
// -> N'importe qui peut re-run et obtenir le meme resultat
```

### 4.2 Chainlink CRE Oracle

Le CRE (Chainlink Runtime Environment) remplace un systeme multi-signer custom.
Chaque noeud du DON Chainlink (20+ noeuds) execute le workflow independamment,
puis consensus BFT automatique sur le resultat.

```
CRE Workflow "xYield-Pricing" :

  TRIGGER : EVM log (RequestPricing event emis par AutocallEngine)

  CALLBACK :
    1. HTTP GET -> API MC externe (serveur Rust xYield)
       Chaque noeud DON appelle l'API independamment
    2. Consensus BFT sur le resultat MC (20+ noeuds, quorum 2/3)
    3. EVM write -> CREConsumer.fulfillPricing(noteId, result)

  CREConsumer.sol verifie :
    - Resultat dans les bornes [MIN_PREMIUM, MAX_PREMIUM]
    - Cross-check vs OptionPricer.verifyPricing() (approx on-chain)
    - Si OK -> pricing accepte

CRE Workflow "xYield-VolOracle" :

  TRIGGER : cron (toutes les heures)

  CALLBACK :
    1. HTTP GET -> api.tradier.com/v1/markets/options/chains
       ?symbol=NVDA&expiration={6mo}&greeks=true
       -> mid_iv pour NVDA (ex: 0.55 = 55%)
    2. HTTP GET -> meme endpoint pour TSLA (ex: mid_iv = 0.60)
    3. HTTP GET -> meme endpoint pour META (ex: mid_iv = 0.40)
       (3 requetes sur 5 max CRE = OK)
    4. Consensus DON sur les 3 vols implicites
    5. EVM write -> VolOracle.updateVols(
         [NVDA, TSLA, META],
         [5500, 6000, 4000],     // vols en bps
         [5500, 4800, 5200]      // correlations pairwise (rolling 30j Chainlink)
       )

  Source : Tradier API (ORATS data, vol implicite reelle des options US)
  Cout : $10/mois, 120 req/min
  Fallback si Tradier/CRE down : vol realisee on-chain (Chainlink prices, 30j rolling)

Avantages vs Multi-Signer custom :
  - 20+ noeuds Chainlink au lieu de 3-5 signers custom
  - Pas d'infra signer a gerer
  - Consensus BFT natif
  - Resout aussi le VolOracle (2 workflows, 1 infra)
```

```solidity
/// @notice Receives pricing results from Chainlink CRE workflow
contract CREConsumer {

    address public immutable creRouter;  // Chainlink CRE router

    struct PricingResult {
        uint16 putPremiumBps;
        uint16 kiProbabilityBps;
        uint16 expectedKILossBps;
        uint16 vegaBps;
        bytes32 inputsHash;
    }

    /// @notice Called by CRE workflow after DON consensus
    function fulfillPricing(
        bytes32 noteId,
        PricingResult calldata result
    ) external onlyCRERouter {
        // 1. Bounds check
        require(result.putPremiumBps >= MIN_PREMIUM, "premium too low");
        require(result.putPremiumBps <= MAX_PREMIUM, "premium too high");

        // 2. Cross-check vs on-chain approximation
        (bool approved, ) = optionPricer.verifyPricing(
            _getNoteParams(noteId), result.putPremiumBps, result.inputsHash
        );
        require(approved, "CRE vs on-chain divergence");

        // 3. Store accepted pricing
        acceptedPricings[noteId] = result;
        emit PricingAccepted(noteId, result.putPremiumBps, result.kiProbabilityBps);
    }

    modifier onlyCRERouter() {
        require(msg.sender == creRouter, "only CRE router");
        _;
    }
}
```

### 4.3 On-Chain Approximation (couche de verification finale)

```solidity
/// @notice Analytical worst-of put approximation
/// Sert de BORNE — rejette les MC results qui divergent trop
contract OptionPricer {

    // Tolerance dynamique selon le regime de vol
    uint256 constant TOLERANCE_HIGH_VOL = 300;  // 3% si vol > 50%
    uint256 constant TOLERANCE_MID_VOL = 200;   // 2% si vol 35-50%
    uint256 constant TOLERANCE_LOW_VOL = 150;   // 1.5% si vol < 35%

    uint256 constant MIN_PREMIUM = 300;   // 3% floor
    uint256 constant MAX_PREMIUM = 1500;  // 15% ceiling
    uint256 constant MAX_KI_PROB = 1500;  // 15% max

    function verifyPricing(
        PricingParams calldata params,
        uint256 mcPremiumBps,
        bytes32 mcHash
    ) external view returns (bool approved, uint256 onChainApprox) {

        uint256 avgVol = _getAvgVol(params.basket);
        uint256 avgCorr = volOracle.getAvgCorrelation(params.basket);
        uint256 T = (params.maturityDays * 1e18) / 365;

        // Worst-of put = BS_put(avgVol, KI, T) * sqrt(n) * (1 - rho/2)
        uint256 singlePut = _bsApproxPut(avgVol, params.kiBarrierBps, T);
        uint256 worstOfMult = _sqrt(params.basket.length * 1e18);
        uint256 corrAdj = 1e18 - (avgCorr * 1e18 / 20000);

        onChainApprox = (singlePut * worstOfMult * corrAdj) / 1e36;
        onChainApprox = (onChainApprox * 365 * BPS) / (params.maturityDays * 1e18);

        // Dynamic tolerance
        uint256 tolerance;
        if (avgVol >= 5000) tolerance = TOLERANCE_HIGH_VOL;
        else if (avgVol >= 3500) tolerance = TOLERANCE_MID_VOL;
        else tolerance = TOLERANCE_LOW_VOL;

        uint256 diff = mcPremiumBps > onChainApprox
            ? mcPremiumBps - onChainApprox
            : onChainApprox - mcPremiumBps;

        approved = diff <= tolerance
            && mcPremiumBps >= MIN_PREMIUM
            && mcPremiumBps <= MAX_PREMIUM;
    }
}
```

### 4.4 Pricing flow complet

```
                    +-----------------------------+
                    |  MARKET DATA                |
                    |  Chainlink Data Streams      |
                    |  spot prices on Ink          |
                    +---------+-------------------+
                              |
              +---------------+---------------+
              |                               |
    +---------v-----------+     +-------------v-----------+
    |  CRE Workflow       |     |  CRE Workflow           |
    |  "xYield-VolOracle" |     |  "xYield-Pricing"       |
    |  cron 1h            |     |  trigger: RequestPricing|
    |  -> fetch vols      |     |  -> call MC API         |
    |  -> consensus DON   |     |  -> consensus DON       |
    |  -> write VolOracle |     |  -> write CREConsumer   |
    +---------+-----------+     +-------------+-----------+
              |                               |
              v                               v
    +---------+-----------+     +-------------+-----------+
    |  VolOracle.sol      |     |  CREConsumer.sol        |
    |  vols + correlations|     |  pricing result         |
    +---------------------+     +-------------+-----------+
                                              |
                                +---------v-------------------+
                                |  ON-CHAIN VERIFICATION       |
                                |  OptionPricer.sol            |
                                |  * BS worst-of approx        |
                                |  * |MC - approx| < tolerance |
                                |  * Dynamic tolerance (vol)   |
                                |  * Bounds: 3% <= prem <= 15% |
                                +---------+-------------------+
                                          |
                                +---------v-------------------+
                                |  PRICING ACCEPTED            |
                                |  premium = 920 bps           |
                                |  -> CouponCalculator         |
                                |  -> IssuanceGate             |
                                |  -> CreateNote               |
                                +-----------------------------+
```

---

## 5. Coupon Formula

```
base_coupon_bps = option_premium_bps - safety_margin_bps

    safety_margin (dynamic, vol-linked) :
      avg_vol >= 50%  -> 200 bps (2%)
      avg_vol 35-50% -> 150 bps (1.5%)
      avg_vol < 35%  -> 100 bps (1%)

carry_enhance_bps = min(
    carry_rate_total * carry_share_rate / BPS,
    MAX_CARRY_ENHANCE
)

    carry_rate_total = funding_rate + lending_rate
    carry_share_rate = 7000 (70%, Phase 1)
    MAX_CARRY_ENHANCE = 500 bps (5%, Phase 1)

total_coupon_bps = base_coupon_bps + carry_enhance_bps
coupon_per_obs = total_coupon_bps * obs_interval_days / 365
coupon_amount = notional * coupon_per_obs / BPS

Tout est FIXE a l'emission. Immuable on-chain.
```

---

## 6. State Machine

```
12 etats, transitions strictes, emergency procedures.

CREATED --> PRICED --> ACTIVE --> OBSERVATION_PENDING
                                        |
                             +----------+----------+
                             v          v          v
                        coupon paid  coupon miss  AUTOCALLED
                             |          |              |
                             +----+-----+              |
                                  v                    |
                             ACTIVE (loop)             |
                                  |                    |
                             last observation          |
                                  v                    |
                          MATURITY_CHECK               |
                             |         |               |
                             v         v               |
                        NO_KI_SETTLE  KI_SETTLE        |
                             |         |               |
                             |    holder chooses       |
                             |    xStocks or USDC      |
                             |         |               |
                             +----+----+               |
                                  v                    v
                              SETTLED <------------- SETTLED
                                  |
                                  v
                             ROLLED (auto-roll ERC-7579)

Emergency : ACTIVE -> EMERGENCY_PAUSED -> ACTIVE (multisig)
Cancel : CREATED/PRICED -> CANCELLED
```

---

## 7. Waterfall — Distribution du cash

```
Chaque epoch (48h), le cash disponible est distribue :

P1 (SENIOR)  : Base coupons dus          <- obligation retail, TOUJOURS paye en premier
P2 (SENIOR)  : Principal repayment       <- couvert par le hedge delta-neutre
P3 (MEZZ)    : Carry enhancement retail  <- pas de memory si impaye
P4 (JUNIOR)  : Hedge operational costs   <- gas, slippage, rebalancing
P5 (JUNIOR)  : Reserve fund contribution <- buffer, Ethena model
P6 (EQUITY)  : Protocol treasury         <- profit net

Si P1 pas couvert -> reserve fund backup.
Si reserve fund vide -> coupon defere (memory base).
JAMAIS de P6 si P1 impaye.
```

---

## 8. Carry Engine — 3 sources

```
Le carry est diversifie sur 3 sources prouvees.

A. FUNDING RATE — Nado stock perps (Ink)                   ~55%
   -> Short perps NVDA/TSLA/META -> collect funding
   -> 5-20% ann (variable, positif >80% du temps)

B. USDC LENDING — Tydro (Aave v3 on Ink)                  ~35%
   -> USDC idle du vault -> Tydro lending pool
   -> 4-6% ann (stable, Aave-proven)

C. xSTOCKS COLLATERAL YIELD — Tydro                       ~10%
   -> xStocks deposes en collateral generent du yield
   -> 1-3% ann (passif, automatique)
   -> Disponible quand Tydro active xStocks comme collateral

Carry total par regime :
  Funding 10% + lending 5%  -> carry ~10% -> enhance 5% -> coupon ~12.5%
  Funding 3%  + lending 5%  -> carry ~6%  -> enhance 3% -> coupon ~10.5%
  Funding 0%  + lending 5%  -> carry ~4%  -> enhance 2% -> coupon ~9.5%
  Funding <0  + lending 5%  -> carry ~3%  -> enhance 1% -> coupon ~8.5%

  Plancher : ~8.5%. Toujours au-dessus du risk-free.
```

---

## 9. Coupon Streaming — Sablier V2

Le coupon n'est pas verse en lump sum mensuel. Il est **streame en continu**.

```solidity
/// @notice Create a Sablier stream for each note's coupon
/// User sees their balance increase every second
contract CouponStreamer {

    ISablierV2LockupLinear public sablier;

    function startCouponStream(
        bytes32 noteId,
        address holder,
        uint256 monthlyAmount,    // coupon amount per observation period
        uint256 startTime,        // observation start
        uint256 endTime           // next observation date
    ) internal returns (uint256 streamId) {

        LockupLinear.CreateWithTimestamps memory params = LockupLinear.CreateWithTimestamps({
            sender: address(this),
            recipient: holder,
            totalAmount: uint128(monthlyAmount),
            asset: USDC,
            cancelable: true,       // can cancel if note settles early
            transferable: false,
            timestamps: LockupLinear.Timestamps({
                start: uint40(startTime),
                cliff: 0,
                end: uint40(endTime)
            }),
            broker: Broker(address(0), ud60x18(0))
        });

        streamId = sablier.createWithTimestamps(params);
        emit CouponStreamStarted(noteId, holder, streamId, monthlyAmount);
    }
}

// UX : le user ouvre l'app -> voit son solde augmenter en temps reel
// $0.004/seconde qui coule dans son wallet
```

---

## 10. Hedge Manager — Delta-Neutre On-Chain

```solidity
contract HedgeManager {

    INadoAdapter public nado;
    ITydroAdapter public tydro;
    IOneInchSwapper public swapper;

    /// @notice Open full delta-neutral hedge for a note
    function openHedge(
        bytes32 noteId,
        address[] calldata basket,  // [NVDAx, METAx, TSLAx]
        uint256 notional            // $10,000
    ) external {
        uint256 perStock = notional / basket.length;  // $3,333 each

        for (uint i = 0; i < basket.length; i++) {
            // 1. Buy xStocks spot via 1inch
            uint256 xStockAmount = swapper.swap(USDC, basket[i], perStock);

            // 2. Deposit xStocks on Tydro as collateral
            tydro.depositCollateral(basket[i], xStockAmount);

            // 3. Short stock perps on Nado (delta hedge)
            nado.openShort(
                _getPairIndex(basket[i]),  // pair indexes TBD (ask Nado team)
                perStock                    // notional
            );
        }

        // 4. Borrow USDC from Euler (margin for perps)
        uint256 borrowed = tydro.borrowUSDC(notional / 2);

        emit HedgeOpened(noteId, notional, notional, borrowed);
    }

    /// @notice Close hedge — called at settlement
    function closeHedge(bytes32 noteId) external returns (uint256 recovered) {
        HedgePosition storage pos = positions[noteId];

        // 1. Close all short perps on Nado
        for (uint i = 0; i < pos.basket.length; i++) {
            nado.closeShort(pos.basket[i]);
        }

        // 2. Repay Tydro borrow
        tydro.repayUSDC(pos.tydroBorrowed);

        // 3. Withdraw xStocks from Tydro
        for (uint i = 0; i < pos.basket.length; i++) {
            uint256 xStockAmount = tydro.withdrawCollateral(pos.basket[i]);
            // 4. Sell xStocks via 1inch -> USDC
            recovered += swapper.swap(pos.basket[i], USDC, xStockAmount);
        }

        emit HedgeClosed(noteId, recovered, int256(recovered) - int256(pos.spotNotional));
    }

    // --- REBALANCING PARAMETERS ---
    uint256 constant DELTA_THRESHOLD_BPS = 500;   // 5% drift -> trigger rebalance
    uint256 constant DELTA_CRITICAL_BPS = 1500;   // 15% drift -> circuit breaker
    uint256 constant MAX_REBALANCE_COST = 50;     // 0.5% du notional max par rebalance
    // Frequence : chaque epoch (48h) via CRE workflow ou permissionless

    /// @notice Rebalance if delta drift > threshold
    /// Called by Chainlink CRE (cron 48h) or anyone (permissionless)
    function rebalance(bytes32 noteId) external {
        int256 deltaDrift = _calculateDeltaDrift(noteId);

        if (_abs(deltaDrift) > DELTA_THRESHOLD_BPS) {
            // Adjust perp positions to restore delta neutrality
            _adjustPerps(noteId, deltaDrift);
            emit HedgeRebalanced(noteId, deltaDrift);
        }

        if (_abs(deltaDrift) > DELTA_CRITICAL_BPS) {
            // Circuit breaker — hedge trop desequilibre
            _emergencyPause(noteId, EmergencyReason.HedgeDriftCritical);
        }
    }

    /// @notice Calculate delta drift between spot and perp legs
    function _calculateDeltaDrift(bytes32 noteId) internal view returns (int256) {
        HedgePosition storage pos = positions[noteId];
        uint256 spotValue = _getSpotValue(pos);        // valeur actuelle des xStocks
        uint256 perpValue = _getPerpNotional(pos);     // notional des positions short
        // drift = (spot - perp) / notional en bps
        return int256((spotValue - perpValue) * BPS / pos.notional);
    }
}

/// @notice Nado adapter interface (a confirmer avec l'equipe Nado)
interface INadoAdapter {
    function openShort(
        uint256 pairIndex,       // index de la paire (NVDA, TSLA, etc.)
        uint256 notional,        // taille de la position en USDC
        uint256 leverage         // levier (1x pour delta-neutre)
    ) external returns (bytes32 positionId);

    function closeShort(
        bytes32 positionId
    ) external returns (uint256 pnl);

    function claimFunding(
        bytes32 positionId
    ) external returns (uint256 fundingAmount);

    function getPosition(
        bytes32 positionId
    ) external view returns (
        int256 unrealizedPnl,
        uint256 margin,
        uint256 size,
        uint256 accumulatedFunding
    );
}
```

---

## 11. KI Settlement — Holder's Choice

```solidity
/// @notice At KI, the holder chooses: xStocks or USDC
function settleKI(bytes32 noteId, bool preferPhysical) external {
    Note storage note = notes[noteId];
    require(note.state == State.KISettle, "not KI");
    require(msg.sender == note.holder, "only holder");

    hedgeManager.closeHedge(noteId);
    (address worstStock, uint256 deliveryQty) = _calculateDelivery(note);
    uint256 worstPerf = _getWorstPerformance(note);

    if (preferPhysical) {
        // Physical delivery — holder gets xStocks, can hold for recovery
        uint256 xStockAmount = swapper.swap(USDC, worstStock, note.notional);
        IERC20(worstStock).transfer(note.holder, xStockAmount);
        emit NoteSettled(noteId, xStockAmount, NoteSettleType.KIPhysical);
    } else {
        // Cash settlement — holder gets USDC at current market value
        uint256 cashValue = (note.notional * worstPerf) / BPS;
        IERC20(USDC).transfer(note.holder, cashValue);
        emit NoteSettled(noteId, cashValue, NoteSettleType.KICash);
    }

    note.state = State.Settled;
}
```

---

## 12. Reserve Fund

```
NIVEAUX :
  TARGET    = 10% du notional outstanding  -> fonctionnement normal
  MINIMUM   = 3%                           -> carry enhancement nouvelles notes = 0
  CRITIQUE  = 1%                           -> haircut carry existant + pause emissions

ALIMENTATION :
  30% du carry net  -> reserve (en temps normal)
  100% du carry     -> reserve (si reserve < minimum)
  KI payoffs surplus -> reserve (quand KI payoffs > coupons payes)
  0.5% embedded fee -> reserve

SORTIES :
  Couvrir deficit P1 (base coupons impayable par le cash courant)
  Couvrir deficit P3 (carry enhancement si funding insuffisant)

HAIRCUT DYNAMIQUE (si reserve < CRITIQUE) :
  Le base coupon est TOUJOURS paye integralement (immutable).
  Le carry enhancement des notes existantes est reduit :
    haircut_ratio = reserve_balance / (1% * total_notional)
    carry_paye = carry_enhance_bps * haircut_ratio
  Exemple : reserve = 0.5%, critique = 1%
    -> haircut_ratio = 0.5 -> carry paye a 50%

Modele Ethena : Ethena a accumule $60M+ de reserve avec cette logique.
```

---

## 13. Economie Phase 1 & Fee Timing

```
FEES (reduits, TVL grab) :
  Embedded       0.5%       (-> 1.5% Phase 3)
  Origination    0.1%       (-> 0.3%)
  Management     0.25% ann  (-> 0.5%)
  Performance    10% carry  (-> 20%)

CARRY SHARE : 70% au retail (-> 30% Phase 3)
MAX CARRY ENHANCE : 500 bps (5%)

Sur $1M TVL / 6 mois :
  Retail :     $60,000 (12% ann)
  Protocole :  $15,000 (3% ann)
  Ratio :      80% retail / 20% protocole

Transitions : Phase 2 a $10M TVL, Phase 3 a $50M TVL.
Parametres ajustables via governance (IssuancePolicy.sol).
```

---

## 14. Invariants — Tests critiques

```
INV-1 : base_coupon + safety_margin <= option_premium
INV-2 : |spot_value + perp_pnl| ~= notional (+-5%)
INV-3 : spot_value + perp_pnl >= notional * 95%
INV-4 : state transitions follow defined table ONLY
INV-5 : P1-P6 waterfall order ALWAYS respected
INV-6 : no note PRICED->ACTIVE without issuanceGate.approved
```

---

## 15. Failure Modes

```
ORACLE STALE         -> grace 24h, fallback permissionless, global pause 72h
KEEPER LATE          -> grace 24h, anyone can call observe(), skip after
NADO DOWN            -> positions stay, new issuance blocked, pause if drift >15%
1INCH FAIL           -> retry 3x (+0.5% slippage), USDC fallback
PARTIAL HEDGE CLOSE  -> progressive 24h, reserve covers gap
TYDRO DOWN           -> positions stay, deferred settlement 48h
CRE DOWN             -> fallback: OptionPricer.sol approx on-chain seule
```

---

## 16. Frontend

```
STACK : Next.js 14 + wagmi + viem + Tailwind

PAGES :
  / (landing)           -> pitch, stats, APY comparison vs GS
  /deposit              -> connect wallet, choose basket, deposit USDC
  /notes                -> active notes, coupon history, streaming counter
  /note/:id             -> detail: observations, worst-of chart, PnL
  /note/:id/settle      -> KI settlement choice (xStocks or USDC)
  /dashboard            -> protocol stats: TVL, notes outstanding, reserve health

COMPOSANTS CLES :
  CouponStreamCounter   -> affiche le coupon qui coule en temps reel (Sablier)
  ObservationTimeline   -> timeline visuelle des 6 observations
  WorstOfChart          -> graphe des 3 stocks vs barriers
  PricingBreakdown      -> base coupon, carry enhance, safety margin, MC hash
  SettlementChoice      -> 2 boutons au KI : [xStocks] [USDC]
```

---

## 17. Access Control & Operations

```
ROLES :
  ADMIN (multisig 3/5)    -> deploy, upgrade, pause, parametre changes
  KEEPER (CRE + anyone)   -> observe(), rebalance(), distributeWaterfall()
                             CRE en primaire, permissionless en fallback
  RETAIL                  -> deposit(), claimDeposit(), settleKI()

UPGRADABILITY :
  Phase 1 : Proxy UUPS (pouvoir patcher)
  Phase 3 : Immutable (apres audit complet)

POSITION LIMITS :
  MAX_NOTE_SIZE    = $100,000
  MAX_TVL          = $5,000,000 (Phase 1)
  MAX_ACTIVE_NOTES = 500
  MIN_NOTE_SIZE    = $100

DEPOSIT FLOW (ERC-7540 async) :
  1. Retail appelle requestDeposit(amount)
  2. Protocole price la note (CRE workflow, ~minutes)
  3. Protocole ouvre le hedge (Nado + Tydro + 1inch)
  4. Retail appelle claimDeposit() -> recoit NoteToken ERC-1155
  Delai max : 24h. Si non claim -> refund automatique.

FEE TIMING :
  Embedded fee (0.5%)   -> preleve au depot (sur le notional)
  Origination (0.1%)    -> preleve au depot
  Management (0.25%)    -> preleve a chaque epoch (48h), pro-rata
  Performance (10%)     -> preleve sur le carry net a chaque epoch
```

---

## 18. References

```
PROTOCOLES :
  Nado          nado.xyz (Ink perp DEX, unified margin)
  Tydro         tydro.xyz (Aave v3 fork on Ink)
  Chainlink DS  docs.chain.link/data-streams
  Chainlink CRE docs.chain.link/cre
  Sablier V2    docs.sablier.com
  1inch API     portal.1inch.dev
  xStocks       docs.xstocks.fi
  Ink           docs.inkonchain.com
```

---

*xYield Protocol — Technical Specification v2.
Chainlink CRE oracle pricing. On-chain verification. Delta-neutral on-chain hedge.
Multi-source carry engine. Coupon streaming. Physical delivery.
Deploye sur Ink (Kraken L2). Premier autocall permissionless sur tokenized equities.*
