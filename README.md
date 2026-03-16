<p align="center">
  <img src="https://probechain.org/logo-probe-fire.png" alt="Probe Builders" width="120" />
</p>

<h1 align="center">Probe Builders</h1>

<p align="center">
  <strong>The World's First On-Chain Agent Dapp Store</strong>
</p>

<p align="center">
  210 Agent Dapps · 11 Categories · 61K+ Lines of Solidity · Built on ProbeChain
</p>

<p align="center">
  <a href="https://probe.builders">Portal</a> · <a href="https://proscan.pro/rydberg">Explorer</a> · <a href="https://proscan.pro/rydberg/faucet">Faucet</a> · <a href="https://probechain.org">ProbeChain</a> · <a href="https://x.com/AioaiN">X</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Agent_Dapps-210-E8873A?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0id2hpdGUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iMTIiIGN5PSIxMiIgcj0iMTAiIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMiIvPjxjaXJjbGUgY3g9IjEyIiBjeT0iMTIiIHI9IjQiLz48L3N2Zz4=" alt="Agent Dapps" />
  <img src="https://img.shields.io/badge/Solidity-0.8.24-363636?style=for-the-badge&logo=solidity" alt="Solidity" />
  <img src="https://img.shields.io/badge/Chain_ID-8004-3B82F6?style=for-the-badge" alt="Chain ID" />
  <img src="https://img.shields.io/badge/EVM-London-10B981?style=for-the-badge" alt="EVM" />
  <img src="https://img.shields.io/badge/license-MIT-8B5CF6?style=for-the-badge" alt="License" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/categories-11-F59E0B?style=flat-square" alt="Categories" />
  <img src="https://img.shields.io/badge/block_time-~1s-10B981?style=flat-square" alt="Block Time" />
  <img src="https://img.shields.io/badge/consensus-PoB_V3.0-E8873A?style=flat-square" alt="Consensus" />
  <img src="https://img.shields.io/badge/testnet-Rydberg-3B82F6?style=flat-square" alt="Testnet" />
</p>

---

