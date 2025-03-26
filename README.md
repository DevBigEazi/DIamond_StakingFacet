[![Mentioned in Awesome Foundry](https://awesome.re/mentioned-badge-flat.svg)](https://github.com/crisgarner/awesome-foundry)
# Foundry Diamonds Staking Platform
This is a flexible multi-token staking implementation using [Diamonds](https://github.com/ethereum/EIPs/issues/2535) pattern with AppStorage for shared state across facets.
## Installation
- Clone this repo
- Install dependencies
```bash
$ forge install
```
### Compile
```bash
$ forge build
```
## Deployment
### Foundry
```bash
$ forge script scripts/DeployDiamond.s.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY>
```
### Testing
```bash
$ forge test
```
`Note`: The staking platform supports ERC20, ERC721, and ERC1155 tokens with customizable reward mechanisms, time-based decay, and cooldown periods. The platform includes security features like ReentrancyGuard and proper implementation of receiver interfaces.

Need some more clarity? Join the [EIP-2535 Diamonds Discord server](https://discord.gg/kQewPw2)
