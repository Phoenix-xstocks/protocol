/**
 * Monte Carlo Worst-of Put Pricer for Phoenix Autocall
 *
 * Correlated GBM simulation with Cholesky decomposition.
 * Deterministic RNG (seeded xorshift128) for reproducibility.
 * 10,000 paths, 3 correlated assets, 6 monthly observations.
 */

interface MCInputs {
  spotPrices: number[];
  implVols: number[];
  correlations: number[];
  kiBarrier: number;
  couponBarrier: number;
  autocallTrigger: number;
  stepDown: number;
  maturityDays: number;
  numObservations: number;
  numPaths: number;
  rngSeed: number;
}

interface MCOutput {
  putPremiumBps: number;
  kiProbabilityBps: number;
  expectedKILossBps: number;
  avgAutocallMonth: number;
  vegaBps: number;
}

class DeterministicRNG {
  private state: [number, number, number, number];

  constructor(seed: number) {
    this.state = [
      seed ^ 0x12345678,
      (seed * 1103515245 + 12345) & 0x7fffffff,
      (seed * 214013 + 2531011) & 0x7fffffff,
      (seed * 16807 + 1) & 0x7fffffff,
    ];
    for (let i = 0; i < 20; i++) this.nextUint32();
  }

  nextUint32(): number {
    let t = this.state[3];
    const s = this.state[0];
    this.state[3] = this.state[2];
    this.state[2] = this.state[1];
    this.state[1] = s;
    t ^= t << 11;
    t ^= t >>> 8;
    this.state[0] = t ^ s ^ (s >>> 19);
    return (this.state[0] >>> 0) & 0x7fffffff;
  }

  nextUniform(): number {
    return this.nextUint32() / 0x80000000;
  }

  nextNormal(): number {
    const u1 = Math.max(this.nextUniform(), 1e-10);
    const u2 = this.nextUniform();
    return Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.PI * u2);
  }
}

function choleskyDecompose(corr: number[][]): number[][] {
  const n = corr.length;
  const L: number[][] = Array.from({ length: n }, () => new Array(n).fill(0));
  for (let i = 0; i < n; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = 0;
      for (let k = 0; k < j; k++) sum += L[i][k] * L[j][k];
      if (i === j) {
        L[i][j] = Math.sqrt(Math.max(corr[i][i] - sum, 0));
      } else {
        L[i][j] = L[j][j] !== 0 ? (corr[i][j] - sum) / L[j][j] : 0;
      }
    }
  }
  return L;
}

function buildCorrMatrix(correlations: number[]): number[][] {
  return [
    [1.0, correlations[0], correlations[1]],
    [correlations[0], 1.0, correlations[2]],
    [correlations[1], correlations[2], 1.0],
  ];
}

function runMonteCarloCore(
  inputs: MCInputs,
  L: number[][],
  rng: DeterministicRNG
): { premium: number; kiCount: number; kiLoss: number; autocallMonth: number; autocallCount: number } {
  const { implVols, kiBarrier, couponBarrier, autocallTrigger, stepDown, maturityDays, numObservations, numPaths } =
    inputs;
  const n = implVols.length;
  const dt = maturityDays / 365 / numObservations;
  const riskFreeRate = 0.045;
  let totalPremium = 0;
  let kiCount = 0;
  let totalKILoss = 0;
  let totalAutocallMonth = 0;
  let autocallCount = 0;

  for (let path = 0; path < numPaths; path++) {
    const prices = new Array(n).fill(1.0);
    let autocalled = false;
    let couponsEarned = 0;
    let autocallMonth = 0;

    for (let obs = 0; obs < numObservations; obs++) {
      const z = new Array(n).fill(0);
      const indep = new Array(n).fill(0).map(() => rng.nextNormal());
      for (let i = 0; i < n; i++) {
        for (let j = 0; j <= i; j++) z[i] += L[i][j] * indep[j];
      }
      for (let i = 0; i < n; i++) {
        const sigma = implVols[i];
        prices[i] *= Math.exp(
          (riskFreeRate - 0.5 * sigma * sigma) * dt + sigma * Math.sqrt(dt) * z[i]
        );
      }
      const worstPerf = Math.min(...prices);
      const trigger = autocallTrigger - stepDown * obs;
      if (worstPerf >= trigger) {
        autocalled = true;
        autocallMonth = obs + 1;
        couponsEarned += 1;
        break;
      }
      if (worstPerf >= couponBarrier) couponsEarned += 1;
    }

    if (autocalled) {
      totalPremium += couponsEarned / numObservations;
      totalAutocallMonth += autocallMonth;
      autocallCount++;
    } else {
      const worstFinal = Math.min(...prices);
      if (worstFinal < kiBarrier) {
        const loss = 1.0 - worstFinal;
        totalKILoss += loss;
        kiCount++;
        totalPremium += loss;
      } else {
        totalPremium += couponsEarned / numObservations;
      }
    }
  }

  return { premium: totalPremium, kiCount, kiLoss: totalKILoss, autocallMonth: totalAutocallMonth, autocallCount };
}