Every Agent Dapp in this repository is a **real, compilable, deployable** smart contract targeting the [ProbeChain Rydberg Testnet](https://proscan.pro/rydberg). On-chain Agent Nodes autonomously develop, iterate, and deploy these Dapps — making this the first ecosystem where AI agents build the application layer.

## Quick Start

```bash
git clone https://github.com/ProbeChain/ProbeBuilders.git
cd ProbeBuilders/ProbeSwap          # pick any Dapp
npm install
npx hardhat compile
npx hardhat test
npx hardhat run scripts/deploy.ts --network rydberg
```

> **Get test PROBE:** [proscan.pro/rydberg/faucet](https://proscan.pro/rydberg/faucet)

## Network

| Parameter | Value |
|-----------|-------|
| **Network** | ProbeChain Rydberg Testnet |
| **Chain ID** | `8004` (0x1F44) |
| **Token** | PROBE (18 decimals) |
| **RPC** | `https://proscan.pro/chain/rydberg-rpc` |
| **Explorer** | [proscan.pro/rydberg](https://proscan.pro/rydberg) |
| **Block Time** | ~1 second |
| **Consensus** | Proof-of-Behavior (PoB) V3.0.0 |
| **EVM** | London-compatible |

---

## Agent Dapps by Category

### 🤖 Agent Economy & Intent Networks

Autonomous agent collaboration, registries, coordination, and intent-driven protocols.

| Dapp | Contract | Description |
|------|----------|-------------|
| [AgentForge](./AgentForge) | `AgentRegistry.sol` | Agent development framework — register, manage, and discover on-chain agents |
| [AgentHub](./AgentHub) | `SkillMarketplace.sol` | Agent skill marketplace — list, purchase, and rate agent capabilities |
| [AgentAuth](./AgentAuth) | `AgentIdentity.sol` | Soulbound agent identity and DID with credential management |
| [AgentWallet](./AgentWallet) | `AgentWallet.sol` | Budget-controlled wallet for AI agents with daily spending limits |
| [AgentMesh](./AgentMesh) | `AgentMessaging.sol` | Agent-to-agent encrypted messaging and channel communication |
| [AgentSandbox](./AgentSandbox) | `SandboxEnvironment.sol` | Safe testing environment for agent behaviors before mainnet |
| [AgentSocial](./AgentSocial) | `CompanionRegistry.sol` | AI companion registry with paid interactions and ratings |
| [ProbeSwarm](./ProbeSwarm) | `SwarmCoordinator.sol` | Multi-agent swarm coordination for complex task execution |
| [IntentForge](./IntentForge) | `IntentEngine.sol` | Intent compilation — express goals, agents find optimal execution |
| [IntentPool](./IntentPool) | `IntentAggregator.sol` | Intent aggregation and batch execution for gas savings |
| [CogitoNet](./CogitoNet) | `KnowledgeGraph.sol` | Decentralized knowledge graph built by agent contributions |
| [ModelChain](./ModelChain) | `ModelVersioning.sol` | On-chain AI model version registry with changelog tracking |

### ⚡ Compute DePIN

Distributed GPU/CPU sharing, decentralized inference, training, and edge compute.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeGPU](./ProbeGPU) | `GPUMarketplace.sol` | GPU rental marketplace — list, rent, and rate compute resources |
| [TensorPool](./TensorPool) | `TrainingPool.sol` | Decentralized ML training cluster with reward distribution |
| [InferNet](./InferNet) | `InferenceNetwork.sol` | Edge inference network with proof-based result verification |
| [ComputeX](./ComputeX) | `ComputeExchange.sol` | CPU/GPU compute spot market with session management |
| [NeuroScale](./NeuroScale) | `AutoScaler.sol` | Auto-scaling inference endpoints with pay-per-request |
| [HashForge](./HashForge) | `ComputeProof.sol` | Optimistic compute verification with challenge mechanism |
| [ProbeCloud](./ProbeCloud) | `CloudPlatform.sol` | Decentralized container deployment and scaling |
| [ModelHost](./ModelHost) | `ModelServing.sol` | Staked model hosting with pay-per-call and disputes |
| [WasmNode](./WasmNode) | `WasmExecutor.sol` | WebAssembly compute execution with capability registry |
| [BatchFlow](./BatchFlow) | `BatchScheduler.sol` | Batch job orchestration with priority and deadlines |

### 📡 Physical DePIN

IoT, distributed bandwidth, energy sharing, and real-world sensor networks.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeIoT](./ProbeIoT) | `IoTRegistry.sol` | IoT device registry — sensors, actuators, gateways |
| [SensorChain](./SensorChain) | `SensorMarket.sol` | Sensor data marketplace with subscription access |
| [BandwidthX](./BandwidthX) | `BandwidthExchange.sol` | P2P bandwidth sharing and settlement |
| [EnergyMesh](./EnergyMesh) | `EnergyMarket.sol` | Renewable energy peer-to-peer trading |
| [SignalNet](./SignalNet) | `CoverageProtocol.sol` | Wireless coverage incentive protocol (WiFi/5G/LoRa) |
| [GreenNode](./GreenNode) | `GreenEnergy.sol` | Green energy verification and credit minting |
| [FleetNet](./FleetNet) | `FleetManager.sol` | Vehicle telemetry network with configurable alerts |
| [AirProbe](./AirProbe) | `AirQualityDAO.sol` | Air quality monitoring DAO with sensor governance |
| [MineVision](./MineVision) | `MineMonitor.sol` | Gold mine production monitoring with auditor verification |
| [EdgeVault](./EdgeVault) | `EdgeStorage.sol` | Edge storage network with pay-per-use model |

### 🔐 Data Layer & Privacy Computing

Data marketplaces, zkML, FHE, provenance, and privacy-preserving analytics.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeData](./ProbeData) | `DataMarketplace.sol` | High-quality AI training data marketplace |
| [ZKInfer](./ZKInfer) | `ZKVerifier.sol` | Zero-knowledge proof verification registry |
| [FHEVault](./FHEVault) | `ComputeEscrow.sol` | Encrypted computation escrow with dispute resolution |
| [DataDAO](./DataDAO) | `DataGovernance.sol` | Community data governance with curator rewards |
| [PrivaNet](./PrivaNet) | `PrivateQuery.sol` | Privacy-preserving query marketplace |
| [TruthLayer](./TruthLayer) | `ProvenanceTracker.sol` | Data provenance tracking with auditor certification |
| [SecretQuery](./SecretQuery) | `EncryptedQueryEngine.sol` | Encrypted database query engine |
| [DataForge](./DataForge) | `SyntheticDataMarket.sol` | Synthetic data generation marketplace |
| [AnnotateDAO](./AnnotateDAO) | `LabelingPool.sol` | Decentralized data labeling with consensus validation |
| [ProbeLens](./ProbeLens) | `DashboardRegistry.sol` | Analytics dashboard marketplace |
| [ChainLens](./ChainLens) | `AnalyticsRegistry.sol` | On-chain analytics query marketplace |
| [ProbeGraph](./ProbeGraph) | `GraphAnalytics.sol` | Relationship and cluster analytics engine |

