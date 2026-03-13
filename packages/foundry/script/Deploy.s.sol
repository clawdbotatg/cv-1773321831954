//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployBurnEngine } from "./DeployBurnEngine.s.sol";
import { DeployTreasuryManager } from "./DeployTreasuryManager.s.sol";

contract DeployScript is ScaffoldETHDeploy {
  function run() external {
    DeployBurnEngine deployBurnEngine = new DeployBurnEngine();
    deployBurnEngine.run();

    DeployTreasuryManager deployTreasuryManager = new DeployTreasuryManager();
    deployTreasuryManager.run();
  }
}
