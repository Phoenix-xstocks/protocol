# xYield Protocol — Ce qu'il reste à faire

## FAIT ✅

- [x] Pyth price feeds configurés (NVDA, TSLA, META feed IDs on-chain)
- [x] PythAdapter déployé sur Ink Sepolia
- [x] priceNoteDirect() — mode testnet sans CRE
- [x] Full flow on-chain : deposit → create → claim → price ✅
- [x] 30 xStock tokens déployés
- [x] 339 tests (100% pass)
- [x] VolOracle configuré (vols + correlations)
- [x] Fee collection intégrée (0.6% au deposit)
- [x] Euler V2 intégré pour reserve fund yield
- [x] P2/P4 waterfall transfers fixés

## Protocoles externes

### Nado (Perp DEX) — ❌ NON INTÉGRABLE
- Nado est un orderbook DEX, pas d'adresses de smart contracts publiques
- On ne l'intègre PAS pour le hackathon
- Le HedgeManager est prêt mais pas connecté
- **Impact** : pas de hedge delta-neutre live. Le flow s'arrête à "Priced".

### Tydro (Lending)
- **Mainnet** : Pool `0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA` (vérifié live)
- **Testnet xStocks** : `feat-ink-sepolia-xstocks-tydro-app` (pas encore déployé)
- Assets mainnet : WETH, USDT0, USDe, kBTC, INK, etc.
- **Status** : Adapter prêt, adresses mainnet connues, fork testing possible

### Euler V2
- Pas sur Ink directement (Base + BOB)
- Intégré dans ReserveFund via ERC-4626 interface
- Peut déployer un vault permissionless quand EVK arrive sur Ink

## Ce qui reste

### Code
- [ ] Frontend (Next.js + wagmi + viem)
- [ ] Fork test avec Tydro mainnet
- [ ] Script simulation coûts hedge

### Contacts
- [ ] Tydro team : demander les adresses du testnet xStocks
- [ ] Euler team : demander si EVK deployable sur Ink
- [ ] 1inch : vérifier router sur Ink

## Adresses déployées (Ink Sepolia)

| Contrat | Adresse |
|---------|---------|
| AutocallEngine | `0xF2f32c1789b2318776023eA50C699A9E9e51AD51` |
| XYieldVault | `0xE8f918b1E6046E9714Cb9052b292bDF6E81CfB1e` |
| NoteToken | `0xDF4610F0732adaC6613F82EeAD44eeC35229421f` |
| PythAdapter | `0x4C8763c2281aF3b181CD5eF2B3ebb1ebbE0663aB` |
| CouponCalculator | `0x8D34506E70446d5ee1a8F8926d8B7209D4af9105` |

## Pyth Feed IDs

| Asset | Feed ID |
|-------|---------|
| NVDAx | `0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593` |
| TSLAx | `0x16dad506d7db8da01c87581c87ca897a012a153557d4d578c3b9c9e1bc0632f1` |
| METAx | `0x78a3e3b8e676a8f73c439f5d749737034b139bbbe899ba5775216fba596607fe` |

## Tydro Mainnet Addresses (Ink)

| Contrat | Adresse |
|---------|---------|
| Pool | `0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA` |
| PoolAddressesProvider | `0x4172E6aAEC070ACB31aaCE343A58c93E4C70f44D` |
| TydroOracle | `0x4758213271BFdC72224A7a8742dC865fC97756e1` |
| DataProvider | `0x96086C25d13943C80Ff9a19791a40Df6aFC08328` |
