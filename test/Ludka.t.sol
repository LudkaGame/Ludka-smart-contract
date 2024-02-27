// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2, StdStyle, Vm} from "../lib/forge-std/src/Test.sol";
import {Ludka} from "../src/Ludka.sol";
import {ILudka} from "../src/interfaces/ILudka.sol";
import {Constants} from "./Constants.sol";

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
        /* RoundStatus status = ludka.rounds.status; */
        vm.prank(bob);
        (ILudka.RoundStatus status,,,, uint40 numberOfParticipants,,,,,) = ludka.rounds(1);
        ludka.deposit{value: valuePerEntry}(
            1, userCommitment1, 0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0, 0
        );
        (status,,,, numberOfParticipants,,,,,) = ludka.rounds(1);
        assertEq(uint8(status), 1);
        assertEq(numberOfParticipants, 1);
    }

    function testtogglePaused() public asPrankedUser(alice) {
        ludka.togglePaused();
        assertTrue(ludka.paused());
    }

    function testDrawWinner() public asPrankedUser(alice) {
        ludka.deposit{value: valuePerEntry}(
            1, userCommitment1, 0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0, 0
        );
        vm.stopPrank();
        vm.prank(bob);
        ludka.deposit{value: valuePerEntry}(
            1, userCommitment1, 0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0, 0
        );
        vm.stopPrank();
        vm.prank(david);
        ludka.deposit{value: valuePerEntry}(
            1, userCommitment1, 0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0, 0
        );
        vm.stopPrank();
        vm.prank(alice);
        vm.warp(block.timestamp + 3600);
        ludka.drawWinner(
            0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0,
            0xc0d1b24ce5a3041a25be4c15458a6210971d5e940856b37faf900d2dc8605dff
        );
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
