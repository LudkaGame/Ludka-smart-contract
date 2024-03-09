// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2, StdStyle, Vm} from "../lib/forge-std/src/Test.sol";
import {Ludka} from "../src/Ludka.sol";
import {ILudka} from "../src/interfaces/ILudka.sol";
import {Constants} from "./Constants.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";

contract TestLudka is Test, Constants {
    Ludka public ludka;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public david = makeAddr("david");

    event Paused(address account);
    event Unpaused(address account);

    modifier asPrankedUser(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        vm.createSelectFork("https://sepolia.blast.io", USE_BLOCK);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(david, 10 ether);

        ludka = new Ludka(
            alice,
            alice,
            maximumNumberOfDepositsPerRound,
            maximumNumberOfParticipantsPerRound,
            roundDuration,
            valuePerEntry,
            alice,
            protocolFeeBp,
            entropy,
            entropyProvider,
            pythContract,
            weth
        );
    }

    function testDeposit() public {
        vm.prank(bob);
        (ILudka.RoundStatus status,,,, uint40 numberOfParticipants,,,,,) = ludka.rounds(1);
        ludka.deposit{value: valuePerEntry}(1);
        (status,,,, numberOfParticipants,,,,,) = ludka.rounds(1);
        console2.log(ludka.sequenceNumber());
        assertEq(uint8(status), 1);
        assertEq(numberOfParticipants, 1);
    }

    function testtogglePaused() public asPrankedUser(alice) {
        ludka.togglePaused();
        assertTrue(ludka.paused());
    }

    function testDrawWinner() public asPrankedUser(alice) {
        uint256 roundId = uint256(ludka.roundsCount());
        (ILudka.RoundStatus status, address winner,,, uint40 numberOfParticipants,,,,,) = ludka.rounds(roundId);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(bob);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(david);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.warp(block.timestamp + 3600);
        ludka.getSequenceNumber(roundId, userCommitment1);
        (status, winner,,, numberOfParticipants,,,,,) = ludka.rounds(roundId);
        console2.log(winner);
        assertTrue(winner == address(0));
        ludka.drawWinner(randomhex1, providerRandom);
        (status, winner,,, numberOfParticipants,,,,,) = ludka.rounds(roundId);
        console2.log(winner);
        assertFalse(winner == address(0));
        assertEq(ludka.roundsCount(), roundId + 1);
    }

    function test_claimPrizes() public {
        testDrawWinner();
        uint256 roundId = uint256(ludka.roundsCount()) - 1;
        ludka.deposit{value: valuePerEntry}(ludka.roundsCount()); // for more eth on ludka becose we pay 101 wey for PYTH SequenceNumber
        ludka.getDeposits(roundId);
        ILudka.Deposit[] memory deposits = ludka.getDeposits(roundId);
        uint256[] memory winnerIndices = new uint256[](deposits.length);
        for (uint256 i; i < deposits.length; i++) {
            winnerIndices[i] = i;
        }
        /*         ILudka.ClaimPrizesCalldata[] memory claimPrizesCalldata = new ILudka.ClaimPrizesCalldata[](1);
        claimPrizesCalldata[0].roundId = roundId;
        claimPrizesCalldata[0].prizeIndices = winnerIndices; */

        vm.stopPrank();
        vm.prank(david);

        ludka.claimPrizes(roundId, winnerIndices);

        assertTrue(david.balance > 10 ether);
    }

    function test_getSequenceNumberfNotOpertor() public asPrankedUser(alice) {
        uint256 roundId = uint256(ludka.roundsCount());
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(bob);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(david);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.warp(block.timestamp + 3600);
        vm.expectRevert();
        ludka.getSequenceNumber(roundId, userCommitment1);
    }

    function test_drawWinnerifNotOpertor() public asPrankedUser(alice) {
        uint256 roundId = uint256(ludka.roundsCount());
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(bob);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.prank(david);
        ludka.deposit{value: 10 * valuePerEntry}(roundId);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.warp(block.timestamp + 3600);
        ludka.getSequenceNumber(roundId, userCommitment1);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert();
        ludka.drawWinner(randomhex1, providerRandom);
    }

    function test_pause_RevertIf_NotOwner() public asPrankedUser(bob) {
        vm.expectRevert();
        ludka.togglePaused();
    }

    function test_unpause() public asPrankedUser(alice) {
        ludka.togglePaused();
        assertTrue(ludka.paused());
        ludka.togglePaused();
        assertFalse(ludka.paused());
    }

    function expectEmitCheckAll() internal {
        vm.expectEmit({checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: true});
    }

    function expectEmitOnlyOne() internal {
        vm.expectEmit({checkTopic1: false, checkTopic2: false, checkTopic3: false, checkData: false});
    }
}