function runMonteCarlo(inputs: MCInputs): MCOutput {
  const corrMatrix = buildCorrMatrix(inputs.correlations);
  const L = choleskyDecompose(corrMatrix);
  const rng = new DeterministicRNG(inputs.rngSeed);

  const result = runMonteCarloCore(inputs, L, rng);

  const annFactor = 365 / inputs.maturityDays;
  const avgPremium = (result.premium / inputs.numPaths) * annFactor;
  const kiProb = result.kiCount / inputs.numPaths;
  const avgKILoss = result.kiCount > 0 ? result.kiLoss / result.kiCount : 0;
  const avgAutocall = result.autocallCount > 0 ? result.autocallMonth / result.autocallCount : 0;

  // Vega: re-run with +1% vol bump
  const bumpedVols = inputs.implVols.map((v) => v + 0.01);
  const bumpedInputs = { ...inputs, implVols: bumpedVols, numPaths: Math.min(inputs.numPaths, 2000) };
  const bumpedRng = new DeterministicRNG(inputs.rngSeed + 1);
  const bumpedResult = runMonteCarloCore(bumpedInputs, L, bumpedRng);
  const bumpedPremium = (bumpedResult.premium / bumpedInputs.numPaths) * annFactor;
  const vega = Math.abs(bumpedPremium - avgPremium) * 10000;

  return {
    putPremiumBps: Math.round(avgPremium * 10000),
    kiProbabilityBps: Math.round(kiProb * 10000),
    expectedKILossBps: Math.round(avgKILoss * 10000),
    avgAutocallMonth: Math.round(avgAutocall * 10),
    vegaBps: Math.round(vega),
  };
}

function main() {
  const inputs: MCInputs = {
    spotPrices: [1.0, 1.0, 1.0],
    implVols: [0.55, 0.6, 0.4],
    correlations: [0.55, 0.48, 0.52],
    kiBarrier: 0.5,
    couponBarrier: 0.7,
    autocallTrigger: 1.0,
    stepDown: 0.02,
    maturityDays: 180,
    numObservations: 6,
    numPaths: 10000,
    rngSeed: 42,
  };

  console.log("Phoenix Autocall MC Pricer");
  console.log("=========================");
  console.log(`Assets: 3 (NVDA, TSLA, META)`);
  console.log(`Vols: ${inputs.implVols.map((v) => (v * 100).toFixed(0) + "%").join(", ")}`);
  console.log(`Correlations: ${inputs.correlations.map((c) => c.toFixed(2)).join(", ")}`);
  console.log(`KI: ${(inputs.kiBarrier * 100).toFixed(0)}%, Autocall: ${(inputs.autocallTrigger * 100).toFixed(0)}%`);
  console.log(`Maturity: ${inputs.maturityDays}d, ${inputs.numObservations} obs, ${inputs.numPaths} paths`);
  console.log("");

  const start = Date.now();
  const result = runMonteCarlo(inputs);
  const elapsed = Date.now() - start;

  console.log("Results:");
  console.log(`  Put Premium:       ${result.putPremiumBps} bps (${(result.putPremiumBps / 100).toFixed(2)}% ann)`);
  console.log(`  KI Probability:    ${result.kiProbabilityBps} bps (${(result.kiProbabilityBps / 100).toFixed(2)}%)`);
  console.log(`  Expected KI Loss:  ${result.expectedKILossBps} bps (${(result.expectedKILossBps / 100).toFixed(2)}%)`);
  console.log(`  Avg Autocall Month: ${(result.avgAutocallMonth / 10).toFixed(1)}`);
  console.log(`  Vega:              ${result.vegaBps} bps`);
  console.log(`  Elapsed:           ${elapsed}ms`);

  const inBounds = result.putPremiumBps >= 300 && result.putPremiumBps <= 1500;
  console.log(`\n[${inBounds ? "PASS" : "WARN"}] Premium ${inBounds ? "within" : "outside"} bounds [300, 1500] bps`);
  console.log("\nJSON output for CRE:");
  console.log(JSON.stringify(result, null, 2));
}

main();
