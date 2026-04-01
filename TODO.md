# xYield Protocol — Ce qu'il reste à faire

## Protocoles externes (besoin d'adresses testnet)

### Nado (Perp DEX)
- [ ] Obtenir les adresses contrats testnet Ink Sepolia
- [ ] Configurer les pair indexes (NVDA, TSLA, META)
- [ ] Tester openShort / closeShort / claimFunding en live
- [ ] **Modéliser les coûts de sortie** : spread taker/maker, slippage sur le carnet
- [ ] Simuler les sorties de positions (unwinding) selon la taille
- **Status** : Adapter (`NadoAdapter.sol`) prêt et testé avec mocks

### Tydro (Lending, Aave v3 fork)
- [ ] Obtenir les adresses contrats testnet Ink Sepolia (Pool, aTokens)
- [ ] Tester depositCollateral / borrowUSDC / repayUSDC en live
- [ ] Vérifier getLendingRate retourne des valeurs correctes
- **Status** : Adapter (`TydroAdapter.sol`) prêt et testé avec mocks

### Chainlink Data Streams
- [ ] Obtenir les feed IDs pour NVDAx, TSLAx, METAx sur Ink
- [ ] Configurer `engine.setFeedId()` pour chaque xStock
- [ ] Tester `verifyAndCachePrice` avec un vrai signed report
- **Status** : Adapter (`ChainlinkPriceFeed.sol`) prêt

### Chainlink CRE
- [ ] Déployer le CRE workflow "xYield-Pricing" sur le DON
- [ ] Déployer le CRE workflow "xYield-VolOracle"
- [ ] Configurer le MC Pricer en HTTP mode (`npm run serve`)
- [ ] Tester le flow complet : RequestPricing → CRE → fulfillPricing
- [ ] **Alternative testnet** : ajouter un mode keeper direct qui bypass CRE
- **Status** : Consumer (`CREConsumer.sol`) prêt, MC Pricer HTTP prêt

### Euler V2
- [ ] Déployer un Euler vault USDC sur Ink (permissionless EVK)
- [ ] Configurer `reserveFund.setEulerVault()`
- [ ] Tester deposit/withdraw/yield en live
- **Status** : Intégré dans `ReserveFund.sol`, testé avec mocks

### 1inch
- [ ] Vérifier le router address sur Ink Sepolia
- [ ] Tester les swaps USDC ↔ xStocks
- **Status** : Adapter (`OneInchSwapper.sol`) prêt

---

## Code à compléter

### Mode testnet (bypass CRE)
- [ ] Ajouter `priceNoteDirect()` sur AutocallEngine : le keeper peut passer le pricing directement sans CRE, pour tester sans attendre le DON
- [ ] Garder le flow CRE pour la prod

### Coûts de hedge (question du juge Nado)
- [ ] Modéliser le coût total du hedge : gas + slippage + spread taker/maker Nado
- [ ] Simuler les sorties : pour un notional de $10k, quel est le slippage sur close ?
- [ ] Intégrer le coût dans P4 (hedge operational costs) du waterfall
- [ ] Documenter : coût estimé en bps par open/close/rebalance

### P2/P4 waterfall transfers
- [ ] P2 (principal) et P4 (hedge costs) sont comptabilisés mais jamais transférés
- [ ] Ajouter les safeTransfer vers les bons recipients

### Frontend
- [ ] Next.js 14 + wagmi + viem + Tailwind
- [ ] Pages : landing, deposit, notes, dashboard
- [ ] CouponStreamCounter (temps réel)
- [ ] ObservationTimeline (6 observations visuelles)
- [ ] WorstOfChart (3 stocks vs barriers)

---

## Questions du juge Nado à préparer

1. **"Tu as simulé tes sorties ?"**
   → On doit chiffrer : pour un notional de $10k sur 3 stocks, combien coûte le close en slippage sur Nado ?

2. **"Taker / vs maker"**
   → Notre hedge utilise des market orders (taker) pour ouvrir/fermer rapidement. Coût estimé : 5-10 bps par trade. Sur un open+close : ~20 bps total.

3. **"Ton coût à toi"**
   → Coût total du protocole par note :
   - Fees : 0.6% (embedded + origination)
   - Hedge open/close slippage : ~0.2%
   - Gas (6 observations + settlement) : ~0.05%
   - **Total : ~0.85% par note de 6 mois**

4. **"Délai epoch / piggy bank"**
   → Notre EpochManager a des cycles de 48h. Le withdraw de la reserve est permissionless et instantané. Pas de lock-up.