### 🎨 ModelFi & Creator Economy

AI model tokenization, AIGC on-chain IP, creator revenue, and content platforms.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ModelMint](./ModelMint) | `ModelNFT.sol` | Tokenize AI models as ERC-721 with royalty enforcement |
| [ProbeStudio](./ProbeStudio) | `CreatorStudio.sol` | Collaborative creator workspace with revenue splitting |
| [IPChain](./IPChain) | `IPRegistry.sol` | On-chain IP registration (Patent/Trademark/Copyright) |
| [VoiceForge](./VoiceForge) | `VoiceMarket.sol` | AI voice model marketplace with consent verification |
| [LoRASwap](./LoRASwap) | `ModelExchange.sol` | Fine-tuned model weights trading exchange |
| [ProbeMusic](./ProbeMusic) | `MusicRights.sol` | Music streaming with per-play micro-payments |
| [PixelMint](./PixelMint) | `ImageMintFactory.sol` | AI image generation and NFT minting |
| [ModelAudit](./ModelAudit) | `ModelBenchmark.sol` | AI model performance benchmarking with auditor staking |
| [ThreeDForge](./ThreeDForge) | `ThreeDMarket.sol` | 3D model NFT marketplace (glTF/FBX/OBJ) |
| [GenArtX](./GenArtX) | `GenerativeArt.sol` | On-chain generative art with seed-based creation |
| [ProbeLicense](./ProbeLicense) | `LicenseManager.sol` | Software license management (Perpetual/Subscription/Trial) |
| [ContentMint](./ContentMint) | `ContentNFT.sol` | Content creation with limited edition NFT minting |
| [ProbeArt](./ProbeArt) | `ArtGallery.sol` | AI-curated NFT art gallery with consensus scoring |
| [RoyaltyAgent](./RoyaltyAgent) | `RoyaltyEnforcer.sol` | NFT royalty enforcement across secondary sales |
| [FragmentNFT](./FragmentNFT) | `NFTFragments.sol` | NFT fractionalization with buyout mechanism |

### 💰 Agentic DeFi

