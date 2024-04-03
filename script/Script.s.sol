// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2, StdStyle, Vm} from "../lib/forge-std/src/Test.sol";
import {Script} from "forge-std/Script.sol";
import {Ludka} from "../src/Ludka.sol";
import {ILudka} from "../src/interfaces/ILudka.sol";
import {Constants} from "./Constants.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";

contract MyScript is Script {
    address public alice = makeAddr("alice");

    function run(
        address owner,
        address operator,
        uint40 maximumNumberOfDepositsPerRound,
        uint40 maximumNumberOfParticipantsPerRound,
        uint40 roundDuration,
        uint256 valuePerEntry,
        address protocolFeeRecipient,
        uint16 protocolFeeBp,
        address entropy,
        address entropyProvider,
        address pythContract,
        address weth
    ) external returns (Ludka) {
        vm.startBroadcast();
        Ludka ludka = new Ludka(
            owner,
            operator,
            maximumNumberOfDepositsPerRound,
            maximumNumberOfParticipantsPerRound,
            roundDuration,
            valuePerEntry,
            protocolFeeRecipient,
            protocolFeeBp,
            entropy,
            entropyProvider,
            pythContract,
            weth
        );
        vm.stopBroadcast();
        return (ludka);
    }
}
