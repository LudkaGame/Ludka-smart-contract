// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import "../src/Ludka.sol";

contract MyScript is Script {
    address owner = 0x737122B2228E3c8Fe8931b705713a5450D544C1C;
    address operator = 0x737122B2228E3c8Fe8931b705713a5450D544C1C;
    uint40 _maximumNumberOfDepositsPerRound = 50;
    uint40 _maximumNumberOfParticipantsPerRound = 50;
    uint40 _roundDuration = 3600;
    uint256 _valuePerEntry = 10000000000000000;
    address _protocolFeeRecipient = 0x737122B2228E3c8Fe8931b705713a5450D544C1C;
    uint16 _protocolFeeBp = 500;
    address _entropy = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;
    address _entropyProvider = 0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344;
    address _pythContract = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
    address _weth = 0x4200000000000000000000000000000000000023;
    string PRIVATE_KEY =
        "452a760e91e5d5acd90990d4b58a33afb4c777fd277aae0d80c2b470979568eb";

    function run() external {
        Ludka ludka = new Ludka(
            owner,
            operator,
            _maximumNumberOfDepositsPerRound,
            _maximumNumberOfParticipantsPerRound,
            _roundDuration,
            _valuePerEntry,
            _protocolFeeRecipient,
            _protocolFeeBp,
            _entropy,
            _entropyProvider,
            _pythContract,
            _weth
        );
    }
}
