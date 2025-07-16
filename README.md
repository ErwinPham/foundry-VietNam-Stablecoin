
# 🇻🇳 Vietnam StableCoin (VNDC)

A decentralized overcollateralized stablecoin protocol inspired by MakerDAO's DAI, built on Ethereum-compatible EVM chains. This protocol enables users to mint a stablecoin (VNDC) pegged to the USD using overcollateralized assets such as ETH and WBTC.

---

## 🚀 Features

- 🪙 Mint VNDC (Vietnamese Stablecoin)
- 🔐 Overcollateralized CDP (Collateralized Debt Position)
- 📉 Real-time price feeds using Chainlink Oracles
- 🔄 Invariant testing to ensure system safety
- 🧪 Foundry-based testing suite

---

## 🧱 Core Contracts

| Contract/File              | Description                                      |
|---------------------------|--------------------------------------------------|
| `VietNamStableCoin.sol`   | ERC20-compliant VNDC token contract              |
| `VNDCEngine.sol`          | Core logic for collateral deposit, minting, health factor management |
| `OracleLib.sol`           | Chainlink oracle timeout checks and helpers      |
| `HelperConfig.s.sol`      | Script for dynamic configuration per network     |
| `DeployVNDC.s.sol`        | Script for automated deployment of the protocol |
| `Handler.t.sol`           | Property-based fuzzing test handler              |
| `InvariantTest.t.sol`     | Invariant tests to ensure protocol safety        |
| `VNDCEngineTest.t.sol`    | Unit tests for the engine contract               |

---

## 🛠️ Installation

```bash
git clone https://github.com/your-username/vietnam-stablecoin.git
cd vietnam-stablecoin

# Install dependencies
forge install

# Build the project
forge build
```

---

## 🧪 Running Tests

```bash
# Run all unit tests
forge test

# Run with detailed logs
forge test -vvvv

# Run invariant (property-based) tests
forge test --match-path test/foundry/InvariantTest.t.sol
```

---

## ⚙️ Deployment

Deployment scripts are written using Foundry's scripting system.

```bash
# Example deployment command (Sepolia)
forge script script/DeployVNDC.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

Set your environment variables in a `.env` file or export them manually before running.

---

## 📦 Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`)
- Solidity ^0.8.18
- Chainlink Price Feeds
- EVM-compatible chain (e.g., Sepolia, Base, etc.)

---

## 📄 License

This project is licensed under the MIT License. See `LICENSE` for details.

---

## 🤝 Contribution

Feel free to fork, open issues, and submit PRs to contribute to the development of a decentralized stablecoin ecosystem for Vietnam.

---

## 👨‍💻 Author

Developed by **Huy Phạm**.  
For any collaboration, reach out at: [GitHub](https://github.com/ErwinPham)
