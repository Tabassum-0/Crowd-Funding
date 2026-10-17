// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";

contract Deploy is Script {
    function run() external returns (Crowdfunding cf) {
        vm.startBroadcast();
        cf = new Crowdfunding();
        vm.stopBroadcast();

        console2.log("Crowdfunding deployed at:", address(cf));
    }
}