AI-powered trading, lending, yield aggregation, insurance, and financial infrastructure.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeSwap](./ProbeSwap) | `SimpleSwapRouter.sol` | Constant-product AMM with multi-hop swaps |
| [ProbeSwapV2](./ProbeSwapV2) | `ConcentratedAMM.sol` | Concentrated liquidity AMM with tick-based pricing |
| [ProbeSwapRouter](./ProbeSwapRouter) | `AggregatorRouter.sol` | DEX aggregator with multi-pool order splitting |
| [ProbeYield](./ProbeYield) | `YieldVault.sol` | ERC-4626 yield vault with pluggable strategies |
| [ProbeLend](./ProbeLend) | `LendingPool.sol` | Lending protocol with 150% collateral ratio |
| [VaultGuard](./VaultGuard) | `GuardedVault.sol` | Multi-sig + AI vault with emergency freeze |
| [ArbScout](./ArbScout) | `ArbExecutor.sol` | Arbitrage execution with profit tracking |
| [InsureProbe](./InsureProbe) | `InsurancePool.sol` | DeFi insurance with oracle-based claim resolution |
| [ProbePay](./ProbePay) | `PaymentGateway.sol` | Merchant payment gateway with multi-token support |
| [ProbePayGateway](./ProbePayGateway) | `InvoiceSystem.sol` | Invoice-based payment system with auto-release |
| [ProbeStake](./ProbeStake) | `StakeOptimizer.sol` | Multi-validator staking with auto-compound |
| [ProbeStaking](./ProbeStaking) | `SimpleStaking.sol` | Simple fixed-APR staking contract |
| [FlashLoanGuardian](./FlashLoanGuardian) | `FlashGuard.sol` | Flash loan attack detection and prevention |
| [DCAAgent](./DCAAgent) | `DCAVault.sol` | Dollar-cost averaging with keeper execution |
| [LiquidBot](./LiquidBot) | `LiquidationEngine.sol` | Liquidation bot with keeper incentives |
| [StakeRouter](./StakeRouter) | `StakeRouter.sol` | Multi-validator delegation router |
| [YieldFarm](./YieldFarm) | `FarmManager.sol` | LP farming with per-second reward accrual |
| [ProbeOTC](./ProbeOTC) | `OTCDesk.sol` | OTC desk with escrow and partial fills |
| [PortfolioAI](./PortfolioAI) | `PortfolioVault.sol` | AI portfolio management with rebalancing |
| [ProbeGold](./ProbeGold) | `GoldToken.sol` | Gold-backed ERC-20 token with reserve tracking |
| [ProbeInsure](./ProbeInsure) | `ParametricInsurance.sol` | Parametric insurance with oracle triggers |
| [StreamPay](./StreamPay) | `PaymentStream.sol` | Per-second payment streaming |
| [PredictionMarket](./PredictionMarket) | `PredictionMarket.sol` | Prediction markets with oracle resolution |
| [ProbeAuction](./ProbeAuction) | `AuctionHouse.sol` | English auction house for NFTs |
| [ProbeRaffle](./ProbeRaffle) | `RaffleSystem.sol` | On-chain raffle with blockhash randomness |
| [MEVShield](./MEVShield) | `PrivateMempool.sol` | MEV protection via commit-reveal |
| [MEVWatch](./MEVWatch) | `MEVRegistry.sol` | MEV activity monitoring and reporting |
| [RiskRadar](./RiskRadar) | `RiskMonitor.sol` | DeFi position health monitoring |
| [TaxBot](./TaxBot) | `TaxLedger.sol` | DeFi tax tracking with immutable audit trail |

### 🎮 FOCG & Autonomous Worlds

Fully on-chain games, AI NPCs, procedural worlds, and esports platforms.

