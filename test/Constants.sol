// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Constants {
    uint256 internal constant USE_BLOCK = 2476379;

    uint40 maximumNumberOfDepositsPerRound = 50;
    uint40 maximumNumberOfParticipantsPerRound = 50;
    uint40 roundDuration = 3600;
    uint256 valuePerEntry = 10000000000000000;
    uint16 protocolFeeBp = 2_500;
    address entropy = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;
    address entropyProvider = 0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344;
    address pythContract = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
    address weth = 0x4200000000000000000000000000000000000023;
    bytes32 randomhex1 = 0xf419b4f91f5c842b5312f3b4e80d72cb8005e1d6bbf5078ff52115e6e88eb58f;
    bytes32 userCommitment1 = 0xe7777c75c0a6f1ba489c769d213b9c5cbf31ae236404917c1a14e63eb5998427;
    bytes32 randomhex2 = 0x79b029406af43b11937bca98c49633f9382ed7d3fc0d60e110258c5c8f0d1a05;
    bytes32 userCommitment2 = 0xd4bca63083f9fb9e83e68348cb48f45babd820fc3559c60ba9a67b0ab3845cea;
    bytes32 providerRandom = 0xc0d1b24ce5a3041a25be4c15458a6210971d5e940856b37faf900d2dc8605dff;

    address internal constant UNISWAP_V3_NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant WMATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address internal constant MATIC = 0x0000000000000000000000000000000000001010;
    address internal constant MY_EOA = 0x42d8C4BA2f3E2c90D0a7045c25f36D67445f96b2;
    address internal constant MY_USDT = 0x9EC3c43006145f5701d4FD527e826131778cA122;

    address internal constant UNISWAP_V3_POOL_WMATIC_MY_USDT = 0x680752645E785B727E9E6Bf1D9d21C5F56175096;

    uint24 internal constant FEE_3000 = 3000;
    int24 internal constant UNISWAP_FULL_RANGE_TICK_LOWER = -887220;
    int24 internal constant UNISWAP_FULL_RANGE_TICK_UPPER = 887220;
    uint256 internal constant AMOUNT_A_DESIRED = 100e15;
    uint256 internal constant AMOUNT_B_DESIRED = 100e18;
    uint256 internal constant AMOUNT_A_MIN = (AMOUNT_A_DESIRED * 8) / 10;
    uint256 internal constant AMOUNT_B_MIN = (AMOUNT_B_DESIRED * 8) / 10;

    uint160 internal constant SQRT_STOP_PRICE_X96_SELL = SQRT_CURRENT_PRICE_X96 * 2;
    uint160 internal constant SQRT_STOP_PRICE_X96_BUY = SQRT_CURRENT_PRICE_X96 / 2;

    uint160 internal constant SQRT_CURRENT_PRICE_X96 = 2505413655765166104103837312489; // fixed price on USE_BLOCK
}
