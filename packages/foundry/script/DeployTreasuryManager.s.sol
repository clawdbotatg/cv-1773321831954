//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TreasuryManager.sol";

contract DeployTreasuryManager is ScaffoldETHDeploy {
    // Base mainnet addresses
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address constant TUSD = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07;
    address constant POOL = 0xd013725b904e76394A3aB0334Da306C505D778F8;
    address constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    function run() external ScaffoldEthDeployerRunner {
        // Default caps: 0.5 ETH per action, 2 ETH per day, 10 min cooldown
        address owner = vm.envOr("TREASURY_OWNER", msg.sender);
        uint256 maxPerAction = vm.envOr("MAX_SPEND_PER_ACTION", uint256(0.5 ether));
        uint256 maxPerDay = vm.envOr("MAX_SPEND_PER_DAY", uint256(2 ether));
        uint256 cooldown = vm.envOr("COOLDOWN_PERIOD", uint256(600)); // 10 minutes

        TreasuryManager treasury = new TreasuryManager(
            owner,
            UNISWAP_ROUTER,
            POOL,
            POSITION_MANAGER,
            WETH_BASE,
            TUSD,
            maxPerAction,
            maxPerDay,
            cooldown
        );
        console.logString(string.concat("TreasuryManager deployed at: ", vm.toString(address(treasury))));
    }
}