| Dapp | Contract | Description |
|------|----------|-------------|
| [BattleAgent](./BattleAgent) | `BattleArena.sol` | AI agent PvP arena with ELO ranking |
| [LootForge](./LootForge) | `LootForge.sol` | Procedural item generation (ERC-721) with rarity tiers |
| [ChessAgent](./ChessAgent) | `ChessGame.sol` | On-chain chess with wager and ELO system |
| [ProbeChess2](./ProbeChess2) | `ChessTournament.sol` | Swiss-system chess tournaments with prizes |
| [ProbeQuest](./ProbeQuest) | `RPGQuest.sol` | On-chain RPG with character classes and XP |
| [PetChain](./PetChain) | `DigitalPet.sol` | Digital pets with feeding, training, and evolution |
| [CardForge](./CardForge) | `CardGame.sol` | Trading card game with pack minting and battles |
| [ProbeRace](./ProbeRace) | `RaceTrack.sol` | On-chain racing with season leaderboards |
| [ProbeWorld](./ProbeWorld) | `LandRegistry.sol` | Virtual land registry (ERC-721) with building system |
| [ProbeEsports](./ProbeEsports) | `TournamentManager.sol` | Esports tournament platform with prize pools |
| [StoryWeaver](./StoryWeaver) | `StoryEngine.sol` | Community-voted interactive branching fiction |
| [NPCStudio](./NPCStudio) | `NPCRegistry.sol` | NPC behavior marketplace for game developers |
| [ArenaAI](./ArenaAI) | `AIArena.sol` | AI agent tournament with ELO and wagers |
| [DungeonAI](./DungeonAI) | `DungeonCrawler.sol` | Dungeon crawler with pseudo-random encounters |
| [LootAgent](./LootAgent) | `LootDistributor.sol` | Contribution-weighted loot distribution |
| [LandAgent](./LandAgent) | `LandValuation.sol` | Virtual land appraisal and marketplace |
| [SkinMarket](./SkinMarket) | `ItemMarket.sol` | Cross-game item marketplace (ERC-721/1155) |
| [QuestGuild](./QuestGuild) | `QuestAggregator.sol` | Cross-game quest aggregation |

### 👤 DeID & SocialFi

Decentralized identity, reputation, social platforms, and community governance.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeID](./ProbeID) | `UniversalID.sol` | Universal identity for humans, agents, and orgs |
| [ProofOfHuman](./ProofOfHuman) | `HumanVerifier.sol` | Sybil resistance with challenge-response verification |
| [SoulBound](./SoulBound) | `SoulboundToken.sol` | Non-transferable achievement/credential tokens |
| [ProbeProfile](./ProbeProfile) | `ProfileRegistry.sol` | On-chain identity profiles with username uniqueness |
| [CredStack](./CredStack) | `CredentialStack.sol` | Verifiable credentials with delegation chains |
| [ReputationGraph](./ReputationGraph) | `ReputationSystem.sol` | Multi-dimension reputation with weighted scoring |
| [ProbeDAO](./ProbeDAO) | `GovernorAgent.sol` | DAO governance with proposal lifecycle |
| [DAOVoice](./DAOVoice) | `WeightedGovernor.sol` | Weighted governance with reputation multiplier |
| [SynapseDAO](./SynapseDAO) | `NeuralGovernance.sol` | Conviction voting — longer lock = more weight |
| [ProbeVote](./ProbeVote) | `CommitRevealVote.sol` | Anti-frontrunning commit-reveal voting |
| [ProbeSpace](./ProbeSpace) | `ForumContract.sol` | Decentralized forum with karma and moderation |
| [ProbeChat](./ProbeChat) | `MessageEscrow.sol` | Pay-to-read encrypted messaging |
| [ProbeChat2](./ProbeChat2) | `GroupChat.sol` | Group messaging with admin controls |
| [ProbePress](./ProbePress) | `PublishingPlatform.sol` | Decentralized publishing with subscriptions |
| [BountyBoard](./BountyBoard) | `BountyBoard.sol` | Bounty platform with escrow and disputes |
| [TipBot](./TipBot) | `TipJar.sol` | Social tipping with leaderboard |
| [FanToken](./FanToken) | `FanTokenFactory.sol` | Creator fan tokens with bonding curve |
| [GuildAgent](./GuildAgent) | `GuildManager.sol` | On-chain guild management with treasury |
| [MeetupAgent](./MeetupAgent) | `EventManager.sol` | Event management with ticket sales and check-in |
| [MeetAgent](./MeetAgent) | `NetworkingProtocol.sol` | Skill-based professional networking |
| [TranslateAgent](./TranslateAgent) | `TranslationBounty.sol` | Translation bounty with quality voting |

### 🏢 RWA & Enterprise

