export const ProtocolStatsABI = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_engine",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_vault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_reserveFund",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_usdc",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "engine",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IAutocallEngine"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getStats",
    "inputs": [
      {
        "name": "totalNotional",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "stats",
        "type": "tuple",
        "internalType": "struct ProtocolStats.Stats",
        "components": [
          {
            "name": "totalNotesCreated",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "tvl",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "maxDeposit",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "reserveBalance",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "engineUsdcBalance",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "vaultUsdcBalance",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "reserveLevel",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "reserveFund",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IReserveFund"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "usdc",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IERC20"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "vault",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IXYieldVault"
      }
    ],
    "stateMutability": "view"
  }
] as const;