Real-world asset tokenization, supply chain, compliance, and enterprise services.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ProbeAsset](./ProbeAsset) | `RWAToken.sol` | RWA tokenization with KYC-gated transfers |
| [ProbeKYC](./ProbeKYC) | `KYCRegistry.sol` | Privacy-preserving KYC verification (Basic/Standard/Enhanced) |
| [SupplyAgent](./SupplyAgent) | `SupplyChain.sol` | Supply chain tracking with checkpoint provenance |
| [CarbonProbe](./CarbonProbe) | `CarbonCredit.sol` | Carbon credit trading with project-level provenance |
| [ProbeNotary](./ProbeNotary) | `NotaryService.sol` | Document notarization with timestamp proofs |
| [ProbeCertify](./ProbeCertify) | `CertificateRegistry.sol` | Soulbound digital certificates |
| [PropertyProbe](./PropertyProbe) | `PropertyRegistry.sol` | Real estate title registry with lien management |
| [PayrollAgent](./PayrollAgent) | `PayrollManager.sol` | Crypto payroll with batch multi-token payments |
| [TrustFund](./TrustFund) | `TrustVault.sol` | Conditional trust fund with time-lock release |
| [ProbeHR](./ProbeHR) | `HiringPlatform.sol` | Decentralized hiring with escrow-based payments |
| [InvoiceProbe](./InvoiceProbe) | `InvoiceFactoring.sol` | Invoice factoring with credit risk assessment |
| [ProbeInsight](./ProbeInsight) | `InsightRegistry.sol` | Enterprise analytics report marketplace |

### 🔧 Developer Tools

SDKs, CLIs, contract wizards, CI/CD, testing, and deployment infrastructure.

| Dapp | Contract | Description |
|------|----------|-------------|
| [ContractWizard](./ContractWizard) | `TemplateRegistry.sol` | Contract template factory with one-click deploy |
| [ProbeSDK](./ProbeSDK) | `SDKRegistry.sol` | Multi-language SDK registry (TS/Py/Rust/Go) |
| [ProbeCLI](./ProbeCLI) | `ToolRegistry.sol` | CLI tool registry with download verification |
| [ProbePlayground](./ProbePlayground) | `PlaygroundRegistry.sol` | On-chain code snippet sharing and forking |
| [ProbeCI](./ProbeCI) | `CIRegistry.sol` | CI/CD build result registry with artifact hashes |
| [ProbeTemplate](./ProbeTemplate) | `TemplateStore.sol` | Dapp template marketplace (DeFi/NFT/DAO/GameFi) |
| [ABIDecoder](./ABIDecoder) | `ABIRegistry.sol` | On-chain ABI registry and verification |
| [DocAgent](./DocAgent) | `DocBounty.sol` | Documentation bounty platform |
| [MigrateAgent](./MigrateAgent) | `MigrationTracker.sol` | Cross-chain migration tracking |
| [BugBountyAgent](./BugBountyAgent) | `BugBountyPlatform.sol` | Bug bounty with severity-based payouts |
| [FaucetPlus](./FaucetPlus) | `SmartFaucet.sol` | Anti-sybil faucet with tiered claims |
| [ProbeMonitor](./ProbeMonitor) | `NodeMonitor.sol` | Node performance monitoring and scoring |

### 🎓 Education & Growth

Learn-to-earn, bootcamps, quizzes, hackathons, and ecosystem growth tools.

| Dapp | Contract | Description |
|------|----------|-------------|
| [QuestBoard](./QuestBoard) | `QuestSystem.sol` | Learn-to-earn quest system with badge NFTs |
| [ProbeCamp](./ProbeCamp) | `BootcampTracker.sol` | Interactive bootcamp with module completion tracking |
| [ProbeAcademy](./ProbeAcademy) | `CourseMarket.sol` | Course marketplace with paid enrollment |
| [SimTrader](./SimTrader) | `PaperTrading.sol` | Zero-risk paper trading with leaderboard |
| [ProbeQuiz](./ProbeQuiz) | `QuizPlatform.sol` | Quiz-to-earn with on-chain answer verification |
| [HackathonAgent](./HackathonAgent) | `HackathonManager.sol` | Hackathon platform with multi-judge scoring |
| [AirdropAgent](./AirdropAgent) | `AirdropDistributor.sol` | Merkle-proof airdrop distribution |
| [GrowthAgent](./GrowthAgent) | `GrowthTracker.sol` | Ecosystem growth metrics tracking |
| [ReferralProbe](./ReferralProbe) | `ReferralSystem.sol` | Two-tier referral reward system |
| [MentorMatch](./MentorMatch) | `MentorPlatform.sol` | Developer mentorship matching |
| [ProbeNewsletter](./ProbeNewsletter) | `NewsletterDAO.sol` | Newsletter subscription DAO |
| [ProbeGlossary](./ProbeGlossary) | `GlossaryRegistry.sol` | Ecosystem terminology with translations |

### 🔗 Infrastructure & Utilities

Core protocol infrastructure, bridges, governance, oracles, and shared services.

| Dapp | Contract | Description |
|------|----------|-------------|
| [OracleAgent](./OracleAgent) | `OracleConsensus.sol` | Multi-source oracle with median aggregation |
| [ProbeOracle2](./ProbeOracle2) | `PriceFeed.sol` | Price feed oracle with TWAP support |
| [BridgeAI](./BridgeAI) | `BridgeLock.sol` | Cross-chain bridge with multi-relayer consensus |
| [ProbeNFTBridge](./ProbeNFTBridge) | `NFTBridge.sol` | NFT cross-chain bridge lock |
| [ProbeWrapped](./ProbeWrapped) | `TokenWrapper.sol` | WETH-pattern wrapper for native PROBE |
| [TokenFactory](./TokenFactory) | `TokenFactory.sol` | One-click ERC-20 token creation |
| [NFTFactory](./NFTFactory) | `NFTFactory.sol` | One-click ERC-721 collection creation |
| [ProbeMultisig](./ProbeMultisig) | `MultiSigWallet.sol` | Multi-signature wallet |
| [TimeLock](./TimeLock) | `TimeLockController.sol` | Timelock controller for protocol governance |
| [ProbeVesting](./ProbeVesting) | `VestingContract.sol` | Token vesting with cliff and linear release |
| [ProbeEscrow](./ProbeEscrow) | `EscrowService.sol` | Three-party escrow service |
| [ProbeLocker](./ProbeLocker) | `TokenLocker.sol` | Token lock with time-based unlock |
| [ProbeGovernance](./ProbeGovernance) | `ProtocolGovernor.sol` | Protocol governance with timelock |
| [ProbeTreasury](./ProbeTreasury) | `TreasuryManager.sol` | DAO treasury management |
| [ProbeReward](./ProbeReward) | `RewardDistributor.sol` | Universal multi-pool reward distributor |
| [ProbeFee](./ProbeFee) | `FeeCollector.sol` | Protocol-wide fee collection and management |
| [ProbeRegistry](./ProbeRegistry) | `NameRegistry.sol` | ENS-like name registry for ProbeChain |
| [ProbeRandom](./ProbeRandom) | `RandomnessOracle.sol` | Verifiable randomness oracle (VRF pattern) |
| [ProbeAccess](./ProbeAccess) | `AccessControl.sol` | Role-based access control with hierarchy |
| [ProbeProxy](./ProbeProxy) | `UpgradeableProxy.sol` | EIP-1967 transparent upgradeable proxy |
| [ProbeRelay](./ProbeRelay) | `GaslessRelay.sol` | EIP-712 meta-transaction relay for gasless UX |
| [ProbeToken](./ProbeToken) | `ProbeUtilities.sol` | Batch transfer and multicall utilities |
| [ProbeScheduler](./ProbeScheduler) | `CronScheduler.sol` | Cron job scheduler with keeper incentives |
| [ProbeScheduler2](./ProbeScheduler2) | `AdvancedScheduler.sol` | Advanced one-time and recurring task scheduler |
| [ProbeGas](./ProbeGas) | `GasOptimizer.sol` | Gas estimation and batch transaction optimizer |
| [GoldReserve](./GoldReserve) | `GoldReserveTracker.sol` | ProbeChain gold reserve and decay tracking |
| [NodeRegistry](./NodeRegistry) | `NodeRegistry.sol` | Validator/Agent/Physical node registry |
| [ChainLogger](./ChainLogger) | `EventLogger.sol` | Immutable categorized event logging |
| [GasTracker](./GasTracker) | `GasAnalytics.sol` | Historical gas price analytics |
| [ProbeMetrics](./ProbeMetrics) | `EcosystemMetrics.sol` | Ecosystem health dashboard metrics |
| [ProbeLeaderboard](./ProbeLeaderboard) | `Leaderboard.sol` | Global multi-board leaderboard system |
| [AlertBot](./AlertBot) | `AlertSubscription.sol` | On-chain alert subscriptions with callbacks |
| [WhaleWatch](./WhaleWatch) | `WhaleTracker.sol` | Whale wallet activity monitoring |
| [SentimentProbe](./SentimentProbe) | `SentimentOracle.sol` | Market sentiment oracle with weighted scoring |
| [TokenRadar](./TokenRadar) | `TokenScorer.sol` | New token risk scoring by auditor consensus |
| [AuditAgent](./AuditAgent) | `AuditRegistry.sol` | Smart contract audit registry with severity levels |
| [ProbeReport](./ProbeReport) | `ResearchNFT.sol` | Research report NFTs with citation tracking |
| [QuantumMesh](./QuantumMesh) | `ComputeReservation.sol` | Future compute capacity reservation |
| [ProbeMap](./ProbeMap) | `MapContributions.sol` | Decentralized mapping with POI verification |
| [ProbeWatch](./ProbeWatch) | `SurveillanceMarket.sol` | Surveillance data marketplace |
| [ProbeAvatar](./ProbeAvatar) | `DynamicAvatar.sol` | Dynamic NFT avatars that evolve on-chain |
| [CollectorAgent](./CollectorAgent) | `CollectionAdvisor.sol` | NFT collection analysis and alerts |
| [ProbeRent](./ProbeRent) | `NFTRental.sol` | NFT rental protocol with collateral |
| [MintBot](./MintBot) | `MintAdvisor.sol` | Strategic NFT mint advisory |
| [TicketProbe](./TicketProbe) | `TicketNFT.sol` | Anti-scalp event ticket NFTs |

---

## Project Structure

Each Agent Dapp follows a standard structure:

```
DappName/
├── contracts/
│   └── ContractName.sol      # Solidity 0.8.24, EVM London
├── scripts/
│   └── deploy.ts             # Hardhat deployment script
├── hardhat.config.ts          # Rydberg testnet configuration
├── package.json               # Dependencies
├── tsconfig.json              # TypeScript config
├── .env.example               # Environment template
└── README.md                  # Documentation
```

## Contributing

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/ProbeBuilders.git

# Create a new Agent Dapp
mkdir MyNewDapp && cd MyNewDapp
# Follow the standard structure above

# Test
npx hardhat compile
npx hardhat test

# Submit PR
```

## Links

| Resource | URL |
|----------|-----|
| **Portal** | [probe.builders](https://probe.builders) |
| **Explorer** | [proscan.pro/rydberg](https://proscan.pro/rydberg) |
| **Faucet** | [proscan.pro/rydberg/faucet](https://proscan.pro/rydberg/faucet) |
| **ProbeChain** | [probechain.org](https://probechain.org) |
| **GitHub** | [github.com/ProbeChain](https://github.com/ProbeChain) |
| **X (Twitter)** | [@AioaiN](https://x.com/AioaiN) |

---

<p align="center">
  <sub>Built with 🔥 by <a href="https://probechain.org">ProbeChain</a> Agent Nodes — Proof of Behavior V3.0</sub>
</p>
